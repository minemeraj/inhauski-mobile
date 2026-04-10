import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart';
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
      final content = await _readFileAsText(file.path!, file.name);

      await rag.ingestText(
        text: content,
        sourceFile: file.name,
        onProgress: (p) => setState(() => _progress = p),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('${file.name}: ${rag.totalChunks} ${loc.docsChunks}'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${loc.docsError}: $e'),
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

  /// Extract text from the file at [path].
  ///
  /// PDF → iterate all pages via pdfx and concatenate the text layer.
  /// TXT / MD → read as UTF-8 string.
  Future<String> _readFileAsText(String path, String name) async {
    final ext = name.toLowerCase().split('.').last;
    if (ext == 'pdf') {
      return _extractPdfText(path);
    }
    return File(path).readAsString();
  }

  Future<String> _extractPdfText(String path) async {
    final doc = await PdfDocument.openFile(path);
    final buf = StringBuffer();
    for (int i = 1; i <= doc.pagesCount; i++) {
      final page = await doc.getPage(i);
      final text = await page.getTextRanges();
      for (final range in text) {
        buf.write(range.text);
        buf.write(' ');
      }
      await page.close();
    }
    await doc.close();
    return buf.toString();
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
              tooltip: loc.docsClearIndex,
              onPressed: () {
                rag.clearIndex();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(loc.docsClearIndexDone)),
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
              loc.docsFormats,
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
