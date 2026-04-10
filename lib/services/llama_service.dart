import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Inference modes
enum GpuMode { auto, gpu, cpu }

/// A single token delta from streaming inference
typedef TokenCallback = void Function(String token);

/// LlamaService manages the llama_cpp_dart lifecycle:
///   - model loading (with GPU layer offload)
///   - streaming chat completion
///   - embedding generation (for RAG)
///   - setup state (first-run detection)
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

  // ignore: unused_field
  Isolate? _llamaIsolate;
  SendPort? _llamaSendPort;

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
    notifyListeners();
  }

  /// Load a GGUF model file from [path].
  ///
  /// GPU layers: 99 (all) in auto/gpu mode, 0 in cpu mode.
  Future<void> loadModel(String path) async {
    _errorMessage = null;
    notifyListeners();

    try {
      final nGpuLayers = _gpuMode == GpuMode.cpu ? 0 : _defaultNGpuLayers;

      // TODO: Replace stub with actual llama_cpp_dart initialization once the
      // package is imported.  Pattern:
      //
      //   final params = LlamaParams(
      //     nGpuLayers: nGpuLayers,
      //     nCtx: 4096,
      //     nBatch: 512,
      //   );
      //   await LlamaContext.load(path, params);
      //
      // For now, simulate success so the UI compiles and runs in emulator.
      await Future.delayed(const Duration(milliseconds: 100));

      debugPrint('[LlamaService] Model loaded: $path (ngl=$nGpuLayers)');
      _isModelLoaded = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('[LlamaService] Load error: $e');
      notifyListeners();
    }
  }

  /// Stream a chat completion.  Yields tokens via [onToken]; resolves when done.
  Future<void> chat({
    required List<Map<String, String>> messages,
    required TokenCallback onToken,
    int maxTokens = 2048,
    double temperature = 0.7,
  }) async {
    if (!_isModelLoaded) throw StateError('Model not loaded');
    if (_isInferring) throw StateError('Already inferring');

    _isInferring = true;
    notifyListeners();

    try {
      // TODO: Replace stub with actual streaming inference.  Pattern:
      //
      //   final stream = LlamaContext.instance.completionStream(
      //     messages: messages,
      //     maxTokens: maxTokens,
      //     temperature: temperature,
      //   );
      //   await for (final token in stream) {
      //     onToken(token);
      //   }
      //
      // Stub: simulate streaming for UI development
      const reply = 'Ich bin InHausKI. Wie kann ich Ihnen helfen?';
      for (final char in reply.split('')) {
        onToken(char);
        await Future.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      _isInferring = false;
      notifyListeners();
    }
  }

  /// Generate an embedding vector for [text].
  /// Returns a float32 list of dimension 768 (nomic-embed-text).
  Future<List<double>> embed(String text) async {
    if (!_isModelLoaded) throw StateError('Model not loaded');

    // TODO: Replace stub with actual embedding call.  Pattern:
    //
    //   return await LlamaContext.instance.embed(text);
    //
    // Stub: return a zero vector
    return List.filled(768, 0.0);
  }

  /// Get the models directory inside app documents.
  static Future<String> get modelsDirectory async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/models';
  }
}
