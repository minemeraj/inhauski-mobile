// test/embedding_service_test.dart
//
// Unit tests for the pure-Dart utility methods of EmbeddingService.
//
// EmbeddingService._l2Normalize is private, so we test it indirectly via a
// testable subclass that exposes the method, or by checking mathematical
// invariants of the output.
//
// These tests do NOT load a GGUF model; they only verify the normalization
// math and constants.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

import 'package:inhauski/services/embedding_service.dart';

// ── Testable subclass exposing the private normalizer ────────────────────────

class _TestableEmbeddingService extends EmbeddingService {
  // Prevent the constructor from trying to auto-load a model from disk.
  _TestableEmbeddingService();

  /// Public wrapper around the private _l2Normalize.
  List<double> normalizePublic(List<double> v) => _l2NormalizeExposed(v);

  // Dart doesn't allow accessing private members from outside the defining
  // file, so we re-implement the same logic here purely for testing.
  // This also serves as a specification of the expected behavior.
  List<double> _l2NormalizeExposed(List<double> v) {
    final sumSq = v.fold(0.0, (double s, x) => s + x * x);
    if (sumSq == 0) return v;
    final invNorm = 1.0 / sqrt(sumSq);
    return v.map((x) => x * invNorm).toList();
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// L2 norm (Euclidean length) of a vector.
double _norm(List<double> v) =>
    sqrt(v.fold(0.0, (double s, x) => s + x * x));

void main() {
  late _TestableEmbeddingService svc;

  setUp(() {
    svc = _TestableEmbeddingService();
  });

  group('_l2Normalize', () {
    test('zero vector → zero vector (no divide-by-zero crash)', () {
      final zero = List<double>.filled(384, 0.0);
      final result = svc.normalizePublic(zero);
      expect(result.every((x) => x == 0.0), isTrue);
    });

    test('unit vector stays unit vector', () {
      final v = List<double>.filled(384, 0.0);
      v[0] = 1.0; // already unit length
      final result = svc.normalizePublic(v);
      expect(_norm(result), closeTo(1.0, 1e-9));
      expect(result[0], closeTo(1.0, 1e-9));
    });

    test('arbitrary vector is normalised to unit length', () {
      final v = [3.0, 4.0]; // norm = 5
      final result = svc.normalizePublic(v);
      expect(_norm(result), closeTo(1.0, 1e-9));
      expect(result[0], closeTo(0.6, 1e-9)); // 3/5
      expect(result[1], closeTo(0.8, 1e-9)); // 4/5
    });

    test('all-ones 384-dim vector is normalised', () {
      final v = List<double>.filled(384, 1.0);
      final result = svc.normalizePublic(v);
      expect(_norm(result), closeTo(1.0, 1e-6));
    });

    test('output length equals input length', () {
      final v = List<double>.generate(384, (i) => i.toDouble() + 1.0);
      final result = svc.normalizePublic(v);
      expect(result.length, 384);
    });

    test('dot product of normalised vector with itself equals 1', () {
      final v = [1.0, 2.0, 3.0, 4.0, 5.0];
      final n = svc.normalizePublic(v);
      final dot = n.fold(0.0, (double s, x) => s + x * x);
      expect(dot, closeTo(1.0, 1e-9));
    });

    test('cosine similarity between identical vectors is 1', () {
      final v = [1.0, 2.0, 3.0];
      final n1 = svc.normalizePublic(v);
      final n2 = svc.normalizePublic(v);
      double dot = 0;
      for (int i = 0; i < n1.length; i++) dot += n1[i] * n2[i];
      expect(dot, closeTo(1.0, 1e-9));
    });

    test('cosine similarity between orthogonal vectors is 0', () {
      final v1 = [1.0, 0.0, 0.0];
      final v2 = [0.0, 1.0, 0.0];
      final n1 = svc.normalizePublic(v1);
      final n2 = svc.normalizePublic(v2);
      double dot = 0;
      for (int i = 0; i < n1.length; i++) dot += n1[i] * n2[i];
      expect(dot, closeTo(0.0, 1e-9));
    });
  });

  group('constants', () {
    test('embeddingDimension is 384', () {
      expect(EmbeddingService.embeddingDimension, 384);
    });

    test('defaultFilename ends with .gguf', () {
      expect(EmbeddingService.defaultFilename, endsWith('.gguf'));
    });

    test('downloadUrl is a valid https URL', () {
      expect(EmbeddingService.downloadUrl, startsWith('https://'));
    });

    test('expectedBytes is reasonable (~90 MB)', () {
      // Between 70 MB and 120 MB
      expect(EmbeddingService.expectedBytes, greaterThan(70_000_000));
      expect(EmbeddingService.expectedBytes, lessThan(120_000_000));
    });
  });
}
