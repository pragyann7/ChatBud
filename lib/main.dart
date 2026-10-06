import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:chatbud/database/database.dart';
import 'package:chatbud/models/app_settings.dart';
import 'package:chatbud/models/conversation.dart';
import 'package:chatbud/repositories/bud_repository.dart';
import 'package:chatbud/repositories/conversation_repository.dart';
import 'package:chatbud/repositories/message_repository.dart';
import 'package:chatbud/repositories/settings_repository.dart';
import 'package:chatbud/screens/buds_screen.dart';
import 'package:chatbud/screens/chat_screen.dart';
import 'package:chatbud/screens/model_hub_screen.dart';
import 'package:chatbud/services/generation_manager.dart';
import 'package:chatbud/services/huggingface_service.dart';
import 'package:chatbud/services/llama_cpp_service.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppDatabase? database;
  Object? initError;

  try {
    database = AppDatabase();
    await database.initialize();
  } catch (e) {
    initError = e;
  }

  if (initError != null || database == null) {
    runApp(MyApp(initializationError: initError));
    return;
  }

  final conversationRepository = ConversationRepository(database.isar);
  final messageRepository = MessageRepository(database.isar);
  final budRepository = BudRepository(database.isar);
  final settingsRepository = SettingsRepository(database.isar);

  final generationManager = GenerationManager(
    messageRepository: messageRepository,
    settingsRepository: settingsRepository,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
        Provider<ConversationRepository>.value(value: conversationRepository),
        Provider<MessageRepository>.value(value: messageRepository),
        Provider<BudRepository>.value(value: budRepository),
        Provider<SettingsRepository>.value(value: settingsRepository),
        ChangeNotifierProvider<GenerationManager>.value(
          value: generationManager,
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  final Object? initializationError;

  const MyApp({super.key, this.initializationError});

  @override
  Widget build(BuildContext context) {
    final settingsRepository = initializationError == null
        ? context.read<SettingsRepository>()
        : null;
    return StreamBuilder<AppSettings?>(
      stream: settingsRepository?.watchSettings(),
      builder: (context, snapshot) {
        final themeMode = switch (snapshot.data?.theme) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
        return MaterialApp(
          title: "ChatBud",
          themeMode: themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepOrange,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepOrange,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: initializationError != null
              ? Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 48,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "Failed to initialize ChatBud Database",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "$initializationError",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const MyHomePage(),
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Conversation? _activeConversation;
  int _screenKey = -1;

  void _startNewChat() {
    if (_activeConversation == null) return;

    setState(() {
      _activeConversation = null;
      _screenKey = DateTime.now().microsecondsSinceEpoch;
    });
  }

  void _selectConversation(Conversation conversation) {
    context.read<GenerationManager>().markConversationAsRead(conversation.id);
    setState(() {
      _activeConversation = conversation;
      _screenKey = conversation.id;
    });
  }

  void _deleteConversation(Conversation conversation) async {
    final conversationRepo = context.read<ConversationRepository>();
    try {
      await conversationRepo.deleteConversation(conversation.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Failed to delete chat: $e")));
      }
      return;
    }

    if (_activeConversation?.id == conversation.id) {
      setState(() {
        _activeConversation = null;
        _screenKey = DateTime.now().microsecondsSinceEpoch;
      });
    }
  }

  void _onConversationCreated(Conversation conversation) {
    setState(() {
      _activeConversation = conversation;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawerEdgeDragWidth: MediaQuery.of(context).size.width,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _activeConversation?.title ?? "New Chat",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text("Local LLM • Isar DB", style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "New Chat",
            onPressed: _startNewChat,
            icon: const Icon(Icons.edit_note),
          ),
        ],
      ),
      drawer: AppDrawer(
        activeConversation: _activeConversation,
        onNewChat: _startNewChat,
        onSelectConversation: _selectConversation,
        onDeleteConversation: _deleteConversation,
      ),
      body: ChatScreen(
        key: ValueKey(_screenKey),
        conversation: _activeConversation,
        onConversationCreated: _onConversationCreated,
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  final Conversation? activeConversation;
  final VoidCallback onNewChat;
  final ValueChanged<Conversation> onSelectConversation;
  final ValueChanged<Conversation> onDeleteConversation;

  const AppDrawer({
    super.key,
    this.activeConversation,
    required this.onNewChat,
    required this.onSelectConversation,
    required this.onDeleteConversation,
  });

  void _showServerSettingsDialog(BuildContext context) async {
    final settingsRepo = context.read<SettingsRepository>();
    final currentSettings = await settingsRepo.getSettings();
    final hfService = HuggingFaceService();
    final downloadedFiles = await hfService.getDownloadedGgufFiles();

    final controller = TextEditingController(
      text: currentSettings.serverIp ?? '192.168.1.74',
    );
    String selectedEngine = currentSettings.engineType;
    String? selectedModelPath = currentSettings.modelPath;
    String selectedTheme = currentSettings.theme;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final fileName = selectedModelPath != null
                ? selectedModelPath!.split('/').last
                : "No GGUF file selected";

            return AlertDialog(
              title: const Text("AI Engine & Settings"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Appearance:",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'system', label: Text('System')),
                        ButtonSegment(value: 'light', label: Text('Light')),
                        ButtonSegment(value: 'dark', label: Text('Dark')),
                      ],
                      selected: {selectedTheme},
                      onSelectionChanged: (selection) {
                        setDialogState(() => selectedTheme = selection.first);
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Inference Engine:",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'ollama',
                          label: Text('Ollama'),
                          icon: Icon(Icons.wifi_rounded, size: 16),
                        ),
                        ButtonSegment<String>(
                          value: 'llama_cpp',
                          label: Text('llama.cpp'),
                          icon: Icon(Icons.memory_rounded, size: 16),
                        ),
                      ],
                      selected: {selectedEngine},
                      onSelectionChanged: (Set<String> selection) {
                        setDialogState(() {
                          selectedEngine = selection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (selectedEngine == 'ollama') ...[
                      const Text(
                        "Enter local Ollama server IP address:",
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: controller,
                        keyboardType: TextInputType.text,
                        decoration: const InputDecoration(
                          labelText: "Server IP / Host",
                          hintText: "e.g., 192.168.1.74",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ] else ...[
                      const Text(
                        "Select On-Device GGUF Model:",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (downloadedFiles.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value:
                              downloadedFiles.any(
                                (f) => f.path == selectedModelPath,
                              )
                              ? selectedModelPath
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            labelText: "Downloaded Models",
                          ),
                          hint: const Text("Select a downloaded model"),
                          items: downloadedFiles.map((file) {
                            final name = file.path.split('/').last;
                            return DropdownMenuItem<String>(
                              value: file.path,
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() {
                              selectedModelPath = val;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant
                                .withOpacity(0.5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.insert_drive_file_outlined,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    fileName,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () async {
                                      final result = await FilePicker.platform
                                          .pickFiles(type: FileType.any);
                                      if (result != null &&
                                          result.files.isNotEmpty &&
                                          result.files.single.path != null) {
                                        setDialogState(() {
                                          selectedModelPath =
                                              result.files.single.path;
                                        });
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.folder_open_rounded,
                                      size: 14,
                                    ),
                                    label: const Text(
                                      "Browse Storage",
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 6,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const ModelHubScreen(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.cloud_download_rounded,
                                      size: 14,
                                    ),
                                    label: const Text(
                                      "Model Hub",
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newIp = controller.text.trim();
                    if (LlamaCppAiService.loadedModelPath != null &&
                        (selectedEngine != 'llama_cpp' ||
                            LlamaCppAiService.loadedModelPath !=
                                selectedModelPath)) {
                      await LlamaCppAiService.unloadModel();
                    }
                    await settingsRepo.saveSettings(
                      currentSettings.copyWith(
                        theme: selectedTheme,
                        serverIp: newIp.isNotEmpty
                            ? newIp
                            : currentSettings.serverIp,
                        engineType: selectedEngine,
                        modelPath: selectedModelPath,
                      ),
                    );
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                            selectedEngine == 'llama_cpp'
                                ? "On-device llama.cpp mode selected"
                                : "Server IP updated to: $newIp",
                          ),
                        ),
                      );
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showConversationOptions(BuildContext context, Conversation conv) {
    final conversationRepo = context.read<ConversationRepository>();
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                child: Text(
                  conv.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Divider(
                indent: 16,
                endIndent: 16,
                height: 16,
                thickness: 0.8,
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
              ListTile(
                leading: Icon(
                  conv.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                ),
                title: Text(conv.isPinned ? "Unpin chat" : "Pin chat"),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await conversationRepo.togglePinConversation(conv);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Failed to pin chat: $e")),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text("Rename chat"),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameDialog(context, conv);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  "Delete chat",
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onDeleteConversation(conv);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context, Conversation conv) {
    final conversationRepo = context.read<ConversationRepository>();
    final controller = TextEditingController(text: conv.title);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Rename Chat"),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: "Enter chat name"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final newTitle = controller.text.trim();
                if (newTitle.isNotEmpty) {
                  try {
                    await conversationRepo.renameConversation(conv, newTitle);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Failed to rename chat: $e")),
                      );
                    }
                  }
                }
                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final conversationRepo = context.read<ConversationRepository>();
    final genManager = context.watch<GenerationManager>();
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text(
                  "ChatBud",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onNewChat();
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text("Chat"),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.psychology_outlined),
              title: const Text("Buds (AI Personalities)"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BudsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text("Model Hub (Download GGUF)"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ModelHubScreen(),
                  ),
                );
              },
            ),
            Divider(
              indent: 16,
              endIndent: 16,
              height: 24,
              thickness: 0.8,
              color: theme.colorScheme.outlineVariant.withOpacity(0.5),
            ),
            Expanded(
              child: StreamBuilder<List<Conversation>>(
                stream: conversationRepo.watchConversations(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final conversations = snapshot.data!;
                  if (conversations.isEmpty) {
                    return Center(
                      child: Text(
                        "No conversations",
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    );
                  }

                  final pinned = conversations
                      .where((c) => c.isPinned)
                      .toList();
                  final recents = conversations
                      .where((c) => !c.isPinned)
                      .toList();

                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      if (pinned.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 12,
                            right: 12,
                            top: 8,
                            bottom: 4,
                          ),
                          child: Text(
                            "PINNED",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                        ...pinned.map((conv) {
                          final isSelected = activeConversation?.id == conv.id;
                          final isGenerating = genManager.isGenerating(conv.id);
                          final hasUnread = genManager.hasUnreadCompletion(
                            conv.id,
                          );

                          Widget? trailingWidget;
                          if (isGenerating) {
                            trailingWidget = SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            );
                          } else if (hasUnread && !isSelected) {
                            trailingWidget = Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                            );
                          }

                          return ListTile(
                            selected: isSelected,
                            selectedTileColor: theme
                                .colorScheme
                                .primaryContainer
                                .withOpacity(0.4),
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: Icon(
                              Icons.push_pin_rounded,
                              size: 16,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.primary.withOpacity(0.7),
                            ),
                            title: Text(
                              conv.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                            ),
                            trailing: trailingWidget,
                            onTap: () {
                              genManager.markConversationAsRead(conv.id);
                              Navigator.pop(context);
                              onSelectConversation(conv);
                            },
                            onLongPress: () {
                              _showConversationOptions(context, conv);
                            },
                          );
                        }),
                        Divider(
                          indent: 12,
                          endIndent: 12,
                          height: 20,
                          thickness: 0.8,
                          color: theme.colorScheme.outlineVariant.withOpacity(
                            0.5,
                          ),
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 12,
                          right: 12,
                          top: 8,
                          bottom: 4,
                        ),
                        child: Text(
                          "RECENTS",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                      if (recents.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            "No recent chats",
                            style: TextStyle(
                              color: theme.colorScheme.outline,
                              fontSize: 13,
                            ),
                          ),
                        )
                      else
                        ...recents.map((conv) {
                          final isSelected = activeConversation?.id == conv.id;
                          final isGenerating = genManager.isGenerating(conv.id);
                          final hasUnread = genManager.hasUnreadCompletion(
                            conv.id,
                          );

                          Widget? trailingWidget;
                          if (isGenerating) {
                            trailingWidget = SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.primary,
                              ),
                            );
                          } else if (hasUnread && !isSelected) {
                            trailingWidget = Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                            );
                          }

                          return ListTile(
                            selected: isSelected,
                            selectedTileColor: theme
                                .colorScheme
                                .primaryContainer
                                .withOpacity(0.4),
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            title: Text(
                              conv.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                            ),
                            trailing: trailingWidget,
                            onTap: () {
                              genManager.markConversationAsRead(conv.id);
                              Navigator.pop(context);
                              onSelectConversation(conv);
                            },
                            onLongPress: () {
                              _showConversationOptions(context, conv);
                            },
                          );
                        }),
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.only(
                left: 12,
                right: 12,
                top: 8,
                bottom: 22,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        alignment: Alignment.centerLeft,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        onNewChat();
                      },
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text(
                        "New Chat",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: "Server Settings",
                    onPressed: () {
                      Navigator.pop(context);
                      _showServerSettingsDialog(context);
                    },
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
