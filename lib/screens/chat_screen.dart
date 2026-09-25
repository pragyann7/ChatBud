import 'dart:math';
import 'package:flutter/material.dart';
import 'package:chatbud/models/message.dart';
import 'package:chatbud/services/llm_service.dart';
import 'package:chatbud/widgets/chat_input.dart';
import 'package:chatbud/widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Message> _messages = [
    Message(id: _newMessageId(), text: "Hello, ChatBud", isUser: true),
    Message(
      id: _newMessageId(),
      text: "Hello there, how are you?",
      isUser: false,
    ),
  ];
  final Map<String, ValueNotifier<String>> _streamingNotifiers = {};
  final Set<String> _activeMessageIds = {};
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final LlmService _llmService = LlmService();
  bool _showScrollToLatest = false;

  bool get _isGenerating => _activeMessageIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.position.pixels > 40;
    if (shouldShow != _showScrollToLatest && mounted) {
      setState(() => _showScrollToLatest = shouldShow);
    }
  }

  void _scrollToLatest({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (force || _scrollController.position.pixels <= 40) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_isGenerating) return;
    final prompt = _textController.text.trim();
    if (prompt.isEmpty) return;

    _textController.clear();
    final userMessage = Message(
      id: _newMessageId(),
      text: prompt,
      isUser: true,
    );
    final assistantId = _newMessageId();
    final notifier = ValueNotifier<String>("");

    setState(() {
      _activeMessageIds.add(assistantId);
      _streamingNotifiers[assistantId] = notifier;
      _messages
        ..add(userMessage)
        ..add(Message(id: assistantId, text: "", isUser: false));
    });
    _scrollToLatest(force: true);

    final response = StringBuffer();
    var lastPublished = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await for (final token in _llmService.generate(prompt)) {
        if (!mounted) return;
        response.write(token);
        final now = DateTime.now();
        // Limit widget notifications to roughly one per frame.
        if (now.difference(lastPublished).inMilliseconds >= 16) {
          notifier.value = response.toString();
          lastPublished = now;
        }
      }
      if (!mounted) return;
      notifier.value = response.toString();
      _completeMessage(assistantId, response.toString(), notifier);
    } catch (error, stackTrace) {
      debugPrint("Chat response stream failed: $error\n$stackTrace");
      if (!mounted) return;
      const userFacingError =
          "Sorry, I couldn’t finish that response. Please try again.";
      notifier.value = userFacingError;
      _completeMessage(assistantId, userFacingError, notifier);
    } finally {
      if (mounted && _activeMessageIds.contains(assistantId)) {
        _completeMessage(assistantId, response.toString(), notifier);
      }
    }
  }

  void _completeMessage(
    String messageId,
    String text,
    ValueNotifier<String> notifier,
  ) {
    final index = _messages.indexWhere((message) => message.id == messageId);
    setState(() {
      if (index != -1) {
        final oldMessage = _messages[index];
        _messages[index] = Message(
          id: oldMessage.id,
          text: text,
          isUser: oldMessage.isUser,
        );
      }
      _activeMessageIds.remove(messageId);
      _streamingNotifiers.remove(messageId);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => notifier.dispose());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _textController.dispose();
    _scrollController.dispose();
    for (final notifier in _streamingNotifiers.values) {
      notifier.dispose();
    }
    _streamingNotifiers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              ListView.builder(
                controller: _scrollController,
                reverse: true,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[_messages.length - 1 - index];
                  return MessageBubble(
                    key: ValueKey(message.id),
                    message: message,
                    textListenable: _streamingNotifiers[message.id],
                  );
                },
              ),
              if (_showScrollToLatest)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    tooltip: "Scroll to latest",
                    onPressed: () => _scrollToLatest(force: true),
                    child: const Icon(Icons.arrow_downward_rounded),
                  ),
                ),
            ],
          ),
        ),
        ChatInput(
          controller: _textController,
          isGenerating: _isGenerating,
          onSend: _sendMessage,
          onAddAttachment: () {},
        ),
      ],
    );
  }
}

String _newMessageId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, "0"))
      .join();
  return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}";
}
