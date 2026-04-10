import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/llama_service.dart';
import '../services/rag_service.dart';
import '../storage/chat_history.dart';
import '../models/chat_message.dart';
import '../i18n/app_localizations.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final llama = context.read<LlamaService>();
    final rag = context.read<RagService>();
    final history = context.read<ChatHistory>();

    _controller.clear();

    // Add user message
    history.addMessage(ChatMessage(
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    ));

    // RAG context retrieval (if documents are indexed)
    String systemContext = '';
    if (rag.totalChunks > 0) {
      final lang = Localizations.localeOf(context).languageCode;
      final chunks = await rag.retrieve(query: text);
      systemContext = rag.buildContext(chunks, lang: lang);
    }

    // Snapshot messages BEFORE adding the assistant placeholder,
    // so the model does not see an empty assistant turn at the end.
    final messages = <Map<String, String>>[];
    if (systemContext.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemContext});
    }
    messages.addAll(history.toApiMessages());

    // Add assistant placeholder — visible immediately in the UI
    history.addAssistantPlaceholder();
    _scrollToBottom();

    try {
      await llama.chat(
        messages: messages,
        onToken: (token) {
          history.updateLastAssistantMessage(token);
          _scrollToBottom();
        },
      );
    } catch (e) {
      // Replace the empty placeholder with an error notice so the bubble
      // doesn't stay blank/spinning indefinitely.
      history.updateLastAssistantMessage('[Error: $e]');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final llama = context.watch<LlamaService>();
    final history = context.watch<ChatHistory>();

    return Scaffold(
      appBar: AppBar(
        title: Text('InHausKI'),
        actions: [
          // GPU status badge
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _GpuBadge(gpuMode: llama.gpuMode),
          ),
          // New chat button
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: loc.chatNewSession,
            onPressed: () => context.read<ChatHistory>().clearSession(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Message list
          Expanded(
            child: history.isEmpty
                ? _EmptyState(loc: loc)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: history.messages.length,
                    itemBuilder: (context, i) =>
                        _MessageBubble(message: history.messages[i]),
                  ),
          ),

          // Input bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: llama.isModelLoaded && !llama.isInferring,
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: loc.chatPlaceholder,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    onPressed:
                        llama.isModelLoaded && !llama.isInferring ? _send : null,
                    child: llama.isInferring
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? colorScheme.primaryContainer
              : colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: message.content.isEmpty
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : SelectableText(
                message.content,
                style: TextStyle(
                  color: isUser
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AppLocalizations loc;
  const _EmptyState({required this.loc});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            loc.chatEmptyTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            loc.chatEmptySubtitle,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _GpuBadge extends StatelessWidget {
  final GpuMode gpuMode;
  const _GpuBadge({required this.gpuMode});

  @override
  Widget build(BuildContext context) {
    final isGpu = gpuMode != GpuMode.cpu;
    return Chip(
      avatar: Icon(
        isGpu ? Icons.bolt : Icons.memory,
        size: 14,
        color: isGpu
            ? Colors.green.shade700
            : Theme.of(context).colorScheme.outline,
      ),
      label: Text(
        isGpu ? 'GPU' : 'CPU',
        style: const TextStyle(fontSize: 11),
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
