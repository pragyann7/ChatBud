import 'dart:io';

import 'package:flutter/material.dart';
import 'package:chatbud/models/app_settings.dart';
import 'package:chatbud/models/bud.dart';
import 'package:chatbud/models/conversation.dart';
import 'package:chatbud/models/message.dart';
import 'package:chatbud/repositories/bud_repository.dart';
import 'package:chatbud/repositories/conversation_repository.dart';
import 'package:chatbud/repositories/message_repository.dart';
import 'package:chatbud/repositories/settings_repository.dart';
import 'package:chatbud/screens/model_hub_screen.dart';
import 'package:chatbud/services/generation_manager.dart';
import 'package:chatbud/services/llama_cpp_service.dart';
import 'package:chatbud/widgets/bud_selector.dart';
import 'package:chatbud/widgets/chat_input.dart';
import 'package:chatbud/widgets/message_bubble.dart';
import 'package:provider/provider.dart';

class ChatScreen extends StatefulWidget {
  final Conversation? conversation;
  final ValueChanged<Conversation>? onConversationCreated;

  const ChatScreen({super.key, this.conversation, this.onConversationCreated});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int _messagePageSize = 50;

  late ConversationRepository _conversationRepository;
  late MessageRepository _messageRepository;
  late BudRepository _budRepository;
  late SettingsRepository _settingsRepository;

