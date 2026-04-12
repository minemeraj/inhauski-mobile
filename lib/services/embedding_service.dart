import 'dart:isolate';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'llama_service.dart' show GpuMode;

const _kEmbedPathKey = 'inhauski_embed_model_path';

// ── Background isolate helpers ────────────────────────────────────────────────

/// Message sent TO the embedding isolate.
class _EmbedRequest {
  final String text;
  final SendPort replyTo;
  const _EmbedRequest(this.text, this.replyTo);
}

/// Message sent FROM the embedding isolate back to the main isolate.
class _EmbedReply {
  final List<double>? vector;
  final String? error;
  const _EmbedReply({this.vector, this.error});
}

/// Top-level isolate entry point — must be a top-level or static function.
void _embeddingIsolateMain(_IsolateBootstrap bootstrap) {
  final llama = Llama(
    bootstrap.modelPath,
    modelParams: ModelParams()..nGpuLayers = bootstrap.nGpuLayers,
    contextParams: ContextParams()
      ..nCtx = 512
      ..nBatch = 512
      ..nThreads = 1
      ..embeddings = true,
  );

  final port = ReceivePort();
  bootstrap.readyPort.send(port.sendPort);

  port.listen((dynamic msg) {
    if (msg is _EmbedRequest) {
      try {
        // llama.cpp normalises internally; we do NOT normalise again.
        final vec = llama.getEmbeddings(msg.text, normalize: true);
        msg.replyTo.send(_EmbedReply(vector: vec));
      } catch (e) {
        msg.replyTo.send(_EmbedReply(error: e.toString()));
      }
    } else if (msg == null) {
      // Shutdown signal
      llama.dispose();
      port.close();
    }
  });
}

class _IsolateBootstrap {
  final String modelPath;
  final int nGpuLayers;
  final SendPort readyPort;
  const _IsolateBootstrap(this.modelPath, this.nGpuLayers, this.readyPort);
}

// ── EmbeddingService ──────────────────────────────────────────────────────────

/// EmbeddingService manages a dedicated llama.cpp instance loaded with an
/// embedding-optimised GGUF (multilingual-e5-small, ~90 MB, 384 dims).
///
/// The model runs in a **background isolate** so embedding never blocks the
/// Flutter UI thread.  Respects the user's [GpuMode] preference.
class EmbeddingService extends ChangeNotifier {
  static const int embeddingDimension = 384;

  bool _isLoaded = false;
  bool _isLoading = false;
  String? _modelPath;
  String? _errorMessage;

  // Background isolate state
  Isolate? _isolate;
  SendPort? _isolateSendPort;

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;
  String? get modelPath => _modelPath;
  String? get errorMessage => _errorMessage;

  EmbeddingService() {
    _tryAutoLoad();
  }

  Future<void> _tryAutoLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_kEmbedPathKey);
    if (path != null && await File(path).exists()) {
      // Default to auto (try GPU) on auto-load; user can change in Settings.
      await loadModel(path, gpuMode: GpuMode.auto);
    }
  }

  /// Load the embedding GGUF at [path] and persist the path for future starts.
  /// Respects [gpuMode]: cpu → nGpuLayers=0, otherwise → 99.
  Future<void> loadModel(String path, {GpuMode gpuMode = GpuMode.auto}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final f = File(path);
      if (!await f.exists()) {
        throw Exception('Embedding model not found: $path');
      }

      // Shut down previous isolate if any
      await _shutdownIsolate();

      final nGpuLayers = gpuMode == GpuMode.cpu ? 0 : 99;

      // Boot the embedding isolate
      final readyPort = ReceivePort();
      _isolate = await Isolate.spawn(
        _embeddingIsolateMain,
        _IsolateBootstrap(path, nGpuLayers, readyPort.sendPort),
        debugName: 'embedding_isolate',
      );

      // Wait for the isolate to signal readiness and hand us its SendPort
      _isolateSendPort = await readyPort.first as SendPort;
      readyPort.close();

      _modelPath = path;
      _isLoaded = true;
      _isLoading = false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kEmbedPathKey, path);

      debugPrint('[EmbeddingService] Ready (dim=$embeddingDimension, ngl=$nGpuLayers)');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Embedding model load error: $e';
      _isLoading = false;
      _isLoaded = false;
      debugPrint('[EmbeddingService] Error: $_errorMessage');
      notifyListeners();
      rethrow;
    }
  }

  /// Embed [text] and return a 384-dim L2-normalised float vector.
  ///
  /// Runs in the background isolate — never blocks the UI thread.
  Future<List<double>> embed(String text) async {
    if (!_isLoaded || _isolateSendPort == null) {
      throw StateError('Embedding model not loaded');
    }
    final replyPort = ReceivePort();
    _isolateSendPort!.send(_EmbedRequest(text, replyPort.sendPort));
    final reply = await replyPort.first as _EmbedReply;
    replyPort.close();
    if (reply.error != null) throw Exception(reply.error);
    return reply.vector!;
  }

  /// Shut down the background isolate gracefully.
  Future<void> _shutdownIsolate() async {
    if (_isolateSendPort != null) {
      _isolateSendPort!.send(null); // shutdown signal
      _isolateSendPort = null;
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  /// Remove the persisted path (called from resetSetup).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEmbedPathKey);
    await _shutdownIsolate();
    _isLoaded = false;
    _modelPath = null;
    _errorMessage = null;
    notifyListeners();
  }

  /// Default filename for the embedding model download.
  static const String defaultFilename = 'multilingual-e5-small-Q8_0.gguf';

  /// Hugging Face download URL for multilingual-e5-small Q8_0 GGUF (~90 MB).
  static const String downloadUrl =
      'https://huggingface.co/leliuga/multilingual-e5-small-GGUF'
      '/resolve/main/multilingual-e5-small-Q8_0.gguf';

  static const int expectedBytes = 92_000_000; // ~90 MB

  /// Canonical storage path under app documents/models/.
  static Future<String> get defaultModelPath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/models/$defaultFilename';
  }

  @override
  void dispose() {
    _shutdownIsolate();
    super.dispose();
  }
}
