import 'dart:io';
import 'package:objectbox/objectbox.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'storage/vector_chunk.dart';
export 'storage/vector_chunk.dart';

// The generated binding is in objectbox.g.dart (part of this library).
// objectbox_generator outputs this file at lib/objectbox.g.dart when the
// store file lives at the lib/ root (the standard objectbox project layout).
// Run:  dart run build_runner build --delete-conflicting-outputs
part 'objectbox.g.dart';

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
