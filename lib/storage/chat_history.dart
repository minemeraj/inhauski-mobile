import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import 'app_database.dart';

/// ChatHistory manages the current chat session.
///
/// Messages are persisted to SQLite via drift so they survive app restarts.
/// The public API is identical to the previous in-memory version so that
/// ChatScreen requires no changes.
class ChatHistory extends ChangeNotifier {
  final AppDatabase _db;

  final List<ChatMessage> _messages = [];
  // Parallel list of DB row IDs — null for assistant placeholder rows that
  // have not yet been flushed (they get an id once the first token arrives).
  final List<int?> _rowIds = [];

  String _sessionId = '';

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isEmpty => _messages.isEmpty;
  String get sessionId => _sessionId;

  ChatHistory(this._db) {
    _restoreLastSession();
  }

  // ── Initialization ─────────────────────────────────────────────────────────

  /// Load the most recent session from the database on startup.
  Future<void> _restoreLastSession() async {
    // Use today's date-stamp as the restored session id.  A proper
    // implementation would persist the active session id separately; for now
    // the simplest heuristic is sufficient.
    _sessionId = _makeSessionId();

    // Re-use the same session id across restarts within the same day.
    // (A future settings option can let the user clear history.)
    final rows = await _db.getSession(_sessionId);
    for (final row in rows) {
      _messages.add(_rowToMessage(row));
      _rowIds.add(row.id);
    }
    if (rows.isNotEmpty) notifyListeners();
  }

  // ── Public API (same as before) ────────────────────────────────────────────

  Future<void> addMessage(ChatMessage message) async {
    _messages.add(message);
    final id = await _db.insertMessage(MessagesTableCompanion(
      sessionId: Value(_sessionId),
      role: Value(message.role.name),
      content: Value(message.content),
      timestamp: Value(message.timestamp),
    ));
    _rowIds.add(id);
    notifyListeners();
  }

  /// Append [delta] to the last assistant message and persist.
  Future<void> updateLastAssistantMessage(String delta) async {
    if (_messages.isEmpty || _messages.last.role != MessageRole.assistant) {
      return;
    }
    final idx = _messages.length - 1;
    final updated = _messages[idx].copyWith(
      content: _messages[idx].content + delta,
    );
    _messages[idx] = updated;

    // Persist: if there is already a row id, update it; otherwise insert now.
    if (_rowIds[idx] != null) {
      await _db.updateContent(_rowIds[idx]!, updated.content);
    } else {
      final id = await _db.insertMessage(MessagesTableCompanion(
        sessionId: Value(_sessionId),
        role: Value(updated.role.name),
        content: Value(updated.content),
        timestamp: Value(updated.timestamp),
      ));
      _rowIds[idx] = id;
    }
    notifyListeners();
  }

  void addAssistantPlaceholder() {
    _messages.add(ChatMessage(
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
    ));
    // Row not yet written — we defer the INSERT until the first token so we
    // don't persist empty rows.
    _rowIds.add(null);
    notifyListeners();
  }

  Future<void> clearSession() async {
    await _db.clearSession(_sessionId);
    _messages.clear();
    _rowIds.clear();
    _sessionId = _makeSessionId();
    notifyListeners();
  }

  /// Convert messages to the format expected by LlamaService.chat().
  List<Map<String, String>> toApiMessages() {
    return _messages
        .map((m) => {'role': m.role.name, 'content': m.content})
        .toList();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static ChatMessage _rowToMessage(MessagesTableData row) {
    return ChatMessage(
      role: MessageRole.values.firstWhere(
        (r) => r.name == row.role,
        orElse: () => MessageRole.user,
      ),
      content: row.content,
      timestamp: row.timestamp,
    );
  }

  /// Session id = date-based so today's conversation is always restored.
  static String _makeSessionId() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
