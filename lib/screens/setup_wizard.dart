import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/embedding_service.dart';
import '../services/llama_service.dart';
import '../services/locale_service.dart';
import '../i18n/app_localizations.dart';

// ── Model download configurations ─────────────────────────────────────────────

class _ModelConfig {
  final String name;
  final String url;
  final int expectedBytes;
  const _ModelConfig({
    required this.name,
    required this.url,
    required this.expectedBytes,
  });
}

const _chatModels = [
  _ModelConfig(
    name: 'Gemma 4 2B Instruct (Q4_K_M)',
    url:
        'https://huggingface.co/lmstudio-community/gemma-4-2b-it-GGUF/resolve/main/gemma-4-2b-it-Q4_K_M.gguf',
    expectedBytes: 1_500_000_000, // ~1.5 GB
  ),
  _ModelConfig(
    name: 'Gemma 3 2B Instruct (Q4_K_M) — Fallback',
    url:
        'https://huggingface.co/lmstudio-community/gemma-3-2b-it-GGUF/resolve/main/gemma-3-2b-it-Q4_K_M.gguf',
    expectedBytes: 1_500_000_000,
  ),
];

// ── Wizard ────────────────────────────────────────────────────────────────────

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  // Total steps: 0=Language, 1=Model+GPU, 2=Chat download, 3=Embed download
  static const int _totalSteps = 4;

  int _step = 0;
  String _selectedLanguage = 'de';
  _ModelConfig _selectedChatModel = _chatModels[0];
  GpuMode _selectedGpuMode = GpuMode.auto;

  // Chat model download state
  double? _chatDownloadProgress;
  String? _chatDownloadStatus;
  bool _isChatDownloading = false;

  // Embedding model download state
  double? _embedDownloadProgress;
  String? _embedDownloadStatus;
  bool _isEmbedDownloading = false;
  bool _embedDownloadDone = false;

  // ── Step 0: Welcome + Language ────────────────────────────────────────────

  Widget _buildWelcome(AppLocalizations loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock, size: 56, color: Color(0xFF1A73E8)),
        const SizedBox(height: 24),
        Text(
          loc.setupWelcome,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Text(
          loc.setupTagline,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 32),
        Text(
          loc.setupLanguageLabel,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'de', label: Text('Deutsch')),
            ButtonSegment(value: 'en', label: Text('English')),
          ],
          selected: {_selectedLanguage},
          onSelectionChanged: (s) {
            final code = s.first;
            setState(() => _selectedLanguage = code);
            // Immediately apply locale so subsequent wizard steps render
            // in the chosen language.
            context.read<LocaleService>().setLocale(code);
          },
        ),
      ],
    );
  }

  // ── Step 1: Model + GPU ───────────────────────────────────────────────────

  Widget _buildModelSelection(AppLocalizations loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.setupModelChoose,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          loc.setupModelHint,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        for (final model in _chatModels) ...[
          RadioListTile<_ModelConfig>(
            title: Text(model.name),
            subtitle: Text(
                '${(model.expectedBytes / 1e9).toStringAsFixed(1)} GB'),
            value: model,
            groupValue: _selectedChatModel,
            onChanged: (m) => setState(() => _selectedChatModel = m!),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          loc.setupGpuLabel,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SegmentedButton<GpuMode>(
          segments: const [
            ButtonSegment(value: GpuMode.auto, label: Text('Auto')),
            ButtonSegment(value: GpuMode.gpu, label: Text('GPU')),
            ButtonSegment(value: GpuMode.cpu, label: Text('CPU')),
          ],
          selected: {_selectedGpuMode},
          onSelectionChanged: (s) =>
              setState(() => _selectedGpuMode = s.first),
        ),
      ],
    );
  }

  // ── Step 2: Chat model download ───────────────────────────────────────────

  Widget _buildChatDownload(AppLocalizations loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.setupDownloading,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _selectedChatModel.name,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 32),
        if (_isChatDownloading || _chatDownloadProgress != null) ...[
          LinearProgressIndicator(value: _chatDownloadProgress),
          const SizedBox(height: 12),
          Text(_chatDownloadStatus ?? ''),
        ] else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.download),
              label: Text(loc.setupDownloadButton),
              onPressed: _startChatDownload,
            ),
          ),
      ],
    );
  }

  Future<void> _startChatDownload() async {
    setState(() {
      _isChatDownloading = true;
      _chatDownloadProgress = 0;
      _chatDownloadStatus = '…';
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${dir.path}/models');
      await modelsDir.create(recursive: true);

      final filename = _selectedChatModel.url.split('/').last;
      final destPath = '${modelsDir.path}/$filename';

      final client = http.Client();
      final request =
          http.Request('GET', Uri.parse(_selectedChatModel.url));
      final response = await client.send(request);
      final total =
          response.contentLength ?? _selectedChatModel.expectedBytes;

      final sink = File(destPath).openWrite();
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final pct = received / total;
        final mb = received / 1e6;
        final totalMb = total / 1e6;
        if (mounted) {
          setState(() {
            _chatDownloadProgress = pct;
            _chatDownloadStatus =
                '${(pct * 100).toStringAsFixed(1)}% — '
                '${mb.toStringAsFixed(0)} / '
                '${totalMb.toStringAsFixed(0)} MB';
          });
        }
      }

      await sink.close();
      client.close();

      // Persist model path + GPU mode; this also triggers model load.
      if (mounted) {
        await context.read<LlamaService>().completeSetup(
              modelPath: destPath,
              gpuMode: _selectedGpuMode,
            );
        setState(() => _step++); // advance to embed step
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isChatDownloading = false;
          _chatDownloadStatus = 'Error: $e';
        });
      }
    }
  }

  // ── Step 3: Embedding model download (skippable) ──────────────────────────

  Widget _buildEmbedDownload(AppLocalizations loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.setupEmbedTitle,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          loc.setupEmbedHint,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 32),
        if (_embedDownloadDone) ...[
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                EmbeddingService.defaultFilename,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ] else if (_isEmbedDownloading ||
            _embedDownloadProgress != null) ...[
          LinearProgressIndicator(value: _embedDownloadProgress),
          const SizedBox(height: 12),
          Text(_embedDownloadStatus ?? ''),
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.download),
              label: Text(loc.setupDownloadButton),
              onPressed: _startEmbedDownload,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _finishSetup,
              child: Text(loc.setupEmbedSkip),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _startEmbedDownload() async {
    setState(() {
      _isEmbedDownloading = true;
      _embedDownloadProgress = 0;
      _embedDownloadStatus = '…';
    });

    try {
      final destPath = await EmbeddingService.defaultModelPath;
      final modelsDir = Directory(destPath).parent;
      await modelsDir.create(recursive: true);

      final client = http.Client();
      final request =
          http.Request('GET', Uri.parse(EmbeddingService.downloadUrl));
      final response = await client.send(request);
      final total =
          response.contentLength ?? EmbeddingService.expectedBytes;

      final sink = File(destPath).openWrite();
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final pct = received / total;
        final mb = received / 1e6;
        final totalMb = total / 1e6;
        if (mounted) {
          setState(() {
            _embedDownloadProgress = pct;
            _embedDownloadStatus =
                '${(pct * 100).toStringAsFixed(1)}% — '
                '${mb.toStringAsFixed(0)} / '
                '${totalMb.toStringAsFixed(0)} MB';
          });
        }
      }

      await sink.close();
      client.close();

      // Load the embedding model immediately after download.
      if (mounted) {
        await context.read<EmbeddingService>().loadModel(destPath);
        setState(() {
          _embedDownloadDone = true;
          _isEmbedDownloading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEmbedDownloading = false;
          _embedDownloadStatus = 'Error: $e';
        });
      }
    }
  }

  void _finishSetup() {
    // Setup is already marked complete by completeSetup() in step 2.
    // main.dart will transition away from SetupWizard because
    // LlamaService.isSetupComplete is now true.
    // Nothing extra needed here — the Consumer in main.dart reacts.
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    final steps = [
      _buildWelcome(loc),
      _buildModelSelection(loc),
      _buildChatDownload(loc),
      _buildEmbedDownload(loc),
    ];

    // Bottom button logic:
    //   step 0 → "Los geht's" / "Let's go"
    //   step 1 → "Weiter" / "Continue"
    //   step 2 → no button (download drives navigation)
    //   step 3 → "Fertig" / "Finish" (only after download or always as fallback)
    Widget? bottomButton;
    if (_step == 0) {
      bottomButton = FilledButton(
        onPressed: () => setState(() => _step++),
        child: Text(loc.setupStartButton),
      );
    } else if (_step == 1) {
      bottomButton = FilledButton(
        onPressed: () => setState(() => _step++),
        child: Text(loc.setupContinue),
      );
    } else if (_step == 3 && _embedDownloadDone) {
      bottomButton = FilledButton(
        onPressed: _finishSetup,
        child: Text(loc.setupFinish),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress bar
              Row(
                children: List.generate(
                  _totalSteps,
                  (i) => Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i <= _step
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Step content
              Expanded(child: steps[_step]),

              // Navigation button (null on download steps)
              if (bottomButton != null)
                SizedBox(width: double.infinity, child: bottomButton),
            ],
          ),
        ),
      ),
    );
  }
}
