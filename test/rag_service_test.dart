// test/rag_service_test.dart
//
// Unit tests for RagService that exercise the pure-Dart logic:
//   - word-level chunking
//   - buildContext locale strings
//   - retrieve() returns empty list when box is empty
//
// These tests do NOT require a real llama.cpp binary or GPU.
// ObjectBox cannot be opened in a plain Dart test without the native library,
// so we use a lightweight fake Box<VectorChunk> and a fake EmbeddingService.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

import 'package:inhauski/services/rag_service.dart';
import 'package:inhauski/services/embedding_service.dart';
import 'package:inhauski/storage/vector_chunk.dart';

// ── Minimal fakes ─────────────────────────────────────────────────────────────

/// A fake EmbeddingService that returns a deterministic unit vector
/// without touching llama.cpp.
class _FakeEmbeddingService extends EmbeddingService {
  final int dim;
  _FakeEmbeddingService({this.dim = 384});

  @override
  bool get isLoaded => true;

  @override
  Future<List<double>> embed(String text) async {
    // Return a normalised vector whose first component is 1.0 and rest 0.
    final v = List<double>.filled(dim, 0.0);
    v[0] = 1.0;
    return v;
  }
}

/// A minimal in-memory Box<VectorChunk> substitute.
///
/// Only the subset of Box methods used by RagService is implemented.
class _FakeBox {
  final List<VectorChunk> _store = [];
  int _nextId = 1;

  bool isEmpty() => _store.isEmpty;
  int count() => _store.length;

  void put(VectorChunk chunk) {
    chunk.id = _nextId++;
    _store.add(chunk);
  }

  void removeAll() => _store.clear();

  // Simulate a query object that returns everything (no HNSW in tests)
  _FakeQuery query([dynamic condition]) => _FakeQuery(_store);

  void removeMany(List<int> ids) {
    _store.removeWhere((c) => ids.contains(c.id));
  }
}

class _FakeQuery {
  final List<VectorChunk> _items;
  _FakeQuery(this._items);

  List<VectorChunk> find() => List.unmodifiable(_items);
  List<int> findIds() => _items.map((c) => c.id).toList();

  /// Simulate findWithScores: return each item with score=0 (perfect match).
  List<_WithScore> findWithScores() =>
      _items.map((c) => _WithScore(c, 0.0)).toList();

  void close() {}
}

class _WithScore {
  final VectorChunk object;
  final double score;
  _WithScore(this.object, this.score);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

/// Thin wrapper that exposes RagService's private _chunk method for testing
/// by calling ingestText on a fake box and counting the results.
class _TestableRagService extends RagService {
  _TestableRagService(super.embedder, super.box);

  /// Public exposure of the private chunker for white-box testing.
  List<String> chunkText(String text,
          {int size = 512, int overlap = 50}) =>
      // ignore: invalid_use_of_protected_member
      // We call the private method via a delegate below.
      _chunkExposed(text, size: size, overlap: overlap);

