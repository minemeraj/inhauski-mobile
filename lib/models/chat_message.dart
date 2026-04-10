enum MessageRole { user, assistant, system }

class ChatMessage {
  final MessageRole role;
  final String content;
  final DateTime timestamp;

  const ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  ChatMessage copyWith({
    MessageRole? role,
    String? content,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
