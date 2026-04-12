import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../services/embedding_service.dart';
import '../services/model_download_service.dart';
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

  // Lazily-created resumable downloader for the embedding model.
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

  // ── Document import ───────────────────────────────────────────────────────

  Future<void> _importDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md'],
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
      final content = await File(file.path!).readAsString();

      await rag.ingestText(
        text: content,
        sourceFile: file.name,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${file.name}: ${rag.totalChunks} ${loc.docsChunks}'),
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

  // ── Confirm-delete dialog ─────────────────────────────────────────────────

  Future<void> _confirmDelete(String sourceFile) async {
    final rag = context.read<RagService>();
    final loc = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(sourceFile),
        content: Text(loc.docsDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.buttonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.docsDeleteAction),
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

  Widget _buildEmbedBanner(AppLocalizations loc, EmbeddingService embedSvc) {
    return FutureBuilder<ModelDownloadService>(
      future: _getEmbedDownloader(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final dl = snap.data!;
        return ListenableBuilder(
          listenable: dl,
          builder: (context, _) {
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

            if (dl.status == DownloadStatus.downloading ||
                dl.status == DownloadStatus.paused) {
              return _EmbedDownloadCard(dl: dl, loc: loc);
            }
            if (dl.isDone) return const SizedBox.shrink();
            if (embedSvc.errorMessage != null) {
              return Card(
                color: Theme.of(context).colorScheme.errorContainer,
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(embedSvc.errorMessage!,
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onErrorContainer)),
                ),
              );
            }
            // Idle banner
            return Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Theme.of(context)
                            .colorScheme
                            .onTertiaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(loc.docsNoEmbedWarning,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onTertiaryContainer)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: dl.start,
                      child: Text(loc.docsNoEmbedAction),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── Embed download progress card ──────────────────────────────────────────────

class _EmbedDownloadCard extends StatelessWidget {
  final ModelDownloadService dl;
  final AppLocalizations loc;
  const _EmbedDownloadCard({required this.dl, required this.loc});

  @override
  Widget build(BuildContext context) {
    final progress = dl.progress;
    final receivedMb = dl.receivedBytes / 1e6;
    final totalMb = dl.totalBytes / 1e6;
    final pctStr = progress != null
        ? '${(progress * 100).toStringAsFixed(1)}%'
        : '…';
    final sizeStr = totalMb > 0
        ? '$pctStr — ${receivedMb.toStringAsFixed(0)} / ${totalMb.toStringAsFixed(0)} MB'
        : '$pctStr — ${receivedMb.toStringAsFixed(0)} MB';

    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(EmbeddingService.defaultFilename,
                style: const TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(sizeStr,
                    style: Theme.of(context).textTheme.bodySmall),
                if (dl.status == DownloadStatus.downloading)
                  TextButton.icon(
                    icon: const Icon(Icons.pause, size: 16),
                    label: Text(loc.setupDownloadPause),
                    onPressed: dl.pause,
                  )
                else
                  TextButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: Text(loc.setupDownloadResume),
                    onPressed: dl.start,
                  ),
              ],
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
            Icon(Icons.storage,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$totalChunks ${loc.docsChunks}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '$totalSources ${loc.docsFiles(totalSources)} · ${loc.docsIndexed}',
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
    if (ext == 'md') return Icons.code_outlined;
    return Icons.text_snippet_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_iconForFile(sourceFile),
          color: Theme.of(context).colorScheme.primary),
      title: Text(sourceFile, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
