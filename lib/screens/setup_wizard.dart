import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/embedding_service.dart';
import '../services/llama_service.dart';
import '../services/locale_service.dart';
import '../services/model_download_service.dart';
import '../i18n/app_localizations.dart';

// ── Model download configurations ─────────────────────────────────────────────

class _ModelConfig {
  final String name;
  final String filename;
  final String url;
  final int expectedBytes;
  const _ModelConfig({
    required this.name,
    required this.filename,
    required this.url,
    required this.expectedBytes,
  });
}

/// Gemma 4 E2B IT — Q4_K_M quant from bartowski (2.89 GiB on disk).
/// Hosted on Hugging Face; supports HTTP Range requests (resumable).
const _chatModels = [
  _ModelConfig(
    name: 'Gemma 4 E2B Instruct (Q4_K_M) — 2.9 GB',
    filename: 'gemma-4-E2B-it-Q4_K_M.gguf',
    url: 'https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF'
        '/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf',
    expectedBytes: 3_103_113_871, // 2.89 GiB
  ),
  _ModelConfig(
    name: 'Gemma 4 E2B Instruct (IQ2_M) — 2.4 GB (lower RAM)',
    filename: 'gemma-4-E2B-it-IQ2_M.gguf',
    url: 'https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF'
        '/resolve/main/gemma-4-E2B-it-IQ2_M.gguf',
    expectedBytes: 2_446_682_624, // 2.28 GiB
  ),
];

// ── Wizard ────────────────────────────────────────────────────────────────────

class SetupWizard extends StatefulWidget {
  const SetupWizard({super.key});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  // Steps: 0=Language, 1=Model+GPU, 2=Chat download, 3=Embed download
  static const int _totalSteps = 4;

  int _step = 0;
  String _selectedLanguage = 'de';
  _ModelConfig _selectedChatModel = _chatModels[0];
  GpuMode _selectedGpuMode = GpuMode.auto;

