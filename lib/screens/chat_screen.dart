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

  // Extract core model family & size e.g. qwen2.5-0.5b-instruct-q4_k_m -> Qwen2.5-0.5B
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
  if (name.length > 15) {
    name = "${name.substring(0, 14)}…";
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

  // 1. OPEN AI BUD & MODEL SHEET (References @bud&model-selection.png)
  void openDropdownSheet() {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalCtx) {
        return StreamBuilder<AppSettings?>(
          stream: _settingsRepository.watchSettings(),
          builder: (context, snapshot) {
            final settings = snapshot.data;
            final modelPath = settings?.modelPath;
            final cleanModel = formatCleanModelName(modelPath);

            return DefaultTabController(
              length: 2,
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.78,
                maxChildSize: 0.94,
                minChildSize: 0.5,
                builder: (context, scrollController) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // HEADER: AI Bud & Model
                        Row(
                          children: [
                            const Text(
                              "AI Bud & Model",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
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
                                "• Ready • GGUF Edge",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.greenAccent,
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white70, size: 20),
                              onPressed: () => Navigator.pop(modalCtx),
                            ),
                          ],
                        ),

                        Text(
                          "⚡ 1.42 GB LPDDR5X  •  28.4 tok/s  •  Zero Cloud Latency",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade200,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ACTIVE SUMMARY CARD
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2B1D19),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.deepOrange.withOpacity(0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.deepOrange.shade800,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.code_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "${_activeBud?.name ?? 'Coding Bud'} • $cleanModel",
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      "Dart, Rust & reactive low-latency architecture",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white60,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  "• 986 MB",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // TAB BUTTONS
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF251A17),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: TabBar(
                            indicator: BoxDecoration(
                              color: const Color(0xFFFF5722),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            indicatorSize: TabBarIndicatorSize.tab,
                            labelColor: Colors.white,
                            unselectedLabelColor: Colors.white54,
                            labelStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            tabs: const [
                              Tab(text: "🍱 AI Buds 3"),
                              Tab(text: "🧠 GGUF Models 4"),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // TAB CONTENTS
                        Expanded(
                          child: TabBarView(
                            children: [
                              // TAB 1: AI BUDS
                              StreamBuilder<List<Bud>>(
                                stream: _budRepository.watchBuds(),
                                builder: (context, snapshot) {
                                  final buds = snapshot.data ?? [];
                                  return ListView(
                                    controller: scrollController,
                                    children: [
                                      _buildReferenceBudTile(
                                        title: "Coding Bud",
                                        subtitle:
                                            "Temp 0.2 • Flutter, Rust, architecture",
                                        icon: Icons.code_rounded,
                                        isActive: _activeBud?.name == "Coding Bud" || _activeBud == null,
                                        onTap: () {
                                          if (buds.isNotEmpty) _onBudChanged(buds.first);
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      _buildReferenceBudTile(
                                        title: "Teacher Bud",
                                        subtitle:
                                            "Socratic guidance & step-by-step breakdown • Temp 0.5",
                                        icon: Icons.school_rounded,
                                        isActive: _activeBud?.name == "Teacher Bud",
                                        onTap: () {
                                          if (buds.length > 1) _onBudChanged(buds[1]);
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      _buildReferenceBudTile(
                                        title: "Writing Bud",
                                        subtitle:
                                            "Lyrical nuance, creative narratives & prose • Temp 0.85",
                                        icon: Icons.palette_rounded,
                                        isActive: _activeBud?.name == "Writing Bud",
                                        onTap: () {
                                          if (buds.length > 2) _onBudChanged(buds[2]);
                                        },
                                      ),
                                    ],
                                  );
                                },
                              ),

                              // TAB 2: GGUF MODELS
                              FutureBuilder<List<File>>(
                                future: _hfService.getDownloadedGgufFiles(),
                                builder: (context, snapshot) {
                                  final files = snapshot.data ?? [];
                                  if (files.isEmpty) {
                                    return const Center(
                                      child: Text(
                                        "No offline GGUF files found",
                                        style: TextStyle(color: Colors.white54),
                                      ),
                                    );
                                  }
                                  return ListView.builder(
                                    controller: scrollController,
                                    itemCount: files.length,
                                    itemBuilder: (context, index) {
                                      final file = files[index];
                                      final rawName = file.path.split('/').last;
                                      final clean = formatCleanModelName(rawName);
                                      final isSelected = modelPath == file.path;

                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        color: const Color(0xFF251A17),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(
                                            color: isSelected
                                                ? Colors.orange
                                                : Colors.white10,
                                          ),
                                        ),
                                        child: ListTile(
                                          leading: const Icon(Icons.memory_rounded,
                                              color: Colors.orange),
                                          title: Text(clean,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13)),
                                          subtitle: Text(rawName,
                                              style: const TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 10),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                          trailing: isSelected
                                              ? const Chip(
                                                  label: Text("ACTIVE",
                                                      style: TextStyle(
                                                          fontSize: 9,
                                                          color: Colors.white)),
                                                  backgroundColor: Colors.orange,
                                                )
                                              : ElevatedButton(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.deepOrange,
                                                  ),
                                                  onPressed: () async {
                                                    await _settingsRepository
                                                        .updateModelPath(file.path);
                                                    _loadLocalGgufModel(file.path);
                                                  },
                                                  child: const Text("Load",
                                                      style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.white)),
                                                ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        // BOTTOM BUTTONS
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF6D3B),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () => Navigator.pop(modalCtx),
                                icon: const Icon(Icons.check, color: Colors.white, size: 18),
                                label: const Text(
                                  "Apply to Chat",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white24),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
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
  }

  Widget _buildReferenceBudTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF251A17),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? Colors.deepOrange : Colors.white10,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isActive ? Colors.deepOrange : Colors.white12,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive)
              const Row(
                children: [
                  Icon(Icons.check, color: Colors.greenAccent, size: 16),
                  SizedBox(width: 4),
                  Text(
                    "Active",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.greenAccent,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // 2. OPEN VOICE SYNTHESIS & TTS SHEET (References @voice&TTS-selection.png)
  void openTtsVoiceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // HEADER
                  Row(
                    children: [
                      const Text(
                        "Voice Synthesis & TTS",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.green.withOpacity(0.5)),
                        ),
                        child: const Text(
                          "• Offline • ONNX",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),

                  Text(
                    "⚡ Piper / Sherpa-ONNX Engine  •  0ms Cloud Latency",
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade200,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // PLAYING SAMPLE BAR
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2B1D19),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.deepOrange.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                          ),
                          icon: Icon(
                            _isPlayingSample
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
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
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    "22.05 kHz",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.greenAccent,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                '"On-device LLMs run directly in memory ..."',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white54,
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
                  const Row(
                    children: [
                      Text(
                        "INSTALLED LOCAL VOICES",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: Colors.white54,
                        ),
                      ),
                      Spacer(),
                      Text(
                        "4 READY",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent,
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
                      const Text(
                        "Speaking Cadence:",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Wrap(
                        spacing: 6,
                        children: [0.8, 1.0, 1.2, 1.5].map((speed) {
                          final isSel = _speakingCadence == speed;
                          return InkWell(
                            onTap: () {
                              setSheetState(() => _speakingCadence = speed);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? Colors.deepOrange
                                    : const Color(0xFF251A17),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSel
                                      ? Colors.orange
                                      : Colors.white12,
                                ),
                              ),
                              child: Text(
                                "${speed}x",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSel ? Colors.white : Colors.white60,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        "Pitch Modulation:",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        "Flat",
                        style: TextStyle(fontSize: 10, color: Colors.white38),
                      ),
                      Expanded(
                        child: Slider(
                          value: _pitchModulation,
                          min: 0.5,
                          max: 2.0,
                          activeColor: Colors.deepOrange,
                          onChanged: (val) {
                            setSheetState(() => _pitchModulation = val);
                          },
                        ),
                      ),
                      Text(
                        "+${_pitchModulation.toStringAsFixed(1)}",
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // BOTTOM BUTTONS
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6D3B),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(modalCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Default Voice set to $_selectedVoice"),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          icon: const Icon(Icons.check,
                              color: Colors.white, size: 18),
                          label: const Text(
                            "Set Default Voice",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
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
    );
  }

  Widget _buildSoundBar(double height, bool active) {
    return Container(
      width: 3,
      height: active ? height : 6,
      decoration: BoxDecoration(
        color: active ? Colors.orangeAccent : Colors.white24,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF251A17),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? Colors.deepOrange : Colors.white10,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.deepOrange : Colors.white12,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.record_voice_over_rounded,
                  color: Colors.white, size: 18),
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
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.orange.shade200,
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
                            color: Colors.greenAccent,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white38,
                      fontFamily: 'monospace',
                    ),
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
