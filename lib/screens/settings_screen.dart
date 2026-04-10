import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/llama_service.dart';
import '../services/locale_service.dart';
import '../i18n/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final llama = context.watch<LlamaService>();
    final localeService = context.watch<LocaleService>();
    final currentLang = localeService.locale?.languageCode ??
        Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(loc.navSettings)),
      body: ListView(
        children: [
          // ── Model ───────────────────────────────────────────────────────
          _SectionHeader(title: loc.settingsModel),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Gemma 4 2B Instruct (Q4_K_M)'),
            subtitle: Text(llama.modelPath ?? loc.settingsModelNotLoaded),
            trailing: llama.isModelLoaded
                ? const Icon(Icons.check_circle, color: Colors.green)
                : llama.errorMessage != null
                    ? const Icon(Icons.error_outline, color: Colors.red)
                    : const Icon(Icons.hourglass_top_outlined,
                        color: Colors.orange),
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
            // Use a sentinel value that cannot match a real language code.
            value: 'system',
            groupValue: localeService.locale == null ? 'system' : currentLang,
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
