import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Inference modes
enum GpuMode { auto, gpu, cpu }

/// A single token delta from streaming inference
typedef TokenCallback = void Function(String token);

/// LlamaService manages the llama_cpp_dart lifecycle:
///   - model loading (with GPU layer offload)
///   - streaming chat completion via LlamaParent (non-blocking Flutter isolate)
///   - setup state (first-run detection)
///
/// Embedding generation uses a separate [EmbeddingService] instance
/// that loads the embedding GGUF with embeddingMode:true.
class LlamaService extends ChangeNotifier {
  static const _setupKey = 'inhauski_setup_complete';
  static const _modelPathKey = 'inhauski_model_path';
  static const _gpuModeKey = 'inhauski_gpu_mode';
  static const _defaultNGpuLayers = 99; // offload all layers to GPU

  bool _isSetupComplete = false;
  bool _isModelLoaded = false;
  bool _isInferring = false;
  String? _modelPath;
  GpuMode _gpuMode = GpuMode.auto;
  String? _errorMessage;

  LlamaParent? _llamaParent;

  bool get isSetupComplete => _isSetupComplete;
  bool get isModelLoaded => _isModelLoaded;
  bool get isInferring => _isInferring;
  String? get modelPath => _modelPath;
  GpuMode get gpuMode => _gpuMode;
  String? get errorMessage => _errorMessage;

  LlamaService() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _isSetupComplete = prefs.getBool(_setupKey) ?? false;
    _modelPath = prefs.getString(_modelPathKey);
    final gpuStr = prefs.getString(_gpuModeKey) ?? 'auto';
    _gpuMode = GpuMode.values.firstWhere(
      (e) => e.name == gpuStr,
      orElse: () => GpuMode.auto,
    );
    notifyListeners();

    // Auto-load model if setup is complete and path is known
    if (_isSetupComplete && _modelPath != null) {
      await loadModel(_modelPath!);
    }
  }

  /// Mark setup as complete and persist the model path.
  Future<void> completeSetup({
    required String modelPath,
    required GpuMode gpuMode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupKey, true);
    await prefs.setString(_modelPathKey, modelPath);
    await prefs.setString(_gpuModeKey, gpuMode.name);
    _isSetupComplete = true;
    _modelPath = modelPath;
    _gpuMode = gpuMode;
    notifyListeners();
    await loadModel(modelPath);
  }

  /// Reset setup (for testing / settings screen).
  Future<void> resetSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_setupKey);
    await prefs.remove(_modelPathKey);
    _isSetupComplete = false;
    _isModelLoaded = false;
    _modelPath = null;
    _llamaParent?.dispose();
    _llamaParent = null;
    notifyListeners();
  }

  /// Change the GPU mode and immediately reload the model with the new setting.
  Future<void> setGpuMode(GpuMode mode) async {
    if (mode == _gpuMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gpuModeKey, mode.name);
    _gpuMode = mode;
    notifyListeners();
    if (_modelPath != null) {
      _isModelLoaded = false;
      notifyListeners();
      await loadModel(_modelPath!);
    }
  }

  /// Load a GGUF model file from [path].
  ///
  /// Uses [LlamaParent] which runs inference in a background isolate so the
  /// Flutter UI thread is never blocked.
  Future<void> loadModel(String path) async {
    _errorMessage = null;
    notifyListeners();

    try {
      final modelFile = File(path);
      if (!await modelFile.exists()) {
        throw Exception('Model file not found: $path');
      }

      final nGpuLayers = _gpuMode == GpuMode.cpu ? 0 : _defaultNGpuLayers;
      final nThreads = Platform.numberOfProcessors > 4 ? 4 : 2;

      // Dispose previous instance if any
      _llamaParent?.dispose();
      _llamaParent = null;

      final loadCmd = LlamaLoad(
        path: path,
        modelParams: ModelParams()..nGpuLayers = nGpuLayers,
        contextParams: ContextParams()
          ..nCtx = 4096
          ..nBatch = 512
          ..nThreads = nThreads,
        samplingParams: SamplerParams()..temp = 0.7,
      );

      _llamaParent = LlamaParent(loadCmd);
      await _llamaParent!.init();

      _isModelLoaded = true;
      _modelPath = path;
      debugPrint('[LlamaService] Model loaded: $path (ngl=$nGpuLayers)');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Model load error: $e';
      debugPrint('[LlamaService] Load error: $_errorMessage');
      notifyListeners();
      rethrow;
    }
  }

  /// Stream a chat completion.
  ///
  /// Formats [messages] into a single prompt string and streams tokens back
  /// via [onToken], resolving when the response is complete.
  Future<void> chat({
    required List<Map<String, String>> messages,
    required TokenCallback onToken,
    int maxTokens = 2048,
    double temperature = 0.7,
  }) async {
    if (!_isModelLoaded || _llamaParent == null) {
      throw StateError('Model not loaded');
    }
    if (_isInferring) throw StateError('Already inferring');

    _isInferring = true;
    notifyListeners();

    try {
      final prompt = _buildPrompt(messages);

      // Subscribe to the token stream before sending the prompt so we
      // don't miss any early tokens.
      final subscription = _llamaParent!.stream.listen(onToken);

      // sendPrompt triggers inference in the background isolate and resolves
      // when the full response has been generated (returns the prompt ID).
      await _llamaParent!.sendPrompt(prompt);

      // Cancel the subscription once the prompt future has resolved —
      // the response is complete at this point.
      await subscription.cancel();
    } catch (e) {
      _errorMessage = 'Inference error: $e';
      debugPrint('[LlamaService] Inference error: $_errorMessage');
      notifyListeners();
      rethrow;
    } finally {
      _isInferring = false;
      notifyListeners();
    }
  }

  /// Convert role/content message list into a ChatML prompt string.
  String _buildPrompt(List<Map<String, String>> messages) {
    final buf = StringBuffer();
    for (final msg in messages) {
      final role = msg['role'] ?? 'user';
      final content = msg['content'] ?? '';
      switch (role) {
        case 'system':
          buf.write('<|im_start|>system\n$content<|im_end|>\n');
          break;
        case 'assistant':
          buf.write('<|im_start|>assistant\n$content<|im_end|>\n');
          break;
        default: // user
          buf.write('<|im_start|>user\n$content<|im_end|>\n');
      }
    }
    buf.write('<|im_start|>assistant\n');
    return buf.toString();
  }

  /// Get the models directory inside app documents.
  static Future<String> get modelsDirectory async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/models';
  }

  @override
  void dispose() {
    _llamaParent?.dispose(); // returns Future but we can't await in dispose()
    super.dispose();
  }
}
