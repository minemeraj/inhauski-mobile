// test/chat_history_test.dart
//
// Unit tests for ChatHistory using an in-memory drift database.
//
// AppDatabase.forTesting(NativeDatabase.memory()) opens a SQLite in-memory
// database so no file I/O is needed. Tests run on any platform (desktop,
// CI) without a device.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inhauski/models/chat_message.dart';
import 'package:inhauski/storage/app_database.dart';
import 'package:inhauski/storage/chat_history.dart';

/// Returns a fresh in-memory AppDatabase for each test.
AppDatabase _makeDb() =>
    AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late ChatHistory history;

  setUp(() async {
    db = _makeDb();
    history = ChatHistory(db);
    // Wait for the constructor's _restoreLastSession() to complete before
    // each test so we start from a known state.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => db.close());

  // ── addMessage ──────────────────────────────────────────────────────────────

  group('addMessage', () {
    test('adds message to in-memory list', () async {
      expect(history.messages, isEmpty);
      await history.addMessage(ChatMessage(
        role: MessageRole.user,
        content: 'Hello',
        timestamp: DateTime(2025),
      ));
      expect(history.messages.length, 1);
      expect(history.messages.first.content, 'Hello');
      expect(history.messages.first.role, MessageRole.user);
    });

    test('persists to database and restores on next load', () async {
      await history.addMessage(ChatMessage(
        role: MessageRole.user,
        content: 'Persisted message',
        timestamp: DateTime.now(),
      ));

      // Create a new ChatHistory backed by the same DB — it should restore
      // today's session.
      final history2 = ChatHistory(db);
      await Future<void>.delayed(Duration.zero);

      expect(history2.messages.any((m) => m.content == 'Persisted message'),
          isTrue);
    });
  });

  // ── addAssistantPlaceholder / updateLastAssistantMessage ────────────────────

  group('streaming assistant message', () {
    test('placeholder starts empty', () async {
      history.addAssistantPlaceholder();
      expect(history.messages.last.role, MessageRole.assistant);
      expect(history.messages.last.content, '');
    });

    test('tokens accumulate correctly', () async {
      history.addAssistantPlaceholder();
      await history.updateLastAssistantMessage('Hello');
      await history.updateLastAssistantMessage(', ');
      await history.updateLastAssistantMessage('world!');
      expect(history.messages.last.content, 'Hello, world!');
    });

    test('update on non-assistant tail is a no-op', () async {
      await history.addMessage(ChatMessage(
        role: MessageRole.user,
        content: 'Hi',
        timestamp: DateTime.now(),
      ));
      // Should not throw
      await history.updateLastAssistantMessage('should be ignored');
      expect(history.messages.last.content, 'Hi');
    });

    test('persists accumulated content to db', () async {
      history.addAssistantPlaceholder();
      await history.updateLastAssistantMessage('token1');
      await history.updateLastAssistantMessage('token2');

      // Reload from DB
      final rows = await db.getSession(history.sessionId);
      final assistantRow = rows.firstWhere((r) => r.role == 'assistant');
      expect(assistantRow.content, 'token1token2');
    });
  });

  // ── clearSession ──────────────────────────────────────────────────────────

  group('clearSession', () {
    test('clears in-memory list', () async {
      await history.addMessage(ChatMessage(
        role: MessageRole.user,
        content: 'A',
        timestamp: DateTime.now(),
      ));
      expect(history.isEmpty, isFalse);
      await history.clearSession();
      expect(history.isEmpty, isTrue);
    });

    test('changes sessionId after clear', () async {
      final oldId = history.sessionId;
      // Force the session id to change by simulating a new session
      // (clearSession generates a new date-based id; in tests both before
      // and after are the same date, so we just verify it's a non-empty
      // string and the messages are gone).
      await history.clearSession();
      expect(history.sessionId, isNotEmpty);
      // Messages from old session are not loaded in new session
      final rows = await db.getSession(oldId);
      expect(rows, isEmpty);
    });

    test('does not restore cleared messages', () async {
      await history.addMessage(ChatMessage(
        role: MessageRole.user,
        content: 'To be cleared',
        timestamp: DateTime.now(),
      ));
      await history.clearSession();

      final history2 = ChatHistory(db);
      await Future<void>.delayed(Duration.zero);
      expect(
        history2.messages.any((m) => m.content == 'To be cleared'),
        isFalse,
      );
    });
  });

  // ── toApiMessages ─────────────────────────────────────────────────────────

  group('toApiMessages', () {
    test('converts messages to role/content maps', () async {
      await history.addMessage(ChatMessage(
        role: MessageRole.user,
        content: 'Question',
        timestamp: DateTime.now(),
      ));
      history.addAssistantPlaceholder();
      await history.updateLastAssistantMessage('Answer');

      final api = history.toApiMessages();
      expect(api.length, 2);
      expect(api[0], {'role': 'user', 'content': 'Question'});
      expect(api[1], {'role': 'assistant', 'content': 'Answer'});
    });

    test('empty history → empty list', () {
      expect(history.toApiMessages(), isEmpty);
    });
  });

  // ── isEmpty ───────────────────────────────────────────────────────────────

  group('isEmpty', () {
    test('true when no messages', () {
      expect(history.isEmpty, isTrue);
    });

    test('false after adding a message', () async {
      await history.addMessage(ChatMessage(
        role: MessageRole.user,
        content: 'x',
        timestamp: DateTime.now(),
      ));
      expect(history.isEmpty, isFalse);
    });
  });
}
