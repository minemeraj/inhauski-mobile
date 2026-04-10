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

  late LlamaCppDart _llamaCpp;

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

  /// Change the GPU mode and immediately reload the model with the new setting.
  ///
  /// The new mode is persisted so it survives app restarts.
  Future<void> setGpuMode(GpuMode mode) async {
    if (mode == _gpuMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gpuModeKey, mode.name);
    _gpuMode = mode;
    notifyListeners();
    // Reload model with the new GPU layer count if a model is already loaded.
    if (_modelPath != null) {
      _isModelLoaded = false;
      notifyListeners();
      await loadModel(_modelPath!);
    }
  }

  /// Load a GGUF model file from [path].
  ///
  /// GPU layers: 99 (all) in auto/gpu mode, 0 in cpu mode.
  Future<void> loadModel(String path) async {
    _errorMessage = null;
    notifyListeners();

    try {
      final nGpuLayers = _gpuMode == GpuMode.cpu ? 0 : _defaultNGpuLayers;

      // Verify file exists
      final modelFile = File(path);
      if (!await modelFile.exists()) {
        throw Exception('Model file not found: $path');
      }

      // Initialize llama_cpp_dart with GPU acceleration
      _llamaCpp = LlamaCppDart(
        modelPath: path,
        numGpuLayers: nGpuLayers,
        contextSize: 4096,
        batchSize: 512,
        numThreads: Platform.numberOfProcessors > 4 ? 4 : 2,
      );

      debugPrint('[LlamaService] Initializing model: $path (ngl=$nGpuLayers)');
      await _llamaCpp.initialize();

      _isModelLoaded = true;
      _modelPath = path;
      debugPrint('[LlamaService] Model loaded successfully');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Model load error: $e';
      debugPrint('[LlamaService] Load error: $_errorMessage');
      notifyListeners();
      rethrow;
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
      // Format messages for llama_cpp_dart chat completion
      // llama_cpp_dart expects a list of maps with 'role' and 'content'
      final stream = _llamaCpp.generateStream(
        messages: messages,
        maxTokens: maxTokens,
        temperature: temperature,
      );

      await for (final token in stream) {
        onToken(token);
      }
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

  /// Generate an embedding vector for [text].
  /// Returns a float32 list of dimension 384 (for multilingual-e5-small).
  Future<List<double>> embed(String text) async {
    if (!_isModelLoaded) throw StateError('Model not loaded');

    try {
      // Use llama_cpp_dart's embedding capability
      // The embedding model (multilingual-e5-small) produces 384-dim vectors
      final embedding = await _llamaCpp.embed(text);
      return embedding;
    } catch (e) {
      _errorMessage = 'Embedding error: $e';
      debugPrint('[LlamaService] Embedding error: $_errorMessage');
      notifyListeners();
      rethrow;
    }
  }

  /// Get the models directory inside app documents.
  static Future<String> get modelsDirectory async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/models';
  }
}
