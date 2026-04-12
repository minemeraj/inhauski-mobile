import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Inference modes
enum GpuMode { auto, gpu, cpu }

/// A single token delta from streaming inference
typedef TokenCallback = void Function(String token);

/// Approximate token count for a string.
/// Uses the common heuristic of 1 token ≈ 4 characters.
int _estimateTokens(String text) => (text.length / 4).ceil();

/// LlamaService manages the llama_cpp_dart lifecycle:
///   - model loading (with GPU layer offload)
///   - streaming chat completion via LlamaParent (non-blocking Flutter isolate)
///   - setup state (first-run detection)
///   - context-window truncation (keeps conversation within [maxContextTokens])
///
/// Embedding generation uses a separate [EmbeddingService] instance
/// that loads the embedding GGUF with embeddingMode:true.
class LlamaService extends ChangeNotifier {
  static const _setupKey = 'inhauski_setup_complete';
  static const _modelPathKey = 'inhauski_model_path';
  static const _gpuModeKey = 'inhauski_gpu_mode';
  static const _modelNameKey = 'inhauski_model_name';
  static const _defaultNGpuLayers = 99; // offload all layers to GPU

  /// Hard context window size in tokens. Leave ~512 tokens for the response.
  static const int _nCtx = 4096;
  static const int _maxPromptTokens = _nCtx - 512;

  bool _isSetupComplete = false;
  bool _isModelLoaded = false;
  bool _isInferring = false;
  String? _modelPath;
  String? _modelName; // display name chosen by user in wizard
  GpuMode _gpuMode = GpuMode.auto;
  String? _errorMessage;

  LlamaParent? _llamaParent;

  bool get isSetupComplete => _isSetupComplete;
  bool get isModelLoaded => _isModelLoaded;
  bool get isInferring => _isInferring;
  String? get modelPath => _modelPath;
  String? get modelName => _modelName;
  GpuMode get gpuMode => _gpuMode;
  String? get errorMessage => _errorMessage;

  LlamaService() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _isSetupComplete = prefs.getBool(_setupKey) ?? false;
    _modelPath = prefs.getString(_modelPathKey);
    _modelName = prefs.getString(_modelNameKey);
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

  /// Mark setup as complete and persist the model path + display name.
  Future<void> completeSetup({
    required String modelPath,
    required GpuMode gpuMode,
    String? modelName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_setupKey, true);
    await prefs.setString(_modelPathKey, modelPath);
    await prefs.setString(_gpuModeKey, gpuMode.name);
    if (modelName != null) await prefs.setString(_modelNameKey, modelName);
    _isSetupComplete = true;
    _modelPath = modelPath;
    _modelName = modelName;
    _gpuMode = gpuMode;
    notifyListeners();
    await loadModel(modelPath);
  }

