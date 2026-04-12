import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/embedding_service.dart';
import '../services/llama_service.dart';
import '../services/locale_service.dart';
import '../services/model_download_service.dart';
import '../i18n/app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ModelDownloadService? _embedDownloader;

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
    _embedDownloader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final llama = context.watch<LlamaService>();
    final embedSvc = context.watch<EmbeddingService>();
    final localeService = context.watch<LocaleService>();
    final currentLang = localeService.locale?.languageCode ??
        Localizations.localeOf(context).languageCode;

    // Disable GPU radio buttons while loading or inferring
    final gpuChangeable = !llama.isInferring && llama.isModelLoaded;

    return Scaffold(
      appBar: AppBar(title: Text(loc.navSettings)),
      body: ListView(
        children: [
          // ── Chat model ──────────────────────────────────────────────────
          _SectionHeader(title: loc.settingsModel),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            // Show the model name the user picked in the wizard, or fall
            // back to the filename portion of the path.
            title: Text(llama.modelName ??
                llama.modelPath?.split('/').last ??
                loc.settingsModelNotLoaded),
            subtitle: Text(llama.modelPath ?? loc.settingsModelNotLoaded),
            trailing: _modelStatusIcon(llama),
          ),

          const Divider(),

          // ── Embedding model ─────────────────────────────────────────────
          _SectionHeader(title: loc.settingsEmbedModel),
          if (embedSvc.isLoaded)
            ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: Text(EmbeddingService.defaultFilename),
              subtitle: Text(embedSvc.modelPath ?? ''),
              trailing: const Icon(Icons.check_circle, color: Colors.green),
            )
          else
            _buildEmbedDownloadTile(loc, embedSvc),

          const Divider(),

          // ── GPU ─────────────────────────────────────────────────────────
          _SectionHeader(title: loc.settingsGpu),
          RadioListTile<GpuMode>(
            title: Text(loc.settingsGpuAuto),
            subtitle: Text(loc.settingsGpuSubtitleAuto),
            value: GpuMode.auto,
            groupValue: llama.gpuMode,
            onChanged: gpuChangeable
                ? (mode) =>
                    context.read<LlamaService>().setGpuMode(mode!)
                : null,
          ),
          RadioListTile<GpuMode>(
            title: Text(loc.settingsGpuForce),
            value: GpuMode.gpu,
            groupValue: llama.gpuMode,
            onChanged: gpuChangeable
                ? (mode) =>
                    context.read<LlamaService>().setGpuMode(mode!)
                : null,
          ),
          RadioListTile<GpuMode>(
            title: Text(loc.settingsGpuCpu),
            subtitle: Text(loc.settingsGpuSubtitleCpu),
            value: GpuMode.cpu,
            groupValue: llama.gpuMode,
            onChanged: gpuChangeable
                ? (mode) =>
                    context.read<LlamaService>().setGpuMode(mode!)
                : null,
          ),

          const Divider(),

          // ── Language ────────────────────────────────────────────────────
          _SectionHeader(title: loc.settingsLanguage),
          RadioListTile<String>(
            title: const Text('Deutsch'),
            value: 'de',
            groupValue: currentLang,
            onChanged: (code) =>
                context.read<LocaleService>().setLocale(code),
          ),
          RadioListTile<String>(
            title: const Text('English'),
            value: 'en',
            groupValue: currentLang,
            onChanged: (code) =>
                context.read<LocaleService>().setLocale(code),
          ),
          RadioListTile<String>(
            title: Text(loc.settingsLanguageSystem),
            value: 'system',
            groupValue:
                localeService.locale == null ? 'system' : currentLang,
            onChanged: (_) =>
                context.read<LocaleService>().setLocale(null),
          ),

          const Divider(),

          // ── Data & Reset ─────────────────────────────────────────────────
          _SectionHeader(title: loc.settingsDataReset),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(loc.settingsReset),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(loc.settingsResetDialogTitle),
                  content: Text(loc.settingsResetDialogBody),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(loc.buttonCancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(loc.buttonConfirm),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                await context.read<LlamaService>().resetSetup();
                await context.read<EmbeddingService>().reset();
              }
            },
          ),

          const Divider(),

          // ── About ────────────────────────────────────────────────────────
          _SectionHeader(title: loc.settingsAbout),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('InHausKI v1.0.0'),
            subtitle: Text(loc.settingsAboutSubtitle),
          ),
        ],
      ),
    );
  }

  Widget _buildEmbedDownloadTile(
      AppLocalizations loc, EmbeddingService embedSvc) {
    return FutureBuilder<ModelDownloadService>(
      future: _getEmbedDownloader(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: Text(EmbeddingService.defaultFilename),
            subtitle: Text(embedSvc.errorMessage ?? loc.settingsEmbedNotLoaded,
                style: embedSvc.errorMessage != null
                    ? TextStyle(
                        color: Theme.of(context).colorScheme.error)
                    : null),
          );
        }
        final dl = snap.data!;

        // Auto-load after download completes
        if (dl.isDone && !embedSvc.isLoaded && !embedSvc.isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (mounted) {
              await context
                  .read<EmbeddingService>()
                  .loadModel(dl.destPath);
            }
          });
        }

        return ListenableBuilder(
          listenable: dl,
          builder: (context, _) {
            if (dl.status == DownloadStatus.downloading ||
                dl.status == DownloadStatus.paused) {
              final progress = dl.progress;
              final pct = progress != null
                  ? '${(progress * 100).toStringAsFixed(1)}%'
                  : '…';
              final mb =
                  '${(dl.receivedBytes / 1e6).toStringAsFixed(0)} / '
                  '${(dl.totalBytes / 1e6).toStringAsFixed(0)} MB';
              return ListTile(
                leading: const Icon(Icons.hub_outlined),
                title: Text(EmbeddingService.defaultFilename),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$pct — $mb',
                            style:
                                Theme.of(context).textTheme.bodySmall),
                        if (dl.status == DownloadStatus.downloading)
                          TextButton(
                            onPressed: dl.pause,
                            child: Text(loc.setupDownloadPause),
                          )
                        else
                          TextButton(
                            onPressed: dl.start,
                            child: Text(loc.setupDownloadResume),
                          ),
                      ],
                    ),
                  ],
                ),
                isThreeLine: true,
              );
            }

            if (dl.status == DownloadStatus.error) {
              return ListTile(
                leading: const Icon(Icons.hub_outlined),
                title: Text(EmbeddingService.defaultFilename),
                subtitle: Text(dl.errorMessage ?? loc.settingsEmbedNotLoaded,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                trailing: TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(loc.buttonRetry),
                  onPressed: dl.start,
                ),
              );
            }

            // Idle / done
            return ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: Text(EmbeddingService.defaultFilename),
              subtitle: Text(
                  embedSvc.errorMessage ?? loc.settingsEmbedNotLoaded,
                  style: embedSvc.errorMessage != null
                      ? TextStyle(
                          color: Theme.of(context).colorScheme.error)
                      : null),
              trailing: TextButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('~90 MB'),
                onPressed: dl.start,
              ),
            );
          },
        );
      },
    );
  }

  Widget _modelStatusIcon(LlamaService llama) {
    if (llama.isModelLoaded) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    if (llama.errorMessage != null) {
      return const Icon(Icons.error_outline, color: Colors.red);
    }
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
