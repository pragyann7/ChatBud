import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatbud/models/app_settings.dart';
import 'package:chatbud/models/message.dart';
import 'package:chatbud/repositories/message_repository.dart';
import 'package:chatbud/repositories/settings_repository.dart';
import 'package:chatbud/services/generation_manager.dart';

class _FakeMessageRepository implements MessageRepository {
  final Map<int, Message> messages = {};

  @override
  Future<int?> saveMessageAndTouchConversation(Message message) async {
    messages[message.id] = message;
    return message.id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async {
    return AppSettings(engineType: 'llama_cpp');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 5 — Production Stress & Memory Safeguard Tests', () {
    late _FakeMessageRepository messageRepo;
    late _FakeSettingsRepository settingsRepo;
    late GenerationManager genManager;

    setUp(() {
      messageRepo = _FakeMessageRepository();
      settingsRepo = _FakeSettingsRepository();
      genManager = GenerationManager(
        messageRepository: messageRepo,
        settingsRepository: settingsRepo,
      );
    });

    tearDown(() {
      genManager.dispose();
    });

    test('Stress Test 1: Rapid chat switching during background generation', () async {
      await genManager.startGeneration(
        conversationId: 101,
        assistantMessageId: 1001,
        prompt: 'Generate long response for Chat 101',
        conversationHistory: [],
        createdAt: DateTime.now(),
      );

      expect(genManager.isGenerating(101), isTrue);

      await genManager.startGeneration(
        conversationId: 102,
        assistantMessageId: 1002,
        prompt: 'Generate long response for Chat 102',
        conversationHistory: [],
        createdAt: DateTime.now(),
      );

      expect(genManager.isGenerating(102), isTrue);

      final notifier101 = genManager.getNotifier(101, 1001);
      final notifier102 = genManager.getNotifier(102, 1002);

      expect(notifier101, isNotNull);
      expect(notifier102, isNotNull);
      expect(notifier101, isNot(equals(notifier102)));

      await Future.delayed(const Duration(milliseconds: 300));

      expect(genManager.hasUnreadCompletion(101), isTrue);
      expect(genManager.hasUnreadCompletion(102), isTrue);

      genManager.markConversationAsRead(101);
      expect(genManager.hasUnreadCompletion(101), isFalse);
      expect(genManager.hasUnreadCompletion(102), isTrue);
    });

    test('Stress Test 2: Rapid cancellation and state recovery', () async {
      await genManager.startGeneration(
        conversationId: 201,
        assistantMessageId: 2001,
        prompt: 'Cancel this prompt',
        conversationHistory: [],
        createdAt: DateTime.now(),
      );

      expect(genManager.isGenerating(201), isTrue);

      await genManager.stopGeneration(201);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(genManager.isGenerating(201), isFalse);
    });
  });
}
