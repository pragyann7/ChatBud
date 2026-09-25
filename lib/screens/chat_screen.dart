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
  bool _isSubmitting = false;

  final Map<int, ValueNotifier<String>> _streamingNotifiers = {};
  final Set<int> _activeMessageIds = {};
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final LlmService _llmService = LlmService();
  bool _showScrollToLatest = false;

  bool get _isGenerating => _activeMessageIds.isNotEmpty || _isSubmitting;

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
    if (widget.conversation != null) {
      final savedMessages =
          await _chatRepository.getMessagesForConversation(widget.conversation!.id);

      // Recover any pending/interrupted messages from disk
      for (int i = 0; i < savedMessages.length; i++) {
        final msg = savedMessages[i];
        if (msg.status == MessageStatus.pending) {
          final recovered = Message(
            id: msg.id,
            conversationId: msg.conversationId,
            text: msg.text.isEmpty ? "Response interrupted." : msg.text,
            role: msg.role,
            status: MessageStatus.failed,
            createdAt: msg.createdAt,
          );
          savedMessages[i] = recovered;
          await _chatRepository.saveMessageAndTouchConversation(recovered);
        }
      }

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
    if (_isSubmitting || _isGenerating) return;

    final prompt = _textController.text.trim();
    if (prompt.isEmpty) return;

    final isNewConversation = _currentConversation == null;
    _isSubmitting = true; // Set synchronously to block duplicate taps.
    setState(() {});
    _textController.clear();
    final now = DateTime.now();

    try {
      // Lazy conversation creation on first prompt send
      if (_currentConversation == null) {
        final title =
            prompt.length > 25 ? "${prompt.substring(0, 25)}..." : prompt;
        _currentConversation = Conversation(
          title: title,
          createdAt: now,
          updatedAt: now,
        );
      } else {
        _currentConversation = _currentConversation!.copyWith(
          updatedAt: now,
        );
      }

      final userMessage = Message(
        conversationId: _currentConversation!.id,
        text: prompt,
        role: MessageRole.user,
        status: MessageStatus.completed,
        createdAt: now,
      );
      final assistantMessage = Message(
        conversationId: _currentConversation!.id,
        text: "",
        role: MessageRole.assistant,
        status: MessageStatus.pending,
        createdAt: now,
      );

      // Persist conversation, user message, and assistant placeholder atomically
      final savedMessages = await _chatRepository.saveMessagePairAndTouchConversation(
        conversation: _currentConversation!,
        userMessage: userMessage,
        assistantMessage: assistantMessage,
      );

      widget.onConversationCreated?.call(_currentConversation!);

      final savedUserMessage = savedMessages[0];
      final savedAssistantMessage = savedMessages[1];
      final assistantId = savedAssistantMessage.id;
      final notifier = ValueNotifier<String>("");

      if (mounted) {
        setState(() {
          _activeMessageIds.add(assistantId);
          _streamingNotifiers[assistantId] = notifier;
          _isSubmitting = false;
          _messages
            ..add(savedUserMessage)
            ..add(savedAssistantMessage);
        });
      }
      _scrollToLatest(force: true);

      final response = StringBuffer();
      var lastPublished = DateTime.fromMillisecondsSinceEpoch(0);
      MessageStatus finalStatus;
      String finalText;
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
        finalStatus = MessageStatus.completed;
        finalText = response.toString();
      } catch (error, stackTrace) {
        debugPrint("Chat response stream failed: $error\n$stackTrace");
        if (!mounted) return;
        finalStatus = MessageStatus.failed;
        finalText = response.isEmpty
            ? "Sorry, I couldn’t finish that response. Please try again."
            : response.toString();
      }
      if (!mounted) return;
      notifier.value = finalText;
      await _completeMessage(assistantId, finalText, finalStatus, notifier);
    } catch (error, stackTrace) {
      debugPrint("Could not save chat message: $error\n$stackTrace");
      if (mounted) {
        if (isNewConversation && _messages.isEmpty) {
          _currentConversation = null;
        }
        _textController.text = prompt;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not save your message. Please try again.")),
        );
      }
    } finally {
      if (mounted && _isSubmitting) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _completeMessage(
    int messageId,
    String text,
    MessageStatus status,
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
        status: status,
        createdAt: oldMessage.createdAt,
      );

      // Save final message text to Isar database
      try {
        await _chatRepository.saveMessageAndTouchConversation(updatedMsg);
      } catch (error, stackTrace) {
        debugPrint("Could not persist completed response: $error\n$stackTrace");
        if (mounted) {
          setState(() {
            _activeMessageIds.remove(messageId);
            _streamingNotifiers.remove(messageId);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("The response could not be saved. It will be recovered when you reopen this chat."),
            ),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => notifier.dispose());
        return;
      }

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
                              fontWeight: FontWeight.normal,
                              fontStyle: FontStyle.italic,
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
