import 'dart:math';
import 'package:flutter/foundation.dart';
import 'llama_service.dart';

/// A retrieved chunk from the vector store
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
///   1. Document ingestion (chunking → embedding → store)
///   2. Query retrieval (embed query → cosine search → rerank)
///   3. Context assembly for the LLM prompt
class RagService extends ChangeNotifier {
  final LlamaService _llama;

  // In-memory vector store: list of (vector, chunk text, source file)
  // Replace with ObjectBox HNSW index for production performance.
  final List<_IndexedChunk> _index = [];

  bool _isIngesting = false;
  int _totalChunks = 0;

  bool get isIngesting => _isIngesting;
  int get totalChunks => _totalChunks;

  /// Constructor: Pass the LlamaService instance from Provider
  RagService(this._llama);

  // ── Ingestion ──────────────────────────────────────────────────────────────

  /// Ingest a plain-text document.  Call [onProgress] with 0.0–1.0.
  Future<void> ingestText({
    required String text,
    required String sourceFile,
    void Function(double progress)? onProgress,
  }) async {
    _isIngesting = true;
    notifyListeners();

    try {
      final chunks = _chunk(text);
      for (int i = 0; i < chunks.length; i++) {
        final vector = await _llama.embed(chunks[i]);
        _index.add(_IndexedChunk(
          vector: vector,
          text: chunks[i],
          sourceFile: sourceFile,
        ));
        onProgress?.call((i + 1) / chunks.length);
      }
      _totalChunks = _index.length;
    } finally {
      _isIngesting = false;
      notifyListeners();
    }
  }

  // ── Retrieval ──────────────────────────────────────────────────────────────

  /// Retrieve the top-k most relevant chunks for [query].
  Future<List<RetrievedChunk>> retrieve({
    required String query,
    int k = 5,
    double minScore = 0.2,
  }) async {
    if (_index.isEmpty) return [];

    final queryVector = await _llama.embed(query);

    // Cosine similarity search
    final scored = _index.map((chunk) {
      final score = _cosineSimilarity(queryVector, chunk.vector);
      return (chunk, score);
    }).toList();

    scored.sort((a, b) => b.$2.compareTo(a.$2));

    return scored
        .where((s) => s.$2 >= minScore)
        .take(k)
        .map((s) => RetrievedChunk(
              text: s.$1.text,
              sourceFile: s.$1.sourceFile,
              score: s.$2,
            ))
        .toList();
  }

  /// Build a system prompt + context string from retrieved chunks.
  ///
  /// [lang] should be the current locale language code ('de' or 'en').
  String buildContext(List<RetrievedChunk> chunks, {String lang = 'de'}) {
    if (chunks.isEmpty) return '';
    final buffer = StringBuffer();
    if (lang == 'de') {
      buffer.writeln('Nutze die folgenden Informationen, um die Frage zu beantworten:');
    } else {
      buffer.writeln('Use the following information to answer the question:');
    }
    buffer.writeln();
    for (int i = 0; i < chunks.length; i++) {
      buffer.writeln('[${i + 1}] Source: ${chunks[i].sourceFile}');
      buffer.writeln(chunks[i].text);
      buffer.writeln();
    }
    if (lang == 'de') {
      buffer.writeln('Beantworte die Frage basierend auf den obigen Informationen.');
    } else {
      buffer.writeln('Answer the question based on the information above.');
    }
    return buffer.toString();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Fixed-size chunking: 512 "words" per chunk, 50-word overlap.
  List<String> _chunk(String text, {int size = 512, int overlap = 50}) {
    final words = text.split(RegExp(r'\s+'));
    final chunks = <String>[];
    int start = 0;
    while (start < words.length) {
      final end = min(start + size, words.length);
      chunks.add(words.sublist(start, end).join(' '));
      start += size - overlap;
      if (start >= words.length) break;
    }
    return chunks;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    assert(a.length == b.length);
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  void clearIndex() {
    _index.clear();
    _totalChunks = 0;
    notifyListeners();
  }
}

class _IndexedChunk {
  final List<double> vector;
  final String text;
  final String sourceFile;
  const _IndexedChunk({
    required this.vector,
    required this.text,
    required this.sourceFile,
  });
}
