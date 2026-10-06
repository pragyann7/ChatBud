import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:chatbud/models/app_settings.dart';
import 'package:chatbud/models/bud.dart';
import 'package:chatbud/models/conversation.dart';
import 'package:chatbud/models/message.dart';
import 'package:chatbud/repositories/bud_repository.dart';
import 'package:chatbud/repositories/conversation_repository.dart';
import 'package:chatbud/repositories/message_repository.dart';
import 'package:chatbud/repositories/settings_repository.dart';

void main() {
  late Isar isar;
  late ConversationRepository conversationRepo;
  late MessageRepository messageRepo;
  late BudRepository budRepo;
  late SettingsRepository settingsRepo;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
    isar = await Isar.open([
      ConversationSchema,
      MessageSchema,
      BudSchema,
      AppSettingsSchema,
    ], directory: '.');

    conversationRepo = ConversationRepository(isar);
    messageRepo = MessageRepository(isar);
    budRepo = BudRepository(isar);
    settingsRepo = SettingsRepository(isar);
  });

  tearDownAll(() async {
    await isar.close(deleteFromDisk: true);
  });

  group('Conversation & Message Repository Tests', () {
    test('Cascade deletion deletes messages when conversation is deleted', () async {
      final conv = Conversation(
        title: 'Test Conversation',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final userMsg = Message(
        conversationId: 0,
        text: 'Hello',
        role: MessageRole.user,
        createdAt: DateTime.now(),
      );

      final assistantMsg = Message(
        conversationId: 0,
        text: 'Hi there!',
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
      );

      final saved = await messageRepo.saveMessagePairAndTouchConversation(
        conversation: conv,
        userMessage: userMsg,
        assistantMessage: assistantMsg,
      );

      expect(saved, isNotNull);
      final conversationId = conv.id;

      final initialMessages = await messageRepo.getMessagesForConversation(conversationId);
      expect(initialMessages.length, equals(2));

      await conversationRepo.deleteConversation(conversationId);

      final remainingMessages = await messageRepo.getMessagesForConversation(conversationId);
      expect(remainingMessages.length, equals(0));
    });

    test('Race Condition Safeguard: Save message pair fails gracefully if parent conversation deleted', () async {
      final conv = Conversation(
        id: 999999, // Non-existent conversation ID
        title: 'Ghost Conversation',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final userMsg = Message(
        conversationId: 999999,
        text: 'Orphan text',
        role: MessageRole.user,
        createdAt: DateTime.now(),
      );

      final assistantMsg = Message(
        conversationId: 999999,
        text: 'Orphan response',
        role: MessageRole.assistant,
        createdAt: DateTime.now(),
      );

      final result = await messageRepo.saveMessagePairAndTouchConversation(
        conversation: conv,
        userMessage: userMsg,
        assistantMessage: assistantMsg,
      );

      expect(result, isNull);
    });

    test('SettingsRepository enforces fixed ID 1 single instance', () async {
      final settings1 = await settingsRepo.getSettings();
      expect(settings1.id, equals(1));
      expect(settings1.serverIp, equals('192.168.1.74'));

      await settingsRepo.updateServerIp('10.0.0.5');

      final settings2 = await settingsRepo.getSettings();
      expect(settings2.id, equals(1));
      expect(settings2.serverIp, equals('10.0.0.5'));
    });

    test('BudRepository seeds stable default personas 1-4', () async {
      await budRepo.seedDefaultBuds();

      final buds = await budRepo.watchBuds().first;
      expect(buds.length, greaterThanOrEqualTo(4));

      final generalBud = buds.firstWhere((b) => b.id == 1);
      expect(generalBud.name, equals('General Bud'));
    });

    test('Paginated message history loading with deterministic ordering', () async {
      final conv = Conversation(
        title: 'Paginated Conv',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await isar.writeTxn(() async {
        await isar.conversations.put(conv);
      });

      final now = DateTime.now();
      for (int i = 0; i < 10; i++) {
        await messageRepo.saveMessageAndTouchConversation(
          Message(
            conversationId: conv.id,
            text: 'Message $i',
            role: MessageRole.user,
            createdAt: now.add(Duration(seconds: i)),
          ),
        );
      }

      final page1 = await messageRepo.getMessagesForConversationPaginated(
        conv.id,
        limit: 5,
        offset: 0,
      );
      expect(page1.length, equals(5));
      expect(page1.first.text, equals('Message 5'));

      final page2 = await messageRepo.getMessagesForConversationPaginated(
        conv.id,
        limit: 5,
        offset: 5,
      );
      expect(page2.length, equals(5));
      expect(page2.first.text, equals('Message 0'));
    });
  });
}
