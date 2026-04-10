import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// ── Table definition ────────────────────────────────────────────────────────

/// One row per chat message.
class MessagesTable extends Table {
  @override
  String get tableName => 'messages';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text().withLength(min: 1, max: 64)();
  TextColumn get role => text().withLength(min: 1, max: 16)();
  TextColumn get content => text()();
  DateTimeColumn get timestamp => dateTime()();
}

// ── Database class ──────────────────────────────────────────────────────────

@DriftDatabase(tables: [MessagesTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  // ── Queries ────────────────────────────────────────────────────────────────

  /// Load all messages for [sessionId], ordered by timestamp.
  Future<List<MessagesTableData>> getSession(String sessionId) {
    return (select(messagesTable)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
        .get();
  }

  /// Insert a new message row.
  Future<int> insertMessage(MessagesTableCompanion entry) =>
      into(messagesTable).insert(entry);

  /// Update the content of the last row with the given [id].
  Future<void> updateContent(int id, String newContent) {
    return (update(messagesTable)..where((t) => t.id.equals(id)))
        .write(MessagesTableCompanion(content: Value(newContent)));
  }

  /// Delete all messages for [sessionId].
  Future<void> clearSession(String sessionId) {
    return (delete(messagesTable)
          ..where((t) => t.sessionId.equals(sessionId)))
        .go();
  }
}

// ── Connection helper ───────────────────────────────────────────────────────

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'inhauski_chat.db'));
    return NativeDatabase.createInBackground(file);
  });
}
