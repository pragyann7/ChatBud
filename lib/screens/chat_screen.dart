import 'package:flutter/material.dart';
import 'package:chatbud/models/conversation.dart';
import 'package:chatbud/models/message.dart';
import 'package:chatbud/repositories/chat_repository.dart';
import 'package:chatbud/services/llm_service.dart';
import 'package:chatbud/widgets/chat_input.dart';
import 'package:chatbud/widgets/message_bubble.dart';
import 'package:provider/provider.dart';

class ChatScreen extends StatefulWidget {
  final Conversation? conversation;
  final ValueChanged<Conversation>? onConversationCreated;

  const ChatScreen({
    super.key,
    this.conversation,
    this.onConversationCreated,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late ChatRepository _chatRepository;
  Conversation? _currentConversation;
  List<Message> _messages = [];
  bool _isLoading = true;

  final Map<int, ValueNotifier<String>> _streamingNotifiers = {};
  final Set<int> _activeMessageIds = {};
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) {
      _chatRepository = Provider.of<ChatRepository>(context, listen: false);
      _loadActiveConversationAndMessages();
    }
  }

  Future<void> _loadActiveConversationAndMessages() async {
    // Clean up any empty conversations from database
    await _chatRepository.cleanUpEmptyConversations();

    if (widget.conversation != null) {
      final savedMessages =
          await _chatRepository.getMessagesForConversation(widget.conversation!.id);
      if (mounted) {
        setState(() {
          _currentConversation = widget.conversation;
          _messages = savedMessages;
          _isLoading = false;
        });
      }
    } else {
      // New unsaved chat: start with empty messages and DO NOT create database row yet!
      if (mounted) {
        setState(() {
          _currentConversation = null;
          _messages = [];
          _isLoading = false;
        });
      }
    }
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
    final now = DateTime.now();

    // ChatGPT behavior: Lazy creation on first prompt send!
    if (_currentConversation == null) {
      final title =
          prompt.length > 25 ? "${prompt.substring(0, 25)}..." : prompt;
      _currentConversation =
          await _chatRepository.createNewConversation(title);
      widget.onConversationCreated?.call(_currentConversation!);
    }

    final convId = _currentConversation!.id;

    final userMessage = Message(
      id: _newMessageId(),
      conversationId: convId,
      text: prompt,
      role: MessageRole.user,
      createdAt: now,
    );
    final assistantId = _newMessageId();
    final assistantMessage = Message(
      id: assistantId,
      conversationId: convId,
      text: "",
      role: MessageRole.assistant,
      createdAt: now,
    );
    final notifier = ValueNotifier<String>("");

    // Persist new user message and assistant placeholder to Isar
    await _chatRepository.saveMessage(userMessage);
    await _chatRepository.saveMessage(assistantMessage);

    setState(() {
      _activeMessageIds.add(assistantId);
      _streamingNotifiers[assistantId] = notifier;
      _messages
        ..add(userMessage)
        ..add(assistantMessage);
    });
    _scrollToLatest(force: true);

    final response = StringBuffer();
    var lastPublished = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await for (final token in _llmService.generate(prompt)) {
        if (!mounted) return;
        response.write(token);
        final currentTime = DateTime.now();
        if (currentTime.difference(lastPublished).inMilliseconds >= 16) {
          notifier.value = response.toString();
          lastPublished = currentTime;
        }
      }
      if (!mounted) return;
      notifier.value = response.toString();
      await _completeMessage(assistantId, response.toString(), notifier);
    } catch (error, stackTrace) {
      debugPrint("Chat response stream failed: $error\n$stackTrace");
      if (!mounted) return;
      const userFacingError =
          "Sorry, I couldn’t finish that response. Please try again.";
      notifier.value = userFacingError;
      await _completeMessage(assistantId, userFacingError, notifier);
    } finally {
      if (mounted && _activeMessageIds.contains(assistantId)) {
        await _completeMessage(assistantId, response.toString(), notifier);
      }
    }
  }

  Future<void> _completeMessage(
    int messageId,
    String text,
    ValueNotifier<String> notifier,
  ) async {
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index != -1) {
      final oldMessage = _messages[index];
      final updatedMsg = Message(
        id: oldMessage.id,
        conversationId: oldMessage.conversationId,
        text: text,
        role: oldMessage.role,
        createdAt: oldMessage.createdAt,
      );

      // Save final message text to Isar database
      await _chatRepository.saveMessage(updatedMsg);

      if (mounted) {
        setState(() {
          _messages[index] = updatedMsg;
          _activeMessageIds.remove(messageId);
          _streamingNotifiers.remove(messageId);
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _activeMessageIds.remove(messageId);
          _streamingNotifiers.remove(messageId);
        });
      }
    }
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              if (_messages.isEmpty)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Ready. Offline. Yours.",
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        "Your personal AI, always on your device.",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.normal, fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
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

int _newMessageId() {
  return DateTime.now().microsecondsSinceEpoch;
}
