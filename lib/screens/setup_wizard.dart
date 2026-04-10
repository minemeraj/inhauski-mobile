import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/llama_service.dart';
import '../i18n/app_localizations.dart';

/// Model download configuration
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

const _models = [
  _ModelConfig(
    name: 'Gemma 4 E2B Instruct (Q4_K_M)',
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

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  int _step = 0;
  String _selectedLanguage = 'de';
  _ModelConfig _selectedModel = _models[0];
  GpuMode _selectedGpuMode = GpuMode.auto;

  double? _downloadProgress;
  String? _downloadStatus;
  bool _isDownloading = false;

  // ── Step 0: Welcome + Language ────────────────────────────────────────────

  Widget _buildWelcome(AppLocalizations loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock, size: 56, color: Color(0xFF1A73E8)),
        const SizedBox(height: 24),
        Text(loc.setupWelcome,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text(
          loc.setupTagline,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 32),
        Text(loc.setupLanguageLabel,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'de', label: Text('Deutsch')),
            ButtonSegment(value: 'en', label: Text('English')),
          ],
          selected: {_selectedLanguage},
          onSelectionChanged: (s) =>
              setState(() => _selectedLanguage = s.first),
        ),
      ],
    );
  }

  // ── Step 1: Model + GPU ───────────────────────────────────────────────────

  Widget _buildModelSelection(AppLocalizations loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.setupModelChoose,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          loc.setupModelHint,
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 20),
        for (final model in _models) ...[
          RadioListTile<_ModelConfig>(
            title: Text(model.name),
            subtitle: Text(
                '${(model.expectedBytes / 1e9).toStringAsFixed(1)} GB'),
            value: model,
            groupValue: _selectedModel,
            onChanged: (m) => setState(() => _selectedModel = m!),
          ),
        ],
        const SizedBox(height: 20),
        Text(loc.setupGpuLabel,
            style: const TextStyle(fontWeight: FontWeight.w600)),
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

  // ── Step 2: Download ──────────────────────────────────────────────────────

  Widget _buildDownload(AppLocalizations loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.setupDownloading,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_selectedModel.name,
            style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 32),
        if (_isDownloading || _downloadProgress != null) ...[
          LinearProgressIndicator(value: _downloadProgress),
          const SizedBox(height: 12),
          Text(_downloadStatus ?? ''),
        ] else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.download),
              label: Text(loc.setupDownloadButton),
              onPressed: _startDownload,
            ),
          ),
      ],
    );
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadStatus = '…';
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${dir.path}/models');
      await modelsDir.create(recursive: true);

      final filename = _selectedModel.url.split('/').last;
      final destPath = '${modelsDir.path}/$filename';

      // Stream download with progress
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(_selectedModel.url));
      final response = await client.send(request);
      final total = response.contentLength ?? _selectedModel.expectedBytes;

      final sink = File(destPath).openWrite();
      int received = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final pct = received / total;
        final mb = received / 1e6;
        final totalMb = total / 1e6;
        setState(() {
          _downloadProgress = pct;
          _downloadStatus =
              '${(pct * 100).toStringAsFixed(1)}% — ${mb.toStringAsFixed(0)} / ${totalMb.toStringAsFixed(0)} MB';
        });
      }

      await sink.close();
      client.close();

      // Complete setup
      if (mounted) {
        await context.read<LlamaService>().completeSetup(
              modelPath: destPath,
              gpuMode: _selectedGpuMode,
            );
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _downloadStatus = 'Error: $e';
      });
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    final steps = [
      _buildWelcome(loc),
      _buildModelSelection(loc),
      _buildDownload(loc),
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress dots
              Row(
                children: List.generate(
                  steps.length,
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

              // Navigation
              if (_step < 2)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => setState(() => _step++),
                    child: Text(_step == 0 ? loc.setupStartButton : loc.setupContinue),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
