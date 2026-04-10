import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../services/embedding_service.dart';
import '../services/llama_service.dart';
import '../services/locale_service.dart';
import '../i18n/app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Inline embedding download state (shown when model not installed)
  double? _embedProgress;
  String? _embedStatus;
  bool _isEmbedDownloading = false;

  Future<void> _downloadEmbedModel() async {
    final embedSvc = context.read<EmbeddingService>();
    setState(() {
      _isEmbedDownloading = true;
      _embedProgress = 0;
      _embedStatus = '…';
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
            _embedProgress = pct;
            _embedStatus =
                '${(pct * 100).toStringAsFixed(1)}%  '
                '${mb.toStringAsFixed(0)} / ${totalMb.toStringAsFixed(0)} MB';
          });
        }
      }

      await sink.close();
      client.close();

      if (mounted) {
        await embedSvc.loadModel(destPath);
        setState(() {
          _isEmbedDownloading = false;
          _embedProgress = null;
          _embedStatus = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isEmbedDownloading = false;
          _embedStatus = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final llama = context.watch<LlamaService>();
    final embedSvc = context.watch<EmbeddingService>();
    final localeService = context.watch<LocaleService>();
    final currentLang = localeService.locale?.languageCode ??
        Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(loc.navSettings)),
      body: ListView(
        children: [
          // ── Chat model ──────────────────────────────────────────────────
          _SectionHeader(title: loc.settingsModel),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Gemma 4 2B Instruct (Q4_K_M)'),
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
          else if (_isEmbedDownloading || _embedProgress != null)
            ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: Text(EmbeddingService.defaultFilename),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: _embedProgress),
                  const SizedBox(height: 4),
                  Text(_embedStatus ?? '',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              isThreeLine: true,
            )
          else
            ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: Text(EmbeddingService.defaultFilename),
              subtitle: Text(
                embedSvc.errorMessage ?? loc.settingsEmbedNotLoaded,
                style: embedSvc.errorMessage != null
                    ? TextStyle(
                        color: Theme.of(context).colorScheme.error)
                    : null,
              ),
              trailing: TextButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('~90 MB'),
                onPressed: _downloadEmbedModel,
              ),
            ),

          const Divider(),

          // ── GPU ─────────────────────────────────────────────────────────
          _SectionHeader(title: loc.settingsGpu),
          RadioListTile<GpuMode>(
            title: Text(loc.settingsGpuAuto),
            subtitle: Text(loc.settingsGpuSubtitleAuto),
            value: GpuMode.auto,
            groupValue: llama.gpuMode,
            onChanged: llama.isInferring
                ? null
                : (mode) => context.read<LlamaService>().setGpuMode(mode!),
          ),
          RadioListTile<GpuMode>(
            title: Text(loc.settingsGpuForce),
            value: GpuMode.gpu,
            groupValue: llama.gpuMode,
            onChanged: llama.isInferring
                ? null
                : (mode) => context.read<LlamaService>().setGpuMode(mode!),
          ),
          RadioListTile<GpuMode>(
            title: Text(loc.settingsGpuCpu),
            subtitle: Text(loc.settingsGpuSubtitleCpu),
            value: GpuMode.cpu,
            groupValue: llama.gpuMode,
            onChanged: llama.isInferring
                ? null
                : (mode) => context.read<LlamaService>().setGpuMode(mode!),
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
            title: const Text('Version 1.0.0'),
            subtitle: Text(loc.settingsAboutSubtitle),
          ),
        ],
      ),
    );
  }

  Widget _modelStatusIcon(LlamaService llama) {
    if (llama.isModelLoaded) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    if (llama.errorMessage != null) {
      return const Icon(Icons.error_outline, color: Colors.red);
    }
    return const Icon(Icons.hourglass_top_outlined, color: Colors.orange);
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
