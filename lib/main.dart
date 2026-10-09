import 'package:flutter/material.dart';
import 'package:chatbud/database/database.dart';
import 'package:chatbud/models/app_settings.dart';
import 'package:chatbud/models/conversation.dart';
import 'package:chatbud/repositories/bud_repository.dart';
import 'package:chatbud/repositories/conversation_repository.dart';
import 'package:chatbud/repositories/message_repository.dart';
import 'package:chatbud/repositories/settings_repository.dart';
import 'package:chatbud/screens/buds_screen.dart';
import 'package:chatbud/screens/chat_screen.dart';
import 'package:chatbud/screens/models_screen.dart';
import 'package:chatbud/screens/settings_screen.dart';
import 'package:chatbud/services/generation_manager.dart';
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
            value: generationManager),
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
    final settingsRepo = context.read<SettingsRepository?>();

    if (settingsRepo != null) {
      return StreamBuilder(
        stream: settingsRepo.watchSettings(),
        builder: (context, snapshot) {
          final themeStr = snapshot.data?.theme ?? 'system';
          ThemeMode themeMode = ThemeMode.system;
          if (themeStr == 'light') themeMode = ThemeMode.light;
          if (themeStr == 'dark') themeMode = ThemeMode.dark;

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
                                  fontSize: 12, color: Colors.grey),
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

    return MaterialApp(
      title: "ChatBud",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final GlobalKey<ChatScreenState> _chatScreenKey =
      GlobalKey<ChatScreenState>();

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete chat: $e")),
        );
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
    final settingsRepo = context.watch<SettingsRepository?>();

    return Scaffold(
      drawerEdgeDragWidth: MediaQuery.of(context).size.width,
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: StreamBuilder<AppSettings?>(
          stream: settingsRepo?.watchSettings(),
          builder: (context, snapshot) {
            final settings = snapshot.data;
            final isLlama = settings?.engineType == 'llama_cpp';
            final rawPath = settings?.modelPath;
            final cleanModelName = formatCleanModelName(rawPath);

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _chatScreenKey.currentState?.openDropdownSheet();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _activeConversation?.title ?? "New Chat",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.4),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isLlama
                                ? "• $cleanModelName • RAM Active"
                                : "• Ollama Network",
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.bolt_rounded,
                            size: 12,
                            color: Colors.green,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          // SPEAKER ICON -> OPENS VOICE SYNTHESIS & TTS SHEET
          IconButton(
            tooltip: "Voice Synthesis & TTS",
            icon: const Icon(Icons.volume_up_outlined),
            onPressed: () {
              _chatScreenKey.currentState?.openTtsVoiceSheet();
            },
          ),
          // NEW CHAT ICON
          IconButton(
            tooltip: "New Chat",
            onPressed: _startNewChat,
            icon: const Icon(Icons.edit_note),
          ),
          // 3-DOT SETTING ICON -> OPENS AI BUD & MODEL SHEET
          IconButton(
            tooltip: "Chat Setting",
            onPressed: () {
              _chatScreenKey.currentState?.openDropdownSheet();
            },
            icon: const Icon(Icons.more_vert_rounded),
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
        key: _screenKey == -1
            ? _chatScreenKey
            : ValueKey("chat_$_screenKey"),
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

  @override
  Widget build(BuildContext context) {
    final conversationRepo = context.read<ConversationRepository>();

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const CircleAvatar(
                    child: Icon(Icons.chat_bubble_outline_rounded),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "ChatBud",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded),
                    tooltip: "New Chat",
                    onPressed: () {
                      Navigator.pop(context);
                      onNewChat();
                    },
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text("Chat"),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text("Settings"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SettingsScreen()),
                );
              },
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
              leading: const Icon(Icons.memory_rounded),
              title: const Text("Models"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ModelsScreen()),
                );
              },
            ),
            const Divider(
              indent: 16,
              endIndent: 16,
              height: 24,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Recent Chats",
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
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
                    return const Center(
                      child: Text(
                        "No chat history yet",
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      final isSelected =
                          activeConversation?.id == conversation.id;

                      return ListTile(
                        selected: isSelected,
                        title: Text(
                          conversation.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: Colors.grey,
                          ),
                          onPressed: () {
                            onDeleteConversation(conversation);
                          },
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          onSelectConversation(conversation);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
