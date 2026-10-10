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
import 'package:chatbud/screens/buds_screen.dart';
import 'package:chatbud/screens/models_screen.dart';
import 'package:chatbud/screens/settings_screen.dart';
import 'package:chatbud/services/generation_manager.dart';
import 'package:chatbud/services/huggingface_service.dart';
import 'package:chatbud/services/llama_cpp_service.dart';
import 'package:chatbud/widgets/chat_input.dart';
import 'package:chatbud/widgets/message_bubble.dart';
import 'package:provider/provider.dart';

// HELPER FUNCTION TO TRIM LONG MODEL NAMES
String formatCleanModelName(String? raw) {
  if (raw == null || raw.trim().isEmpty) return "Qwen2.5-1.5B";
  String name = raw.split('/').last.split('\\').last;
  name = name.replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '');

  final qwenMatch = RegExp(r'(qwen2?\.?5?-[0-9\.]+[bm])', caseSensitive: false)
      .firstMatch(name);
  if (qwenMatch != null) {
    String m = qwenMatch.group(1)!;
    return m.substring(0, 1).toUpperCase() + m.substring(1);
  }

  final llamaMatch = RegExp(r'(llama-?[0-9\.]*-?[0-9\.]+[bm])', caseSensitive: false)
      .firstMatch(name);
  if (llamaMatch != null) {
    String m = llamaMatch.group(1)!;
    return m.substring(0, 1).toUpperCase() + m.substring(1);
  }

  name = name.replaceAll(
      RegExp(r'(-instruct|-q\d+_\w+|_q\d+_\w+)', caseSensitive: false), '');
  if (name.length > 13) {
    name = "${name.substring(0, 12)}…";
  }
  return name;
}

class ChatScreen extends StatefulWidget {
  final Conversation? conversation;
  final ValueChanged<Conversation>? onConversationCreated;

  const ChatScreen({
    super.key,
    this.conversation,
    this.onConversationCreated,
  });

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  static const int _pageSize = 50;

  late ConversationRepository _conversationRepository;
  late MessageRepository _messageRepository;
  late BudRepository _budRepository;
  late SettingsRepository _settingsRepository;

  Conversation? _currentConversation;
  Bud? _activeBud; // null = No Bud / Raw LLM
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isLoadingOlderMessages = false;
  bool _hasOlderMessages = true;
  bool _isSubmitting = false;
  bool _isModelLoading = false;

  // TTS Voice State
  String _selectedVoice = 'Nova';
  double _speakingCadence = 1.0;
  double _pitchModulation = 1.2;
  bool _isPlayingSample = false;

  final TextEditingController _textController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToLatest = false;

