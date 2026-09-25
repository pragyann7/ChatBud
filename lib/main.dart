import 'package:flutter/material.dart';
import 'package:chatbud/database/database.dart';
import 'package:chatbud/models/conversation.dart';
import 'package:chatbud/repositories/chat_repository.dart';
import 'package:chatbud/screens/chat_screen.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  await database.initialize();

  final repository = ChatRepository(database.isar);

  runApp(
    MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
        Provider<ChatRepository>.value(value: repository),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
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
    setState(() {
      _activeConversation = conversation;
      _screenKey = conversation.id;
    });
  }

  void _deleteConversation(Conversation conversation) async {
    final repository = Provider.of<ChatRepository>(context, listen: false);
    await repository.deleteConversation(conversation.id);

    // If the active conversation was deleted, reset to a new chat screen
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              "Model Name",
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "New Chat",
            onPressed: _startNewChat,
            icon: Image.asset("assets/new_chat.png", width: 24, height: 24),
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

  void _showConversationOptions(BuildContext context, Conversation conv) {
    final repository = Provider.of<ChatRepository>(context, listen: false);
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
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
                onTap: () {
                  Navigator.pop(context);
                  repository.togglePinConversation(conv);
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
                leading: Icon(Icons.delete_outline,
                    color: theme.colorScheme.error),
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
    final repository = Provider.of<ChatRepository>(context, listen: false);
    final controller = TextEditingController(text: conv.title);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Rename Chat"),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: "Enter chat name",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final newTitle = controller.text.trim();
                if (newTitle.isNotEmpty) {
                  repository.renameConversation(conv, newTitle);
                }
                Navigator.pop(context);
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
    final repository = Provider.of<ChatRepository>(context, listen: false);
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
              leading: Image.asset("assets/buds.png", width: 24, height: 24),
              title: const Text("Buds"),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: Image.asset("assets/models.png", width: 24, height: 24),
              title: const Text("Models"),
              onTap: () => Navigator.pop(context),
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
                stream: repository.watchConversations(),
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

                  final pinned =
                      conversations.where((c) => c.isPinned).toList();
                  final recents =
                      conversations.where((c) => !c.isPinned).toList();

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
                        ...pinned.map(
                          (conv) {
                            final isSelected =
                                activeConversation?.id == conv.id;
                            return ListTile(
                              selected: isSelected,
                              selectedTileColor: theme
                                  .colorScheme.primaryContainer
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
                                    : theme.colorScheme.primary
                                        .withOpacity(0.7),
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
                              onTap: () {
                                Navigator.pop(context);
                                onSelectConversation(conv);
                              },
                              onLongPress: () {
                                _showConversationOptions(context, conv);
                              },
                            );
                          },
                        ),
                        Divider(
                          indent: 12,
                          endIndent: 12,
                          height: 20,
                          thickness: 0.8,
                          color:
                              theme.colorScheme.outlineVariant.withOpacity(0.5),
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
                        ...recents.map(
                          (conv) {
                            final isSelected =
                                activeConversation?.id == conv.id;
                            return ListTile(
                              selected: isSelected,
                              selectedTileColor: theme
                                  .colorScheme.primaryContainer
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
                              onTap: () {
                                Navigator.pop(context);
                                onSelectConversation(conv);
                              },
                              onLongPress: () {
                                _showConversationOptions(context, conv);
                              },
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
            Divider(
              indent: 16,
              endIndent: 16,
              height: 1,
              thickness: 0.8,
              color: theme.colorScheme.outlineVariant.withOpacity(0.5),
            ),
            Container(
              padding: const EdgeInsets.only(
                left: 8,
                right: 8,
                top: 4,
                bottom: 22,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      leading: const Icon(Icons.add_rounded, size: 20),
                      title: const Text(
                        "New Chat",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        onNewChat();
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: "Settings",
                    onPressed: () {
                      Navigator.pop(context);
                      // TODO: Navigate to Settings screen
                    },
                    icon: const Icon(Icons.settings),
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
