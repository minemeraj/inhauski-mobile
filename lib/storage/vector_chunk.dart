import 'package:objectbox/objectbox.dart';

/// Persisted embedding chunk stored in the ObjectBox vector store.
///
/// The [embedding] field carries a 384-dimensional float32 vector produced
/// by multilingual-e5-small.  ObjectBox's HNSW index makes nearest-neighbour
/// search fast without a full scan.
@Entity()
class VectorChunk {
  @Id()
  int id;

  /// Which document this chunk came from.
  String sourceFile;

  /// The raw text that was embedded.
  String text;

  /// 384-dim float32 embedding from multilingual-e5-small.
  /// ObjectBox 5.x requires @Property(type: PropertyType.floatVector)
  /// alongside @HnswIndex for float vector properties.
  @Property(type: PropertyType.floatVector)
  @HnswIndex(dimensions: 384)
  List<double> embedding;

  /// Wall-clock time of ingestion — useful for cache invalidation later.
  @Property(type: PropertyType.date)
  DateTime ingestedAt;

  VectorChunk({
    this.id = 0,
    required this.sourceFile,
    required this.text,
    required this.embedding,
    required this.ingestedAt,
  });
}