  // Lazily created download services — one per model config + one for embed.
  ModelDownloadService? _chatDownloader;
  ModelDownloadService? _embedDownloader;

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<String> _chatDestPath(_ModelConfig cfg) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/models/${cfg.filename}';
  }

  /// Build (or reuse) a ModelDownloadService for the selected chat model.
  Future<ModelDownloadService> _getChatDownloader() async {
    if (_chatDownloader != null) return _chatDownloader!;
    final path = await _chatDestPath(_selectedChatModel);
    _chatDownloader = ModelDownloadService(
      url: _selectedChatModel.url,
      destPath: path,
      expectedBytes: _selectedChatModel.expectedBytes,
    );
    return _chatDownloader!;
  }

  Future<ModelDownloadService> _getEmbedDownloader() async {
    if (_embedDownloader != null) return _embedDownloader!;
    final path = await EmbeddingService.defaultModelPath;
    _embedDownloader = ModelDownloadService(
      url: EmbeddingService.downloadUrl,
      destPath: path,
      expectedBytes: EmbeddingService.expectedBytes,
    );
    return _embedDownloader!;
  }

  @override
  void dispose() {
    _chatDownloader?.dispose();
    _embedDownloader?.dispose();
    super.dispose();
  }

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
            onChanged: (m) {
              if (m != null && m != _selectedChatModel) {
                // Discard old downloader if model changes before download starts.
                _chatDownloader?.dispose();
                _chatDownloader = null;
                setState(() => _selectedChatModel = m);
              }
            },
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
    return FutureBuilder<ModelDownloadService>(
      future: _getChatDownloader(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final dl = snap.data!;
        return ListenableBuilder(
          listenable: dl,
          builder: (context, _) =>
              _buildDownloadCard(loc, dl, isChatModel: true),
        );
      },
    );
  }

  // ── Step 3: Embedding model download ────────────────────────────────────

  Widget _buildEmbedDownload(AppLocalizations loc) {
    return FutureBuilder<ModelDownloadService>(
      future: _getEmbedDownloader(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final dl = snap.data!;
        return ListenableBuilder(
          listenable: dl,
          builder: (context, _) =>
              _buildDownloadCard(loc, dl, isChatModel: false),
        );
      },
    );
  }

  // ── Shared download card ─────────────────────────────────────────────────

  Widget _buildDownloadCard(
    AppLocalizations loc,
    ModelDownloadService dl, {
    required bool isChatModel,
  }) {
    final title = isChatModel ? loc.setupDownloading : loc.setupEmbedTitle;
    final subtitle =
        isChatModel ? _selectedChatModel.name : EmbeddingService.defaultFilename;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style:
                const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(subtitle,
            style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 32),

        // ── Done ──────────────────────────────────────────────────────────
        if (dl.status == DownloadStatus.done) ...[
          Row(children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Text(loc.setupDownloadDone,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 24),
          if (isChatModel) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _onChatDownloadDone(dl.destPath),
                child: Text(loc.setupContinue),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _onEmbedDownloadDone(dl.destPath),
                child: Text(loc.setupFinish),
              ),
            ),
          ],
        ]

        // ── Error ─────────────────────────────────────────────────────────
        else if (dl.status == DownloadStatus.error) ...[
          Row(children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(dl.errorMessage ?? 'Unknown error',
                  style: const TextStyle(color: Colors.red)),
            ),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: Text(loc.buttonRetry),
              onPressed: dl.start,
            ),
          ),
        ]

        // ── Downloading ───────────────────────────────────────────────────
        else if (dl.status == DownloadStatus.downloading) ...[
          _DownloadProgressRow(dl: dl, loc: loc),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.pause),
              label: Text(loc.setupDownloadPause),
              onPressed: dl.pause,
            ),
          ),
        ]

        // ── Paused ────────────────────────────────────────────────────────
        else if (dl.status == DownloadStatus.paused) ...[
          _DownloadProgressRow(dl: dl, loc: loc),
          const SizedBox(height: 8),
          Text(loc.setupDownloadPaused,
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: Text(loc.setupDownloadResume),
              onPressed: dl.start,
            ),
          ),
        ]

        // ── Idle (not started) ────────────────────────────────────────────
        else ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.download),
              label: Text(loc.setupDownloadButton),
              onPressed: dl.start,
            ),
          ),
          if (!isChatModel) ...[
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
      ],
    );
  }

  // ── Completion callbacks ─────────────────────────────────────────────────

  Future<void> _onChatDownloadDone(String destPath) async {
    await context.read<LlamaService>().completeSetup(
          modelPath: destPath,
          gpuMode: _selectedGpuMode,
        );
    if (mounted) setState(() => _step++);
  }

  Future<void> _onEmbedDownloadDone(String destPath) async {
    await context.read<EmbeddingService>().loadModel(destPath);
    _finishSetup();
  }

  void _finishSetup() {
    // LlamaService.isSetupComplete is true → main.dart Consumer switches view.
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
    }
    // Steps 2 and 3: navigation is driven by the download completion buttons.

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress indicators
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

              Expanded(child: steps[_step]),

              if (bottomButton != null)
                SizedBox(width: double.infinity, child: bottomButton),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Progress row widget ───────────────────────────────────────────────────────

class _DownloadProgressRow extends StatelessWidget {
  final ModelDownloadService dl;
  final AppLocalizations loc;
  const _DownloadProgressRow({required this.dl, required this.loc});

  @override
  Widget build(BuildContext context) {
    final progress = dl.progress;
    final receivedMb = dl.receivedBytes / 1e6;
    final totalMb = dl.totalBytes / 1e6;
    final pctStr = progress != null
        ? '${(progress * 100).toStringAsFixed(1)}%'
        : '…';
    final sizeStr = totalMb > 0
        ? '${receivedMb.toStringAsFixed(0)} / ${totalMb.toStringAsFixed(0)} MB'
        : '${receivedMb.toStringAsFixed(0)} MB';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Text('$pctStr — $sizeStr',
            style: TextStyle(color: Colors.grey.shade700)),
      ],
    );
  }
}
