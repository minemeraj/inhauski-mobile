import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../services/rag_service.dart';
import '../i18n/app_localizations.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  double? _progress;
  String? _currentFile;

  Future<void> _importDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'md'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    final rag = context.read<RagService>();
    final loc = AppLocalizations.of(context);

    setState(() {
      _currentFile = file.name;
      _progress = 0;
    });

    try {
      // Read file content
      // TODO: For PDF, use pdfx or pdfium_render to extract text.
      // For now, handle plain text only.
      final content = await _readFileAsText(file.path!);

      await rag.ingestText(
        text: content,
        sourceFile: file.name,
        onProgress: (p) => setState(() => _progress = p),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${file.name}: ${rag.totalChunks} ${loc.docsChunks}'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Fehler: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      setState(() {
        _progress = null;
        _currentFile = null;
      });
    }
  }

  Future<String> _readFileAsText(String path) async {
    // PDF support requires a separate package (e.g. pdfx) — Week 3.
    // For now, read plain text / markdown files directly.
    return File(path).readAsString();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final rag = context.watch<RagService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.navDocuments),
        actions: [
          if (rag.totalChunks > 0)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Index leeren',
              onPressed: () {
                rag.clearIndex();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Dokumentenindex geleert.')),
                );
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.storage,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${rag.totalChunks} ${loc.docsChunks}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          loc.docsIndexed,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Import button / progress
            if (_progress != null) ...[
              Text('${loc.docsProcessing} $_currentFile'),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress),
            ] else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: rag.isIngesting ? null : _importDocument,
                  icon: const Icon(Icons.upload_file),
                  label: Text(loc.docsImport),
                ),
              ),

            const SizedBox(height: 32),

            // Supported formats note
            Text(
              'Unterstützte Formate: PDF, TXT, Markdown',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
