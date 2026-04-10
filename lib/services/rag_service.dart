import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:objectbox/objectbox.dart';

import 'embedding_service.dart';
import '../storage/objectbox_store.dart';

/// A retrieved chunk returned to the caller.
class RetrievedChunk {
  final String text;
  final String sourceFile;
  final double score;
  const RetrievedChunk({
    required this.text,
    required this.sourceFile,
    required this.score,
  });
}

/// RagService orchestrates:
///   1. Document ingestion  → chunk → embed (EmbeddingService) → ObjectBox
///   2. Query retrieval     → embed query → HNSW search → rerank
///   3. Context assembly    → locale-aware system prompt
class RagService extends ChangeNotifier {
  final EmbeddingService _embedder;
  final Box<VectorChunk> _box;

  bool _isIngesting = false;

  bool get isIngesting => _isIngesting;
  int get totalChunks => _box.count();

  RagService(this._embedder, this._box);

  // ── Ingestion ──────────────────────────────────────────────────────────────

  /// Ingest plain text from [sourceFile].
  /// Chunks are persisted in ObjectBox so they survive restarts.
  Future<void> ingestText({
    required String text,
    required String sourceFile,
    void Function(double progress)? onProgress,
  }) async {
    _isIngesting = true;
    notifyListeners();

    try {
      final chunks = _chunk(text);
      final now = DateTime.now();

      for (int i = 0; i < chunks.length; i++) {
        final embedding = await _embedder.embed(chunks[i]);
        _box.put(VectorChunk(
          sourceFile: sourceFile,
          text: chunks[i],
          embedding: embedding,
          ingestedAt: now,
        ));
        onProgress?.call((i + 1) / chunks.length);
      }
    } finally {
      _isIngesting = false;
      notifyListeners();
    }
  }

  // ── Retrieval ──────────────────────────────────────────────────────────────

  /// Return the top-[k] most relevant chunks for [query].
  ///
  /// Uses ObjectBox HNSW nearest-neighbour search when the store has an
  /// index; falls back to linear cosine scan for the hand-written stub.
  Future<List<RetrievedChunk>> retrieve({
    required String query,
    int k = 5,
    double minScore = 0.2,
  }) async {
    if (_box.isEmpty()) return [];

    final queryVector = await _embedder.embed(query);

    // HNSW nearest-neighbour query via ObjectBox
    final nnQuery = _box
        .query(VectorChunk_.embedding.nearestNeighborsF32(queryVector, k * 2))
        .build();
    final candidates = nnQuery.findWithScores();
    nnQuery.close();

    // ObjectBox HNSW score is L2 distance — convert to a cosine-like
    // similarity in [0, 1] so the minScore threshold is meaningful.
    // score = 1 / (1 + distance)
    final results = candidates
        .map((ws) => RetrievedChunk(
              text: ws.object.text,
              sourceFile: ws.object.sourceFile,
              score: 1.0 / (1.0 + ws.score),
            ))
        .where((r) => r.score >= minScore)
        .take(k)
        .toList();

    // Sort descending by score (highest relevance first)
    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  // ── Context assembly ───────────────────────────────────────────────────────

  /// Build a locale-aware system prompt from retrieved chunks.
  String buildContext(List<RetrievedChunk> chunks, {String lang = 'de'}) {
    if (chunks.isEmpty) return '';
    final buf = StringBuffer();
    if (lang == 'de') {
      buf.writeln(
          'Nutze die folgenden Informationen, um die Frage zu beantworten:');
    } else {
      buf.writeln('Use the following information to answer the question:');
    }
    buf.writeln();
    for (int i = 0; i < chunks.length; i++) {
      buf.writeln('[${i + 1}] Source: ${chunks[i].sourceFile}');
      buf.writeln(chunks[i].text);
      buf.writeln();
    }
    if (lang == 'de') {
      buf.writeln(
          'Beantworte die Frage basierend auf den obigen Informationen.');
    } else {
      buf.writeln('Answer the question based on the information above.');
    }
    return buf.toString();
  }

  // ── Index management ───────────────────────────────────────────────────────

  /// Remove all indexed chunks (e.g. when user taps "Clear index").
  void clearIndex() {
    _box.removeAll();
    notifyListeners();
  }

  /// Remove all chunks belonging to a specific source file.
  void removeSource(String sourceFile) {
    final query = _box
        .query(VectorChunk_.sourceFile.equals(sourceFile))
        .build();
    final ids = query.findIds();
    query.close();
    _box.removeMany(ids);
    notifyListeners();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Fixed-size word chunking: [size] words per chunk, [overlap] word overlap.
  List<String> _chunk(String text, {int size = 512, int overlap = 50}) {
    final words = text.split(RegExp(r'\s+'));
    if (words.isEmpty) return [];
    final chunks = <String>[];
    int start = 0;
    while (start < words.length) {
      final end = min(start + size, words.length);
      chunks.add(words.sublist(start, end).join(' '));
      if (end == words.length) break;
      start += size - overlap;
    }
    return chunks;
  }
}