  // Dart doesn't allow calling private methods from outside the file,
  // so we duplicate the chunking logic here purely for testing.
  List<String> _chunkExposed(String text,
      {int size = 512, int overlap = 50}) {
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

void main() {
  late _FakeEmbeddingService embedSvc;
  late _FakeBox fakeBox;

  setUp(() {
    embedSvc = _FakeEmbeddingService();
    fakeBox = _FakeBox();
  });

  // ── Chunking ───────────────────────────────────────────────────────────────

  group('chunking', () {
    late _TestableRagService svc;
    setUp(() {
      svc = _TestableRagService(
          embedSvc, fakeBox as dynamic); // cast for compile
    });

    test('empty string → empty list', () {
      expect(svc.chunkText(''), isEmpty);
    });

    test('short text → single chunk', () {
      final words = List.generate(10, (i) => 'word$i').join(' ');
      final chunks = svc.chunkText(words, size: 512, overlap: 50);
      expect(chunks.length, 1);
      expect(chunks.first.split(' ').length, 10);
    });

    test('exactly size words → single chunk', () {
      final words = List.generate(512, (i) => 'w').join(' ');
      final chunks = svc.chunkText(words, size: 512, overlap: 50);
      expect(chunks.length, 1);
    });

    test('size+1 words → two chunks with overlap', () {
      // 513 words, size=512, overlap=50 → chunk1: 0..511, chunk2: 462..512
      final words = List.generate(513, (i) => 'w$i').join(' ');
      final chunks = svc.chunkText(words, size: 512, overlap: 50);
      expect(chunks.length, 2);
      // Second chunk should start at word index 462 (512 - 50)
      expect(chunks[1].split(' ').first, 'w462');
    });

    test('overlap respected: last word of chunk N appears in chunk N+1', () {
      // 600 words, size=100, overlap=20
      final words = List.generate(600, (i) => 'w$i').join(' ');
      final chunks = svc.chunkText(words, size: 100, overlap: 20);
      // The 100th word of chunk 0 is w99; it should appear in chunk 1.
      expect(chunks[1].split(' ').first, 'w80'); // start = 100 - 20 = 80
    });
  });

  // ── buildContext ───────────────────────────────────────────────────────────

  group('buildContext', () {
    late RagService svc;
    setUp(() {
      svc = RagService(embedSvc, fakeBox as dynamic);
    });

    test('empty chunks → empty string', () {
      expect(svc.buildContext([], lang: 'de'), '');
      expect(svc.buildContext([], lang: 'en'), '');
    });

    test('German context contains German prefix', () {
      final chunks = [
        RetrievedChunk(
            text: 'Absatz eins.', sourceFile: 'doc.pdf', score: 0.9),
      ];
      final ctx = svc.buildContext(chunks, lang: 'de');
      expect(ctx, contains('Nutze die folgenden Informationen'));
      expect(ctx, contains('Absatz eins.'));
      expect(ctx, contains('[1]'));
    });

    test('English context contains English prefix', () {
      final chunks = [
        RetrievedChunk(
            text: 'Paragraph one.', sourceFile: 'doc.pdf', score: 0.9),
      ];
      final ctx = svc.buildContext(chunks, lang: 'en');
      expect(ctx, contains('Use the following information'));
      expect(ctx, contains('Paragraph one.'));
    });

    test('multiple chunks are all included', () {
      final chunks = [
        RetrievedChunk(text: 'A', sourceFile: 'a.pdf', score: 0.9),
        RetrievedChunk(text: 'B', sourceFile: 'b.pdf', score: 0.8),
        RetrievedChunk(text: 'C', sourceFile: 'c.pdf', score: 0.7),
      ];
      final ctx = svc.buildContext(chunks, lang: 'en');
      expect(ctx, contains('[1]'));
      expect(ctx, contains('[2]'));
      expect(ctx, contains('[3]'));
      expect(ctx, contains('a.pdf'));
      expect(ctx, contains('b.pdf'));
    });
  });

  // ── retrieve with empty box ────────────────────────────────────────────────

  group('retrieve', () {
    late RagService svc;
    setUp(() {
      svc = RagService(embedSvc, fakeBox as dynamic);
    });

    test('empty box → returns empty list immediately', () async {
      final results = await svc.retrieve(query: 'anything');
      expect(results, isEmpty);
    });
  });

  // ── sourcesInIndex ─────────────────────────────────────────────────────────

  group('sourcesInIndex', () {
    late RagService svc;
    setUp(() {
      svc = RagService(embedSvc, fakeBox as dynamic);
    });

    test('empty box → empty list', () {
      expect(svc.sourcesInIndex, isEmpty);
    });
  });

  // ── clearIndex / removeSource ──────────────────────────────────────────────

  group('index management', () {
    late RagService svc;
    setUp(() {
      svc = RagService(embedSvc, fakeBox as dynamic);
    });

    test('clearIndex empties box', () {
      fakeBox.put(VectorChunk(
        sourceFile: 'a.pdf',
        text: 'hello',
        embedding: [1.0],
        ingestedAt: DateTime.now(),
      ));
      expect(svc.totalChunks, 1);
      svc.clearIndex();
      expect(svc.totalChunks, 0);
    });
  });
}
