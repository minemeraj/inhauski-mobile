import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';

/// ChatHistory manages in-memory chat sessions.
///
/// TODO: Persist to SQLite via drift for production.
class ChatHistory extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  String _sessionId = '';

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isEmpty => _messages.isEmpty;

  ChatHistory() {
    _newSession();
  }

  void _newSession() {
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  }

  void addMessage(ChatMessage message) {
    _messages.add(message);
    notifyListeners();
  }

  void updateLastAssistantMessage(String delta) {
    if (_messages.isNotEmpty && _messages.last.role == MessageRole.assistant) {
      _messages.last = _messages.last.copyWith(
        content: _messages.last.content + delta,
      );
      notifyListeners();
    }
  }

  void addAssistantPlaceholder() {
    _messages.add(ChatMessage(
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
    ));
    notifyListeners();
  }

  void clearSession() {
    _messages.clear();
    _newSession();
    notifyListeners();
  }

  /// Convert messages to the format expected by LlamaService.chat()
  List<Map<String, String>> toApiMessages() {
    return _messages.map((m) => {
      'role': m.role.name,
      'content': m.content,
    }).toList();
  }
}
