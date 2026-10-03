import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatbud/main.dart';
import 'package:chatbud/models/bud.dart';
import 'package:chatbud/models/conversation.dart';
import 'package:chatbud/models/message.dart';
import 'package:chatbud/repositories/bud_repository.dart';
import 'package:chatbud/repositories/conversation_repository.dart';
import 'package:chatbud/repositories/message_repository.dart';
import 'package:chatbud/repositories/settings_repository.dart';
import 'package:chatbud/services/generation_manager.dart';
import 'package:provider/provider.dart';

class _FakeConversationRepository implements ConversationRepository {
  @override
  Stream<List<Conversation>> watchConversations() => Stream.value([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMessageRepository implements MessageRepository {
  @override
  Stream<List<Message>> watchMessagesForConversation(int conversationId) => Stream.value([]);

  @override
  Future<List<Message>> getMessagesForConversation(int conversationId) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBudRepository implements BudRepository {
  @override
  Stream<List<Bud>> watchBuds() => Stream.value([]);

  @override
  Future<Bud?> getBud(int id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGenerationManager extends ChangeNotifier implements GenerationManager {
  @override
  bool isGenerating(int conversationId) => false;

  @override
  bool get isAnyGenerating => false;

  @override
  ValueNotifier<String>? getNotifier(int conversationId, int assistantMessageId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ConversationRepository>.value(
            value: _FakeConversationRepository(),
          ),
          Provider<MessageRepository>.value(
            value: _FakeMessageRepository(),
          ),
          Provider<BudRepository>.value(
            value: _FakeBudRepository(),
          ),
          Provider<SettingsRepository>.value(
            value: _FakeSettingsRepository(),
          ),
          ChangeNotifierProvider<GenerationManager>.value(
            value: _FakeGenerationManager(),
          ),
        ],
        child: const MyApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('New Chat'), findsWidgets);
  });
}
