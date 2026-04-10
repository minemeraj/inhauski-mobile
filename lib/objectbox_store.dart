import 'dart:io';
import 'package:objectbox/objectbox.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'storage/vector_chunk.dart';
export 'storage/vector_chunk.dart';

// objectbox_generator 5.x outputs a standalone (non-part) file at
// lib/objectbox.g.dart.  Import and re-export it so callers that import
// objectbox_store.dart also get openStore(), VectorChunk_, etc.
// Run:  dart run build_runner build --delete-conflicting-outputs
import 'objectbox.g.dart';
export 'objectbox.g.dart';

/// Singleton wrapper around the ObjectBox [Store].
///
/// Call [ObjectBoxStore.open()] once at app startup and pass the resulting
/// [Store] to any service that needs it.  Close the store when the app exits
/// via [Store.close()].
class ObjectBoxStore {
  final Store store;

  ObjectBoxStore._create(this.store);

  /// Open (or create) the ObjectBox database in the app's documents directory.
  static Future<ObjectBoxStore> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'objectbox');
    await Directory(dbPath).create(recursive: true);
    final store = await openStore(directory: dbPath);
    return ObjectBoxStore._create(store);
  }

  Box<VectorChunk> get vectorChunkBox => store.box<VectorChunk>();
}
