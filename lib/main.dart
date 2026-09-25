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

  void _onConversationCreated(Conversation conversation) {
    setState(() {
      _activeConversation = conversation;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "ChatBud",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              _activeConversation?.title ?? "New Chat",
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
        onNewChat: _startNewChat,
        onSelectConversation: _selectConversation,
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
  final VoidCallback onNewChat;
  final ValueChanged<Conversation> onSelectConversation;

  const AppDrawer({
    super.key,
    required this.onNewChat,
    required this.onSelectConversation,
  });

  @override
  Widget build(BuildContext context) {
    final repository = Provider.of<ChatRepository>(context, listen: false);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: const Text(
                "ChatBud",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.normal),
              ),
              onTap: () {
                Navigator.pop(context);
                onNewChat();
              },
            ),
            ListTile(
              leading: Icon(Icons.chat_outlined),
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
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Recents",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
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
                    return const ListTile(
                      title: Text(
                        "No recents",
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conv = conversations[index];
                      return ListTile(
                        // leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(
                          conv.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          onSelectConversation(conv);
                        },
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.only(left: 8, right: 8, top: 4, bottom: 22),
              child: Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      leading: const Icon(Icons.add_rounded),
                      title: const Text(
                        "New Chat",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
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
