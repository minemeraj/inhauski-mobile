import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/llama_service.dart';
import '../i18n/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final llama = context.watch<LlamaService>();

    return Scaffold(
      appBar: AppBar(title: Text(loc.navSettings)),
      body: ListView(
        children: [
          // ── Model ───────────────────────────────────────────────────────
          _SectionHeader(title: loc.settingsModel),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('Gemma 4 E2B Instruct'),
            subtitle: Text(llama.modelPath ?? loc.settingsModelNotLoaded),
            trailing: llama.isModelLoaded
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.error_outline, color: Colors.orange),
          ),

          const Divider(),

          // ── GPU ─────────────────────────────────────────────────────────
          _SectionHeader(title: loc.settingsGpu),
          RadioListTile<GpuMode>(
            title: Text(loc.settingsGpuAuto),
            subtitle: const Text('Metal (iOS) / OpenCL (Android)'),
            value: GpuMode.auto,
            groupValue: llama.gpuMode,
            onChanged: (_) {}, // TODO: persist via LlamaService
          ),
          RadioListTile<GpuMode>(
            title: Text(loc.settingsGpuForce),
            value: GpuMode.gpu,
            groupValue: llama.gpuMode,
            onChanged: (_) {},
          ),
          RadioListTile<GpuMode>(
            title: Text(loc.settingsGpuCpu),
            subtitle: const Text('Langsamer, aber kompatibel'),
            value: GpuMode.cpu,
            groupValue: llama.gpuMode,
            onChanged: (_) {},
          ),

          const Divider(),

          // ── Language ────────────────────────────────────────────────────
          _SectionHeader(title: loc.settingsLanguage),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Deutsch / English'),
            subtitle: const Text('Folgt der Systemsprache'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {}, // TODO: language picker
          ),

          const Divider(),

          // ── Data & Reset ─────────────────────────────────────────────────
          _SectionHeader(title: 'Daten & Reset'),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(loc.settingsReset),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Setup zurücksetzen?'),
                  content: const Text(
                    'Dies löscht die Einrichtung. Das Modell bleibt erhalten.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Abbrechen'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Zurücksetzen'),
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
          _SectionHeader(title: 'Über InHausKI'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version 1.0.0'),
            subtitle: Text('inhauski.de · 100% offline · DSGVO-konform'),
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