  Conversation? _currentConversation;
  Bud? _activeBud; // null = No Bud / Raw LLM
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isModelLoading = false;
  int _messageOffset = 0;
  bool _hasOlderMessages = false;
  bool _isLoadingOlderMessages = false;

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToLatest = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoading) {
      _conversationRepository = context.read<ConversationRepository>();
      _messageRepository = context.read<MessageRepository>();
      _budRepository = context.read<BudRepository>();
      _settingsRepository = context.read<SettingsRepository>();
      _loadActiveConversationAndMessages();
    }
  }

  Future<void> _loadActiveConversationAndMessages() async {
    Bud? loadedBud;
    try {
      if (widget.conversation != null) {
        final genManager = context.read<GenerationManager>();
        genManager.markConversationAsRead(widget.conversation!.id);

        final savedMessages = await _messageRepository
            .getMessagesForConversationPaginated(
              widget.conversation!.id,
              limit: _messagePageSize,
              offset: 0,
            );

        final isJobActive = genManager.isGenerating(widget.conversation!.id);

        for (int i = 0; i < savedMessages.length; i++) {
          final msg = savedMessages[i];
          if (msg.status == MessageStatus.pending && !isJobActive) {
            final recovered = Message(
              id: msg.id,
              conversationId: msg.conversationId,
              text: msg.text.isEmpty ? "Response interrupted." : msg.text,
              role: msg.role,
              status: MessageStatus.failed,
              createdAt: msg.createdAt,
              budId: msg.budId,
            );
            savedMessages[i] = recovered;
            await _messageRepository.saveMessageAndTouchConversation(recovered);
          }
        }

        if (widget.conversation!.budId != null) {
          loadedBud = await _budRepository.getBud(widget.conversation!.budId!);
          if (loadedBud == null) {
            final repaired = widget.conversation!.copyWith(clearBudId: true);
            await _conversationRepository.saveConversation(repaired);
          }
        }

        if (mounted) {
          setState(() {
            _currentConversation = widget.conversation;
            _messages = savedMessages;
            _messageOffset = savedMessages.length;
            _hasOlderMessages = savedMessages.length == _messagePageSize;
          });
        }
      }
    } catch (e) {
      debugPrint("Failed to load active conversation messages: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load chat history: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _activeBud = loadedBud;
          _isLoading = false;
        });
      }
    }
  }

  void _onBudChanged(Bud? newBud) async {
    setState(() {
      _activeBud = newBud;
    });

    if (_currentConversation != null) {
      final updatedConv = newBud == null
          ? _currentConversation!.copyWith(
              clearBudId: true,
              updatedAt: DateTime.now(),
            )
          : _currentConversation!.copyWith(
              budId: newBud.id,
              updatedAt: DateTime.now(),
            );
      _currentConversation = updatedConv;
      try {
        await _conversationRepository.saveConversation(updatedConv);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to update Bud setting: $e")),
          );
        }
      }
    }
  }

  void _stopGeneration() {
    if (_currentConversation != null) {
      context.read<GenerationManager>().stopGeneration(
        _currentConversation!.id,
      );
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final shouldShow = _scrollController.position.pixels > 40;
    if (shouldShow != _showScrollToLatest && mounted) {
      setState(() => _showScrollToLatest = shouldShow);
    }
    if (_hasOlderMessages &&
        !_isLoadingOlderMessages &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 120) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    final conversation = _currentConversation;
    if (!mounted ||
        conversation == null ||
        !_hasOlderMessages ||
        _isLoadingOlderMessages) {
      return;
    }

    setState(() => _isLoadingOlderMessages = true);
    try {
      final olderMessages = await _messageRepository
          .getMessagesForConversationPaginated(
            conversation.id,
            limit: _messagePageSize,
            offset: _messageOffset,
          );
      if (!mounted) return;

      final loadedIds = _messages.map((message) => message.id).toSet();
      final uniqueOlderMessages = olderMessages
          .where((message) => !loadedIds.contains(message.id))
          .toList(growable: false);
      setState(() {
        _messages.insertAll(0, uniqueOlderMessages);
        _messageOffset += olderMessages.length;
        _hasOlderMessages = olderMessages.length == _messagePageSize;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load older messages: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingOlderMessages = false);
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

  void _showModelRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("GGUF Model Required"),
          content: const Text(
            "To use 100% offline llama.cpp inference, please download a model from Model Hub or select a local .gguf file.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ModelHubScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.cloud_download_rounded, size: 18),
              label: const Text("Open Model Hub"),
            ),
          ],
        );
      },
    );
  }

  void _loadLocalGgufModel(String modelPath) async {
    setState(() => _isModelLoading = true);
    String? errorMessage;
    try {
      final settings = await _settingsRepository.getSettings();
      await LlamaCppAiService.loadModel(
        modelPath,
        cpuThreads: settings.cpuThreads,
        contextSize: settings.contextSize,
        batchSize: settings.batchSize,
      );
    } catch (error) {
      errorMessage = error.toString();
    }
    if (mounted) {
      setState(() => _isModelLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage ?? "Model loaded into RAM successfully!"),
          backgroundColor: errorMessage == null ? null : Colors.red.shade700,
        ),
      );
    }
  }

  void _unloadLocalGgufModel() async {
    await LlamaCppAiService.unloadModel();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Model unloaded from RAM.")));
    }
  }

  Future<void> _retryMessage(Message failedAssistantMessage) async {
    final genManager = context.read<GenerationManager>();
    if (_currentConversation != null &&
        genManager.isGenerating(_currentConversation!.id)) {
      return;
    }

    final settings = await _settingsRepository.getSettings();
    if (settings.engineType == 'llama_cpp' &&
        (settings.modelPath == null ||
            !File(settings.modelPath!).existsSync())) {
      _showModelRequiredDialog();
      return;
    }

    final index = _messages.indexWhere(
      (m) => m.id == failedAssistantMessage.id,
    );
    if (index == -1) return;

    String prompt = "";
    if (index > 0 && _messages[index - 1].isUser) {
      prompt = _messages[index - 1].text;
    } else {
      final userMsg = _messages.lastWhere(
        (m) => m.isUser,
        orElse: () => Message(
          conversationId: failedAssistantMessage.conversationId,
          text: "",
          role: MessageRole.user,
          createdAt: DateTime.now(),
        ),
      );
      prompt = userMsg.text;
    }

    if (prompt.isEmpty) return;

    final pendingMsg = Message(
      id: failedAssistantMessage.id,
      conversationId: failedAssistantMessage.conversationId,
      text: "",
      role: failedAssistantMessage.role,
      status: MessageStatus.pending,
      createdAt: failedAssistantMessage.createdAt,
      budId: failedAssistantMessage.budId,
    );

    if (mounted) {
      setState(() {
        _messages[index] = pendingMsg;
      });
    }

    await _messageRepository.saveMessageAndTouchConversation(pendingMsg);

    await genManager.startGeneration(
      conversationId: failedAssistantMessage.conversationId,
      assistantMessageId: failedAssistantMessage.id,
      prompt: prompt,
      systemPrompt: _activeBud?.systemPrompt,
      conversationHistory: _messages.sublist(0, index),
      createdAt: failedAssistantMessage.createdAt,
      budId: failedAssistantMessage.budId,
    );
  }

  Future<void> _sendMessage() async {
    final genManager = context.read<GenerationManager>();
    final isCurrentGenerating =
        _currentConversation != null &&
        genManager.isGenerating(_currentConversation!.id);

    if (_isSubmitting || isCurrentGenerating) return;

    final prompt = _textController.text.trim();
    if (prompt.isEmpty) return;

    final settings = await _settingsRepository.getSettings();
    if (settings.engineType == 'llama_cpp' &&
        (settings.modelPath == null ||
            !File(settings.modelPath!).existsSync())) {
      _showModelRequiredDialog();
      return;
    }

    final isNewConversation = _currentConversation == null;
    _isSubmitting = true;
    setState(() {});
    _textController.clear();
    final now = DateTime.now();

    try {
      if (_currentConversation == null) {
        final title = prompt.length > 25
            ? "${prompt.substring(0, 25)}..."
            : prompt;
        _currentConversation = Conversation(
          title: title,
          createdAt: now,
          updatedAt: now,
          budId: _activeBud?.id,
        );
      } else {
        _currentConversation = _activeBud == null
            ? _currentConversation!.copyWith(clearBudId: true, updatedAt: now)
            : _currentConversation!.copyWith(
                budId: _activeBud!.id,
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
        budId: _activeBud?.id,
      );

      final savedMessages = await _messageRepository
          .saveMessagePairAndTouchConversation(
            conversation: _currentConversation!,
            userMessage: userMessage,
            assistantMessage: assistantMessage,
          );

      if (savedMessages == null || savedMessages.length < 2) {
        return;
      }

      widget.onConversationCreated?.call(_currentConversation!);

      final savedUserMessage = savedMessages[0];
      final savedAssistantMessage = savedMessages[1];

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _messages
            ..add(savedUserMessage)
            ..add(savedAssistantMessage);
        });
      }
      _scrollToLatest(force: true);

      await genManager.startGeneration(
        conversationId: _currentConversation!.id,
        assistantMessageId: savedAssistantMessage.id,
        prompt: prompt,
        systemPrompt: _activeBud?.systemPrompt,
        conversationHistory: _messages,
        createdAt: savedAssistantMessage.createdAt,
        budId: savedAssistantMessage.budId,
      );
    } catch (error, stackTrace) {
      debugPrint("Could not save chat message: $error\n$stackTrace");
      if (mounted) {
        if (isNewConversation && _messages.isEmpty) {
          _currentConversation = null;
        }
        _textController.text = prompt;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Could not save your message. Please try again."),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _checkAndSyncCompletedBackgroundJobs(GenerationManager genManager) {
    if (_currentConversation == null || _messages.isEmpty) return;

    final conversationId = _currentConversation!.id;
    final isJobRunning = genManager.isGenerating(conversationId);

    if (!isJobRunning) {
      bool needsRefresh = false;
      for (final msg in _messages) {
        if (msg.status == MessageStatus.pending) {
          needsRefresh = true;
          break;
        }
      }

      if (needsRefresh) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || _currentConversation == null) return;
          final refreshLimit = _messageOffset > _messagePageSize
              ? _messageOffset
              : _messagePageSize;
          final freshMessages = await _messageRepository
              .getMessagesForConversationPaginated(
                _currentConversation!.id,
                limit: refreshLimit,
                offset: 0,
              );
          if (mounted) {
            setState(() {
              _messages = freshMessages;
              _messageOffset = freshMessages.length;
              _hasOlderMessages = freshMessages.length == refreshLimit;
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final genManager = context.watch<GenerationManager>();
    final isGeneratingThisChat =
        _currentConversation != null &&
        genManager.isGenerating(_currentConversation!.id);
    final isInputGenerating = isGeneratingThisChat || _isSubmitting;

    _checkAndSyncCompletedBackgroundJobs(genManager);

    return Column(
      children: [
        // Bud Selector Header Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          alignment: Alignment.centerLeft,
          color: Theme.of(context).colorScheme.surface,
          child: Row(
            children: [
              BudSelectorChip(
                activeBud: _activeBud,
                onBudSelected: _onBudChanged,
              ),
              const Spacer(),
            ],
          ),
        ),
        // llama.cpp On-Device Model Status Bar
        StreamBuilder<AppSettings?>(
          stream: _settingsRepository.watchSettings(),
          builder: (context, snapshot) {
            final settings = snapshot.data;
            if (settings?.engineType != 'llama_cpp') {
              return const SizedBox.shrink();
            }

            final modelPath = settings?.modelPath;
            final isLoaded = LlamaCppAiService.isModelLoaded;
            final fileName = modelPath != null
                ? modelPath.split('/').last
                : null;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withOpacity(0.5),
              child: Row(
                children: [
                  Icon(
                    isLoaded ? Icons.bolt_rounded : Icons.memory_rounded,
                    size: 16,
                    color: isLoaded
                        ? Colors.green
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isLoaded
                          ? "Loaded: ${fileName ?? 'Model'} (RAM Active)"
                          : (fileName != null
                                ? "Model Ready: $fileName"
                                : "No Model Loaded"),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isLoaded
                            ? Colors.green
                            : Theme.of(context).colorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_isModelLoading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (isLoaded)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _unloadLocalGgufModel,
                      child: const Text(
                        "Unload RAM",
                        style: TextStyle(fontSize: 11),
                      ),
                    )
                  else if (fileName != null)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _loadLocalGgufModel(modelPath!),
                      icon: const Icon(Icons.bolt_rounded, size: 14),
                      label: const Text(
                        "Load Model",
                        style: TextStyle(fontSize: 11),
                      ),
                    )
                  else
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _showModelRequiredDialog,
                      icon: const Icon(Icons.cloud_download_rounded, size: 14),
                      label: const Text(
                        "Model Hub",
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const Divider(height: 1),
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
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Active Mode: ${_activeBud?.name ?? 'No Bud (Raw LLM)'}",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ModelHubScreen(),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.cloud_download_rounded,
                          size: 18,
                        ),
                        label: const Text("Model Hub (Download GGUF)"),
                      ),
                    ],
                  ),
                )
              else
                ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount:
                      _messages.length +
                      (_hasOlderMessages || _isLoadingOlderMessages ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _messages.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final message = _messages[_messages.length - 1 - index];
                    final isLatestMessage =
                        _messages.isNotEmpty && _messages.last.id == message.id;

                    final activeNotifier = _currentConversation != null
                        ? genManager.getNotifier(
                            _currentConversation!.id,
                            message.id,
                          )
                        : null;

                    return MessageBubble(
                      key: ValueKey(message.id),
                      message: message,
                      textListenable: activeNotifier,
                      isLatest: isLatestMessage,
                      onRetry: () => _retryMessage(message),
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
          isGenerating: isInputGenerating,
          onSend: _sendMessage,
          onStop: _stopGeneration,
          onAddAttachment: () {},
        ),
      ],
    );
  }
}
