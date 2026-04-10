import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';

import '../services/embedding_service.dart';
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

  // ── Embedding model download (shown inline when model is absent) ──────────

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
                '${(pct * 100).toStringAsFixed(1)}% — '
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

  // ── Document import ───────────────────────────────────────────────────────

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
          content: Text(
              '${file.name}: ${rag.totalChunks} ${loc.docsChunks}'),
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
      if (mounted) {
        setState(() {
          _progress = null;
          _currentFile = null;
        });
      }
    }
  }

  /// Extract plain text from a file (PDF, TXT, or Markdown).
  Future<String> _readFileAsText(String path, String name) async {
    final ext = name.toLowerCase().split('.').last;
    if (ext == 'pdf') return _extractPdfText(path);
    return File(path).readAsString();
  }

  Future<String> _extractPdfText(String path) async {
    final doc = await PdfDocument.openFile(path);
    final buf = StringBuffer();
    for (int i = 1; i <= doc.pagesCount; i++) {
      final page = await doc.getPage(i);
      final ranges = await page.getTextRanges();
      for (final range in ranges) {
        buf.write(range.text);
        buf.write(' ');
      }
      await page.close();
    }
    await doc.close();
    return buf.toString();
  }

  // ── Confirm-delete dialog ─────────────────────────────────────────────────

  Future<void> _confirmDelete(String sourceFile) async {
    final rag = context.read<RagService>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(sourceFile),
        content: const Text(
            'Remove all chunks for this file from the index?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context).buttonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      rag.removeSource(sourceFile);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final rag = context.watch<RagService>();
    final embedSvc = context.watch<EmbeddingService>();
    final sources = rag.sourcesInIndex;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.navDocuments),
        actions: [
          if (sources.isNotEmpty)
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Embedding model guard banner ───────────────────────────────
          if (!embedSvc.isLoaded) _buildEmbedBanner(loc, embedSvc),

          // ── Stats card ─────────────────────────────────────────────────
          _StatsCard(
            totalChunks: rag.totalChunks,
            totalSources: sources.length,
            loc: loc,
          ),

          const SizedBox(height: 16),

          // ── Import button / progress ───────────────────────────────────
          if (_progress != null) ...[
            Text('${loc.docsProcessing} $_currentFile'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 16),
          ] else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                // Disable if embedding model absent or currently ingesting
                onPressed: (embedSvc.isLoaded && !rag.isIngesting)
                    ? _importDocument
                    : null,
                icon: const Icon(Icons.upload_file),
                label: Text(loc.docsImport),
              ),
            ),

          const SizedBox(height: 8),

          // ── Per-file list ──────────────────────────────────────────────
          if (sources.isNotEmpty) ...[
            const Divider(height: 32),
            for (final src in sources)
              _SourceTile(
                sourceFile: src,
                onDelete: () => _confirmDelete(src),
              ),
          ],

          const SizedBox(height: 24),

          // ── Supported formats note ─────────────────────────────────────
          Text(
            loc.docsFormats,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmbedBanner(
      AppLocalizations loc, EmbeddingService embedSvc) {
    if (_isEmbedDownloading || _embedProgress != null) {
      return Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                EmbeddingService.defaultFilename,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _embedProgress),
              const SizedBox(height: 4),
              Text(
                _embedStatus ?? '',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    if (embedSvc.errorMessage != null) {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            embedSvc.errorMessage!,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer),
          ),
        ),
      );
    }

    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(context).colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                loc.docsNoEmbedWarning,
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onTertiaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _downloadEmbedModel,
              child: Text(loc.docsNoEmbedAction),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final int totalChunks;
  final int totalSources;
  final AppLocalizations loc;

  const _StatsCard({
    required this.totalChunks,
    required this.totalSources,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
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
                  '$totalChunks ${loc.docsChunks}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '$totalSources ${totalSources == 1 ? "file" : "files"} · ${loc.docsIndexed}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final String sourceFile;
  final VoidCallback onDelete;

  const _SourceTile({
    required this.sourceFile,
    required this.onDelete,
  });

  IconData _iconForFile(String name) {
    final ext = name.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'md':
        return Icons.code_outlined;
      default:
        return Icons.text_snippet_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        _iconForFile(sourceFile),
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        sourceFile,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Remove from index',
        onPressed: onDelete,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
