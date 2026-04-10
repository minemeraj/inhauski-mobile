import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kEmbedPathKey = 'inhauski_embed_model_path';

/// EmbeddingService manages a dedicated llama.cpp instance loaded with an
/// embedding-optimised GGUF (multilingual-e5-small, ~90 MB, 384 dims).
///
/// Uses [Llama.getEmbeddings] from llama_cpp_dart, which runs the model in
/// embedding mode and returns a normalised float32 vector.
///
/// Keeping the embedding model separate from the chat model means:
///   • The chat model context is never polluted by embedding mode.
///   • The embedding model can be swapped without touching chat settings.
class EmbeddingService extends ChangeNotifier {
  static const int embeddingDimension = 384;

  bool _isLoaded = false;
  bool _isLoading = false;
  String? _modelPath;
  String? _errorMessage;

  Llama? _llama;

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
      await loadModel(path);
    }
  }

  /// Load the embedding GGUF at [path] and persist the path for future starts.
  Future<void> loadModel(String path) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final f = File(path);
      if (!await f.exists()) {
        throw Exception('Embedding model not found: $path');
      }

      // Dispose previous instance if any
      _llama?.dispose();
      _llama = null;

      // Embedding models benefit from all layers on GPU (small model).
      // nCtx = 512 matches e5-small max sequence length.
      _llama = Llama(
        path,
        modelParams: ModelParams()..nGpuLayers = 99,
        contextParams: ContextParams()
          ..nCtx = 512
          ..nBatch = 512
          ..nThreads = 1
          ..embeddings = true, // enable embedding mode in llama.cpp context
      );

      debugPrint('[EmbeddingService] Loading: $path');

      _modelPath = path;
      _isLoaded = true;
      _isLoading = false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kEmbedPathKey, path);

      debugPrint('[EmbeddingService] Ready (dim=$embeddingDimension)');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Embedding model load error: $e';
      _isLoading = false;
      debugPrint('[EmbeddingService] Error: $_errorMessage');
      notifyListeners();
      rethrow;
    }
  }

  /// Embed [text] and return a 384-dim L2-normalised float vector.
  Future<List<double>> embed(String text) async {
    if (!_isLoaded || _llama == null) {
      throw StateError('Embedding model not loaded');
    }
    // getEmbeddings runs synchronously in the calling isolate; it is fast
    // (~5 ms for 384-dim e5-small) so running it on the main isolate is fine.
    // normalize: true → llama.cpp normalises the vector to unit length.
    final vec = _llama!.getEmbeddings(text, normalize: true);
    return _l2Normalize(vec);
  }

  List<double> _l2Normalize(List<double> v) {
    final sumSq = v.fold(0.0, (double s, x) => s + x * x);
    if (sumSq == 0) return v;
    final invNorm = 1.0 / sqrt(sumSq);
    return v.map((x) => x * invNorm).toList();
  }

  /// Remove the persisted path (called from resetSetup).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEmbedPathKey);
    _llama?.dispose();
    _llama = null;
    _isLoaded = false;
    _modelPath = null;
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
    _llama?.dispose();
    super.dispose();
  }
}
