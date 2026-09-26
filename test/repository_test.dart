import 'dart:io';
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
  late Directory tempDir;
  late ConversationRepository conversationRepo;
  late MessageRepository messageRepo;
  late BudRepository budRepo;
  late SettingsRepository settingsRepo;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chatbud_test_');
    isar = await Isar.open(
      [
        ConversationSchema,
        MessageSchema,
        BudSchema,
        AppSettingsSchema,
      ],
      directory: tempDir.path,
    );

    conversationRepo = ConversationRepository(isar);
    messageRepo = MessageRepository(isar);
    budRepo = BudRepository(isar);
    settingsRepo = SettingsRepository(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SettingsRepository Tests', () {
    test('Enforces fixed ID 1 and initializes defaults', () async {
      final settings = await settingsRepo.getSettings();
      expect(settings.id, equals(1));
      expect(settings.theme, equals('system'));

      final count = await isar.appSettings.count();
      expect(count, equals(1));
    });

    test('Atomic updates for theme and model', () async {
      await settingsRepo.updateTheme('dark');
      await settingsRepo.updateSelectedModel('llama-3.2-3b.gguf');

      final settings = await settingsRepo.getSettings();
      expect(settings.theme, equals('dark'));
      expect(settings.selectedModel, equals('llama-3.2-3b.gguf'));
    });
  });

  group('BudRepository Tests', () {
    test('Seeds default Buds independently using stable IDs 1..4', () async {
      await budRepo.seedDefaultBuds();
      final buds = await budRepo.getBuds();

      expect(buds.length, equals(4));
      expect(buds.map((b) => b.id), containsAll([1, 2, 3, 4]));
      expect(buds.firstWhere((b) => b.id == 2).name, equals('Coding Bud'));
    });

    test('Prevents deleting built-in default Buds', () async {
      await budRepo.seedDefaultBuds();

      final deleteResult = await budRepo.deleteBud(1); // General Bud (default)
      expect(deleteResult, isFalse);

      final bud1 = await budRepo.getBud(1);
      expect(bud1, isNotNull);
    });

    test('Custom Bud creation and deletion without id 0 conflict', () async {
      await budRepo.seedDefaultBuds();

      final customBud = Bud(
        id: Isar.autoIncrement,
        name: 'Pirate Bud',
        systemPrompt: 'Ahoy!',
        iconName: 'smart_toy',
      );

      final id = await budRepo.saveBud(customBud);
      expect(id, greaterThan(4)); // AutoIncrement after stable IDs 1..4

      final fetched = await budRepo.getBud(id);
      expect(fetched?.name, equals('Pirate Bud'));

      final deleted = await budRepo.deleteBud(id);
      expect(deleted, isTrue);

      final afterDelete = await budRepo.getBud(id);
      expect(afterDelete, isNull);
    });
  });

  group('Conversation & Message Repository Tests', () {
    test('Conversation creation and pinning', () async {
      final conv = await conversationRepo.createNewConversation(title: 'Test Chat');
      expect(conv.id, isPositive);
      expect(conv.title, equals('Test Chat'));
      expect(conv.isPinned, isFalse);

      await conversationRepo.togglePinConversation(conv);
      final pinned = await conversationRepo.getConversation(conv.id);
      expect(pinned?.isPinned, isTrue);
    });

    test('Cascade message deletion on conversation deletion', () async {
      final conv = await conversationRepo.createNewConversation(title: 'Cascade Test');
      final msg = Message(
        conversationId: conv.id,
        text: 'Hello',
        role: MessageRole.user,
        createdAt: DateTime.now(),
      );
      await messageRepo.saveMessageAndTouchConversation(msg);

      final messagesBefore = await messageRepo.getMessagesForConversation(conv.id);
      expect(messagesBefore.length, equals(1));

      await conversationRepo.deleteConversation(conv.id);

      final messagesAfter = await messageRepo.getMessagesForConversation(conv.id);
      expect(messagesAfter, isEmpty);
      final deletedConv = await conversationRepo.getConversation(conv.id);
      expect(deletedConv, isNull);
    });

    test('Race condition: Aborts message save if parent conversation was deleted', () async {
      final conv = await conversationRepo.createNewConversation(title: 'Race Test');
      await conversationRepo.deleteConversation(conv.id);

      final msg = Message(
        conversationId: conv.id,
        text: 'Orphan message',
        role: MessageRole.user,
        createdAt: DateTime.now(),
      );

      final msgId = await messageRepo.saveMessageAndTouchConversation(msg);
      expect(msgId, isNull); // Verified parent conversation check inside writeTxn!
    });

    test('Paginated message history loading with deterministic ordering', () async {
      final conv = await conversationRepo.createNewConversation(title: 'Pagination Test');
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
      expect(page1.first.text, equals('Message 0'));

      final page2 = await messageRepo.getMessagesForConversationPaginated(
        conv.id,
        limit: 5,
        offset: 5,
      );
      expect(page2.length, equals(5));
      expect(page2.first.text, equals('Message 5'));
    });
  });
}