  final HuggingFaceService _hfService = HuggingFaceService();

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

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.conversation?.id != oldWidget.conversation?.id) {
      setState(() {
        _currentConversation = widget.conversation;
        _messages = [];
        _isLoading = true;
      });
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
              limit: _pageSize,
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
            await _messageRepository.saveMessageAndTouchConversation(
              recovered,
            );
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
            _hasOlderMessages = savedMessages.length >= _pageSize;
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

  Future<void> _loadOlderMessages() async {
    final conversation = _currentConversation;
    if (conversation == null ||
        _isLoadingOlderMessages ||
        !_hasOlderMessages) {
      return;
    }

    setState(() {
      _isLoadingOlderMessages = true;
    });

    try {
      final olderMessages = await _messageRepository
          .getMessagesForConversationPaginated(
            conversation.id,
            limit: _pageSize,
            offset: _messages.length,
          );

      if (!mounted) return;

      setState(() {
        if (olderMessages.isEmpty) {
          _hasOlderMessages = false;
        } else {
          _messages = [...olderMessages, ..._messages];
          if (olderMessages.length < _pageSize) {
            _hasOlderMessages = false;
          }
        }
      });
    } catch (e) {
      debugPrint("Failed to load older messages: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingOlderMessages = false;
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
            "To use 100% offline llama.cpp inference, please download a model from Models or select a local .gguf file.",
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
                    builder: (context) => const ModelsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.cloud_download_rounded, size: 18),
              label: const Text("Open Models"),
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
      await LlamaCppAiService.loadModel(modelPath);
    } catch (error) {
      errorMessage = "$error";
    } finally {
      if (mounted) {
        setState(() => _isModelLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage ?? "Model loaded into RAM successfully!",
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _unloadLocalGgufModel() async {
    await LlamaCppAiService.unloadModel();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Model unloaded from RAM."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  IconData _getBudIconData(String? iconName) {
    if (iconName == null) return Icons.smart_toy_rounded;
    switch (iconName) {
      case 'code':
        return Icons.code_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'palette':
        return Icons.palette_rounded;
      case 'psychology':
        return Icons.psychology_rounded;
      case 'terminal':
        return Icons.terminal_rounded;
      case 'smart_toy':
      default:
        return Icons.smart_toy_rounded;
    }
  }

  // 1. OPEN AI BUD & MODEL SHEET (Dynamic Data + App Color Palette Match)
  void openDropdownSheet() {
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
    _inputFocusNode.unfocus();

    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return StreamBuilder<AppSettings?>(
          stream: _settingsRepository.watchSettings(),
          builder: (context, snapshot) {
            final settings = snapshot.data;
            final modelPath = settings?.modelPath;

            return StreamBuilder<List<Bud>>(
              stream: _budRepository.watchBuds(),
              builder: (context, budSnapshot) {
                final buds = budSnapshot.data ?? [];

                return FutureBuilder<List<File>>(
                  future: _hfService.getDownloadedGgufFiles(),
                  builder: (context, modelSnapshot) {
                    final files = modelSnapshot.data ?? [];

                    return DefaultTabController(
                      length: 2,
                      child: DraggableScrollableSheet(
                        expand: false,
                        initialChildSize: 0.65,
                        maxChildSize: 0.90,
                        minChildSize: 0.45,
                        builder: (context, scrollController) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Drag handle
                                Center(
                                  child: Container(
                                    width: 36,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.outlineVariant,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // TAB BUTTONS
                                Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: TabBar(
                                    indicator: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: theme.colorScheme.primary
                                            .withOpacity(0.3),
                                      ),
                                    ),
                                    indicatorSize: TabBarIndicatorSize.tab,
                                    labelColor: theme.colorScheme.primary,
                                    unselectedLabelColor:
                                        theme.colorScheme.onSurfaceVariant,
                                    labelStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    tabs: [
                                      Tab(text: "🍱 AI Buds (${buds.length + 1})"),
                                      Tab(text: "🧠 GGUF Models (${files.length})"),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // TAB CONTENTS (ACTUAL BUDS & MODELS)
                                Expanded(
                                  child: TabBarView(
                                    children: [
                                      // TAB 1: ACTUAL AVAILABLE BUDS
                                      ListView(
                                        controller: scrollController,
                                        children: [
                                          _buildDynamicBudTile(
                                            title: "Raw LLM (No Persona)",
                                            subtitle:
                                                "Direct model completion without custom system prompt",
                                            icon: Icons.memory_rounded,
                                            isActive: _activeBud == null,
                                            onTap: () {
                                              _onBudChanged(null);
                                              Navigator.pop(modalCtx);
                                            },
                                          ),
                                          const SizedBox(height: 8),
                                          ...buds.map((bud) {
                                            final isActive =
                                                _activeBud?.id == bud.id;
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: _buildDynamicBudTile(
                                                title: bud.name,
                                                subtitle: bud.systemPrompt,
                                                icon: _getBudIconData(
                                                    bud.iconName),
                                                isActive: isActive,
                                                onTap: () {
                                                  _onBudChanged(bud);
                                                  Navigator.pop(modalCtx);
                                                },
                                              ),
                                            );
                                          }),
                                        ],
                                      ),

                                      // TAB 2: ACTUAL AVAILABLE GGUF MODELS
                                      files.isEmpty
                                          ? Center(
                                              child: Text(
                                                "No downloaded GGUF files found.",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: theme.colorScheme.outline,
                                                ),
                                              ),
                                            )
                                          : ListView.builder(
                                              controller: scrollController,
                                              itemCount: files.length,
                                              itemBuilder: (context, index) {
                                                final file = files[index];
                                                final rawName =
                                                    file.path.split('/').last;
                                                final clean = formatCleanModelName(
                                                    file.path);
                                                final isSelected =
                                                    modelPath == file.path;

                                                return Card(
                                                  margin: const EdgeInsets.only(
                                                      bottom: 8),
                                                  color: isSelected
                                                      ? theme.colorScheme.primaryContainer
                                                          .withOpacity(0.35)
                                                      : theme.colorScheme
                                                          .surfaceContainerLow,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(12),
                                                    side: BorderSide(
                                                      color: isSelected
                                                          ? theme.colorScheme.primary
                                                          : theme.colorScheme.outlineVariant
                                                              .withOpacity(0.3),
                                                      width: isSelected ? 1.5 : 1,
                                                    ),
                                                  ),
                                                  child: ListTile(
                                                    dense: true,
                                                    leading: Icon(
                                                      Icons.memory_rounded,
                                                      color: isSelected
                                                          ? theme.colorScheme.primary
                                                          : theme.colorScheme.onSurfaceVariant,
                                                    ),
                                                    title: Text(
                                                      clean,
                                                      style: TextStyle(
                                                        color: theme.colorScheme.onSurface,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                    subtitle: Text(
                                                      rawName,
                                                      style: TextStyle(
                                                        color: theme.colorScheme.onSurfaceVariant,
                                                        fontSize: 10,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    trailing: isSelected
                                                        ? Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal: 8,
                                                                    vertical: 3),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: Colors.green
                                                                  .withOpacity(0.2),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(6),
                                                              border: Border.all(
                                                                  color: Colors
                                                                      .green),
                                                            ),
                                                            child: const Text(
                                                              "ACTIVE",
                                                              style: TextStyle(
                                                                fontSize: 9,
                                                                fontWeight:
                                                                    FontWeight.bold,
                                                                color: Colors
                                                                    .green,
                                                              ),
                                                            ),
                                                          )
                                                        : ElevatedButton(
                                                            style:
                                                                ElevatedButton.styleFrom(
                                                              padding: const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal: 10,
                                                                  vertical: 2),
                                                              minimumSize:
                                                                  Size.zero,
                                                              tapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap,
                                                            ),
                                                            onPressed: () async {
                                                              if (LlamaCppAiService
                                                                          .loadedModelPath !=
                                                                      null &&
                                                                  LlamaCppAiService
                                                                          .loadedModelPath !=
                                                                      file.path) {
                                                                await LlamaCppAiService
                                                                    .unloadModel();
                                                              }
                                                              await _settingsRepository
                                                                  .updateModelPath(
                                                                      file.path);
                                                              _loadLocalGgufModel(
                                                                  file.path);
                                                              setState(() {});
                                                            },
                                                            child: const Text(
                                                              "Use & Load",
                                                              style: TextStyle(
                                                                  fontSize: 10),
                                                            ),
                                                          ),
                                                  ),
                                                );
                                              },
                                            ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 12),

                                // BOTTOM ACTION BUTTONS
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => Navigator.pop(modalCtx),
                                        icon: const Icon(Icons.check, size: 18),
                                        label: const Text(
                                          "Apply to Chat",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          Navigator.pop(modalCtx);
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const ModelsScreen(),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.download_rounded,
                                            size: 18),
                                        label: const Text("Manage in Hub"),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    ).then((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      if (mounted) {
        FocusScope.of(context).unfocus();
        _inputFocusNode.unfocus();
      }
    });
  }

  Widget _buildDynamicBudTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withOpacity(0.35)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withOpacity(0.4),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isActive
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.check_circle_rounded,
                color: theme.colorScheme.primary,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 2. OPEN VOICE SYNTHESIS & TTS SHEET (Matched Color Palette)
  void openTtsVoiceSheet() {
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
    _inputFocusNode.unfocus();

    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // HEADER
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          "Voice Synthesis & TTS",
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.green.withOpacity(0.5)),
                        ),
                        child: const Text(
                          "• Offline • ONNX",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),

                  Text(
                    "⚡ Piper / Sherpa-ONNX Engine  •  0ms Cloud Latency",
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // PLAYING SAMPLE BAR
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant
                            .withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                          ),
                          icon: Icon(
                            _isPlayingSample
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: theme.colorScheme.onPrimary,
                          ),
                          onPressed: () {
                            setSheetState(() {
                              _isPlayingSample = !_isPlayingSample;
                            });
                          },
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    "Playing $_selectedVoice Sample",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    "22.05 kHz",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '"On-device LLMs run directly in memory ..."',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // SOUND BARS EQUALIZER
                        Row(
                          children: [
                            _buildSoundBar(18, _isPlayingSample),
                            const SizedBox(width: 2),
                            _buildSoundBar(24, _isPlayingSample),
                            const SizedBox(width: 2),
                            _buildSoundBar(14, _isPlayingSample),
                            const SizedBox(width: 2),
                            _buildSoundBar(20, _isPlayingSample),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        "INSTALLED LOCAL VOICES",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        "4 READY",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // VOICES LIST
                  _buildVoiceTile(
                    name: "Nova",
                    tag: "Recommended",
                    desc: "Warm & Articulate • Tuned for code explanation",
                    meta: "EN-US  •  Piper 42 MB  •  18ms Latency",
                    isSelected: _selectedVoice == "Nova",
                    onTap: () => setSheetState(() => _selectedVoice = "Nova"),
                  ),
                  const SizedBox(height: 8),
                  _buildVoiceTile(
                    name: "Atlas",
                    tag: "Deep Pitch",
                    desc: "Crisp & Technical • Low pitch, clear cadence",
                    meta: "EN-US  •  Sherpa 38 MB  •  15ms Latency",
                    isSelected: _selectedVoice == "Atlas",
                    onTap: () => setSheetState(() => _selectedVoice = "Atlas"),
                  ),

                  const SizedBox(height: 16),

                  // CADENCE & PITCH CONTROLS
                  Row(
                    children: [
                      Text(
                        "Speaking Cadence:",
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [0.8, 1.0, 1.2, 1.5].map((speed) {
                              final isSel = _speakingCadence == speed;
                              return Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: InkWell(
                                  onTap: () {
                                    setSheetState(
                                        () => _speakingCadence = speed);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? theme.colorScheme.primaryContainer
                                          : theme.colorScheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSel
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.outlineVariant
                                                .withOpacity(0.4),
                                      ),
                                    ),
                                    child: Text(
                                      "${speed}x",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isSel
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        "Pitch Modulation:",
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "Flat",
                        style: TextStyle(
                            fontSize: 10, color: theme.colorScheme.outline),
                      ),
                      Expanded(
                        child: Slider(
                          value: _pitchModulation,
                          min: 0.5,
                          max: 2.0,
                          activeColor: theme.colorScheme.primary,
                          onChanged: (val) {
                            setSheetState(() => _pitchModulation = val);
                          },
                        ),
                      ),
                      Text(
                        "+${_pitchModulation.toStringAsFixed(1)}",
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // BOTTOM BUTTONS
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(modalCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text("Default Voice set to $_selectedVoice"),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text(
                            "Set Default Voice",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(modalCtx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ModelsScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text("Download Voices"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      if (mounted) {
        FocusScope.of(context).unfocus();
        _inputFocusNode.unfocus();
      }
    });
  }

  Widget _buildSoundBar(double height, bool active) {
    final theme = Theme.of(context);
    return Container(
      width: 3,
      height: active ? height : 6,
      decoration: BoxDecoration(
        color: active
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildVoiceTile({
    required String name,
    required String tag,
    required String desc,
    required String meta,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withOpacity(0.35)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withOpacity(0.4),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.record_voice_over_rounded,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 9,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (isSelected)
                        const Text(
                          "✓ Selected",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.outline,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
    final isCurrentGenerating = _currentConversation != null &&
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
        final title =
            prompt.length > 25 ? "${prompt.substring(0, 25)}..." : prompt;
        _currentConversation = Conversation(
          title: title,
          createdAt: now,
          updatedAt: now,
          budId: _activeBud?.id,
        );
      } else {
        _currentConversation = _activeBud == null
            ? _currentConversation!.copyWith(
                clearBudId: true,
                updatedAt: now,
              )
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

      final savedMessages =
          await _messageRepository.saveMessagePairAndTouchConversation(
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
          final freshMessages = await _messageRepository
              .getMessagesForConversationPaginated(
                _currentConversation!.id,
                limit: _pageSize,
                offset: 0,
              );
          if (mounted) {
            setState(() {
              _messages = freshMessages;
              _hasOlderMessages = freshMessages.length >= _pageSize;
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
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final genManager = context.watch<GenerationManager>();
    final isGeneratingThisChat = _currentConversation != null &&
        genManager.isGenerating(_currentConversation!.id);
    final isInputGenerating = isGeneratingThisChat || _isSubmitting;

    _checkAndSyncCompletedBackgroundJobs(genManager);

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              if (_messages.isEmpty)
                _buildEmptyStateView(context)
              else
                ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount:
                      _messages.length + (_isLoadingOlderMessages ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isLoadingOlderMessages &&
                        index == _messages.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }

                    final message = _messages[_messages.length - 1 - index];
                    final isLatestMessage = _messages.isNotEmpty &&
                        _messages.last.id == message.id;

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
          focusNode: _inputFocusNode,
          isGenerating: isInputGenerating,
          onSend: _sendMessage,
          onStop: _stopGeneration,
          onAddAttachment: () {},
        ),
      ],
    );
  }

  // MODERN EMPTY CHAT HERO STATE
  Widget _buildEmptyStateView(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "ChatBud • Offline AI",
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Private • On-Device • Uncensored Intelligence",
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: openDropdownSheet,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Chat & Model Settings",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      size: 18,
                      color: theme.colorScheme.outline,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