  /// Reset setup (for testing / settings screen).
  Future<void> resetSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_setupKey);
    await prefs.remove(_modelPathKey);
    await prefs.remove(_modelNameKey);
    // Keep _gpuModeKey so the user's preference is remembered
    _isSetupComplete = false;
    _isModelLoaded = false;
    _modelPath = null;
    _modelName = null;
    _errorMessage = null;
    _llamaParent?.dispose();
    _llamaParent = null;
    notifyListeners();
  }

  /// Change the GPU mode and immediately reload the model with the new setting.
  Future<void> setGpuMode(GpuMode mode) async {
    if (mode == _gpuMode) return;
    // Guard against mode changes while model is loading or inferring
    if (_isInferring) return;
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
    _isModelLoaded = false;
    notifyListeners();

    try {
      final modelFile = File(path);
      if (!await modelFile.exists()) {
        throw Exception('Model file not found: $path');
      }

      final nGpuLayers = _gpuMode == GpuMode.cpu ? 0 : _defaultNGpuLayers;
      // Use at least 1 thread, at most 4 performance threads
      final nThreads = Platform.numberOfProcessors.clamp(1, 4);

      // Dispose previous instance if any
      _llamaParent?.dispose();
      _llamaParent = null;

      final loadCmd = LlamaLoad(
        path: path,
        modelParams: ModelParams()..nGpuLayers = nGpuLayers,
        contextParams: ContextParams()
          ..nCtx = _nCtx
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
      _isModelLoaded = false;
      debugPrint('[LlamaService] Load error: $_errorMessage');
      notifyListeners();
      rethrow;
    }
  }

  /// Stop the current inference if one is running.
  void stopInference() {
    if (!_isInferring || _llamaParent == null) return;
    // Dispose and recreate the parent to abort the background isolate.
    // The next chat() call will re-init automatically.
    _llamaParent?.dispose();
    _llamaParent = null;
    _isModelLoaded = false;
    _isInferring = false;
    notifyListeners();
    // Reload model in background so it's ready for the next message
    if (_modelPath != null) {
      loadModel(_modelPath!);
    }
  }

  /// Stream a chat completion.
  ///
  /// Applies context-window truncation: if the serialised prompt exceeds
  /// [_maxPromptTokens], older non-system messages are dropped from the
  /// front until it fits.
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
      final truncated = _truncateMessages(messages);
      final prompt = _buildPrompt(truncated);

      // Subscribe to the token stream before sending the prompt so we
      // don't miss any early tokens.
      final subscription = _llamaParent!.stream.listen(onToken);

      await _llamaParent!.sendPrompt(prompt);

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

  /// Trim [messages] so the resulting prompt fits within [_maxPromptTokens].
  ///
  /// Strategy: keep the system message (if any) and always the last user
  /// message, then drop the oldest non-system pairs from the front until
  /// the token estimate fits.
  List<Map<String, String>> _truncateMessages(
      List<Map<String, String>> messages) {
    // Fast path: already fits
    final fullPrompt = _buildPrompt(messages);
    if (_estimateTokens(fullPrompt) <= _maxPromptTokens) return messages;

    // Separate system preamble from the rest
    final List<Map<String, String>> system = [];
    final List<Map<String, String>> turns = [];
    for (final m in messages) {
      if (m['role'] == 'system') {
        system.add(m);
      } else {
        turns.add(m);
      }
    }

    // Drop oldest turns until we fit, always keeping at least the last
    // user message.
    while (turns.length > 1) {
      turns.removeAt(0);
      final candidate = [...system, ...turns];
      if (_estimateTokens(_buildPrompt(candidate)) <= _maxPromptTokens) {
        return candidate;
      }
    }

    // Even with only the last message we may exceed the limit (e.g. huge
    // RAG context). Return as-is and let llama.cpp truncate internally.
    return [...system, ...turns];
  }

  /// Convert role/content message list into a Gemma prompt string.
  ///
  /// Gemma instruct models use:
  ///   <start_of_turn>role\n{content}<end_of_turn>\n
  /// The final model turn is left open for the model to complete.
  String _buildPrompt(List<Map<String, String>> messages) {
    final buf = StringBuffer();
    for (final msg in messages) {
      final role = msg['role'] ?? 'user';
      final content = msg['content'] ?? '';
      // Gemma uses 'model' for the assistant role; map system → user for
      // models that don't have a dedicated system role.
      final String templateRole;
      switch (role) {
        case 'assistant':
          templateRole = 'model';
          break;
        case 'system':
          // Gemma 4 has no dedicated system role — prepend as a user turn
          // so the instruction is still respected.
          templateRole = 'user';
          break;
        default:
          templateRole = 'user';
      }
      buf.write('<start_of_turn>$templateRole\n$content<end_of_turn>\n');
    }
    // Open the model turn for the response.
    buf.write('<start_of_turn>model\n');
    return buf.toString();
  }

  /// Get the models directory inside app documents.
  static Future<String> get modelsDirectory async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/models';
  }

  @override
  void dispose() {
    _llamaParent?.dispose();
    super.dispose();
  }
}
