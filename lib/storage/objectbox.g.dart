// GENERATED CODE - DO NOT MODIFY BY HAND
// Re-generate with: dart run build_runner build --delete-conflicting-outputs

// ignore_for_file: camel_case_types, depend_on_referenced_packages
// ignore_for_file: directives_ordering, lines_longer_than_80_chars

part of 'objectbox_store.dart';

// ── Model info ───────────────────────────────────────────────────────────────

/// ObjectBox model used for schema migration and code generation.
ModelDefinition getObjectBoxModel() {
  final model = ModelDefinition(
    entities: [
      ModelEntity(
        id: const IdUid(1, 1),
        name: 'VectorChunk',
        lastPropertyId: const IdUid(5, 5),
        flags: 0,
        properties: [
          ModelProperty(
            id: const IdUid(1, 1),
            name: 'id',
            type: OBXPropertyType.Long,
            flags: OBXPropertyFlags.ID,
          ),
          ModelProperty(
            id: const IdUid(2, 2),
            name: 'sourceFile',
            type: OBXPropertyType.String,
          ),
          ModelProperty(
            id: const IdUid(3, 3),
            name: 'text',
            type: OBXPropertyType.String,
          ),
          ModelProperty(
            id: const IdUid(4, 4),
            name: 'embedding',
            type: OBXPropertyType.FloatVector,
            flags: OBXPropertyFlags.INDEXED,
            indexId: const IdUid(1, 1),
          ),
          ModelProperty(
            id: const IdUid(5, 5),
            name: 'ingestedAt',
            type: OBXPropertyType.Date,
          ),
        ],
        relations: [],
        backlinks: [],
      ),
    ],
    lastEntityId: const IdUid(1, 1),
    lastIndexId: const IdUid(1, 1),
    lastRelationId: const IdUid(0, 0),
    lastSequenceId: const IdUid(0, 0),
    retiredEntityUids: [],
    retiredIndexUids: [],
    retiredPropertyUids: [],
    retiredRelationUids: [],
    modelVersion: 5,
    modelVersionParserMinimum: 5,
    version: 1,
  );
  return model;
}

// ── Store open helper ────────────────────────────────────────────────────────

/// Opens an ObjectBox [Store] at [directory] using the model above.
Future<Store> openStore({
  String? directory,
  int? maxDBSizeInKB,
  int? fileMode,
  int? maxReaders,
  bool queriesCaseSensitiveDefault = true,
  String? macosApplicationGroup,
}) async =>
    Store(
      getObjectBoxModel(),
      directory: directory,
      maxDBSizeInKB: maxDBSizeInKB,
      fileMode: fileMode,
      maxReaders: maxReaders,
      queriesCaseSensitiveDefault: queriesCaseSensitiveDefault,
      macosApplicationGroup: macosApplicationGroup,
    );

// ── VectorChunk entity binding ───────────────────────────────────────────────

class VectorChunk_ {
  static final id =
      QueryIntegerProperty<VectorChunk>(_VectorChunk.id);
  static final sourceFile =
      QueryStringProperty<VectorChunk>(_VectorChunk.sourceFile);
  static final text =
      QueryStringProperty<VectorChunk>(_VectorChunk.text);
  static final embedding =
      QueryHnswProperty<VectorChunk>(_VectorChunk.embedding);
  static final ingestedAt =
      QueryIntegerProperty<VectorChunk>(_VectorChunk.ingestedAt);
}

class _VectorChunk {
  static final EntityDefinition<VectorChunk> entityDef = EntityDefinition(
    model: _entityModel(),
    toOneRelations: (obj) => [],
    toManyRelations: (obj) => {},
    getId: (obj) => obj.id,
    setId: (obj, id) => obj.id = id,
    objectToFB: (obj, fbb) {
      final sourceFileOffset = fbb.writeString(obj.sourceFile);
      final textOffset = fbb.writeString(obj.text);
      final embeddingOffset = fbb.writeListFloat32(
          obj.embedding.map((e) => e.toDouble()).toList());
      fbb.startTable(6);
      fbb.addInt64(0, obj.id);
      fbb.addOffset(1, sourceFileOffset);
      fbb.addOffset(2, textOffset);
      fbb.addOffset(3, embeddingOffset);
      fbb.addInt64(4, obj.ingestedAt.millisecondsSinceEpoch);
      fbb.finish(fbb.endTable());
      return obj.id;
    },
    objectFromFB: (store, rootTable) {
      final id = rootTable.readInt64(0) ?? 0;
      final sourceFile = rootTable.readString(1) ?? '';
      final text = rootTable.readString(2) ?? '';
      final rawEmb = rootTable.readListFloat32(3) ?? <double>[];
      final tsMs = rootTable.readInt64(4) ?? 0;
      return VectorChunk(
        id: id,
        sourceFile: sourceFile,
        text: text,
        embedding: rawEmb,
        ingestedAt: DateTime.fromMillisecondsSinceEpoch(tsMs),
      );
    },
  );

  static ModelEntity _entityModel() => ModelEntity(
        id: const IdUid(1, 1),
        name: 'VectorChunk',
        lastPropertyId: const IdUid(5, 5),
        flags: 0,
        properties: [
          ModelProperty(
              id: const IdUid(1, 1),
              name: 'id',
              type: OBXPropertyType.Long,
              flags: OBXPropertyFlags.ID),
          ModelProperty(
              id: const IdUid(2, 2),
              name: 'sourceFile',
              type: OBXPropertyType.String),
          ModelProperty(
              id: const IdUid(3, 3),
              name: 'text',
              type: OBXPropertyType.String),
          ModelProperty(
              id: const IdUid(4, 4),
              name: 'embedding',
              type: OBXPropertyType.FloatVector,
              flags: OBXPropertyFlags.INDEXED,
              indexId: const IdUid(1, 1)),
          ModelProperty(
              id: const IdUid(5, 5),
              name: 'ingestedAt',
              type: OBXPropertyType.Date),
        ],
        relations: [],
        backlinks: [],
      );

  // Property descriptors used by query builders
  static final id = ModelProperty(
      id: const IdUid(1, 1),
      name: 'id',
      type: OBXPropertyType.Long,
      flags: OBXPropertyFlags.ID);
  static final sourceFile = ModelProperty(
      id: const IdUid(2, 2),
      name: 'sourceFile',
      type: OBXPropertyType.String);
  static final text = ModelProperty(
      id: const IdUid(3, 3),
      name: 'text',
      type: OBXPropertyType.String);
  static final embedding = ModelProperty(
      id: const IdUid(4, 4),
      name: 'embedding',
      type: OBXPropertyType.FloatVector,
      flags: OBXPropertyFlags.INDEXED,
      indexId: const IdUid(1, 1));
  static final ingestedAt = ModelProperty(
      id: const IdUid(5, 5),
      name: 'ingestedAt',
      type: OBXPropertyType.Date);
}
