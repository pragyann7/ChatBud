import 'package:flutter/material.dart';
import 'package:chatbud/screens/chat_screen.dart';

void main() {
  runApp(const MyApp());
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

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "ChatBud",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text("Local chat", style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      drawer: const AppDrawer(),
      body: const ChatScreen(),
    );
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              title: const Text("ChatBud", style: TextStyle(fontSize: 24)),
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
            ListTile(
              title: const Text("Recents"),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
