import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:chatbud/models/message.dart';
import 'package:chatbud/repositories/message_repository.dart';
import 'package:chatbud/repositories/settings_repository.dart';
import 'package:chatbud/services/ai_service.dart';
import 'package:chatbud/services/llama_cpp_service.dart';

class ActiveGenerationJob {
  final int conversationId;
  final int assistantMessageId;
  final String prompt;
  final String? systemPrompt;
  final List<Message> conversationHistory;
  final DateTime createdAt;
  final int? budId;
  final ValueNotifier<String> notifier = ValueNotifier<String>("");
  final StringBuffer accumulatedText = StringBuffer();
  final AiService aiService;
  bool isCompleted = false;

  ActiveGenerationJob({
    required this.conversationId,
    required this.assistantMessageId,
    required this.prompt,
    this.systemPrompt,
    required this.conversationHistory,
    required this.createdAt,
    this.budId,
    required this.aiService,
  });
}

class GenerationManager extends ChangeNotifier with WidgetsBindingObserver {
  final MessageRepository messageRepository;
  final SettingsRepository settingsRepository;

  final Map<int, ActiveGenerationJob> _activeJobs = {};
  final Set<int> _startingConversationIds = {};
  final Set<int> _unreadCompletedIds = {};

  GenerationManager({
    required this.messageRepository,
    required this.settingsRepository,
  }) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      // App backgrounded, hidden, or closed: Automatically unload GGUF model from RAM to prevent OS OOM kills
      debugPrint("App $state: Releasing C-heap native RAM to prevent OS OOM kills");
      unawaited(LlamaCppAiService.unloadModel());
    } else if (state == AppLifecycleState.resumed) {
      // App resumed / brought to foreground: Automatically reload local model (PocketPal pattern)
      debugPrint("App resumed: Auto-reloading local model into RAM (PocketPal pattern)");
      unawaited(_preloadModelOnResume());
    }
  }

  Future<void> _preloadModelOnResume() async {
    if (!Platform.isAndroid) return;
    try {
      final settings = await settingsRepository.getSettings();
      if (settings.engineType != 'llama_cpp') return;
      final path = settings.modelPath;
      if (path == null || path.trim().isEmpty) return;
      final file = File(path);
      if (!await file.exists() || await file.length() < 4) return;
      if (LlamaCppAiService.isModelLoaded || LlamaCppAiService.isModelLoading) {
        return;
      }
      await LlamaCppAiService.loadModel(
        file.path,
        cpuThreads: settings.cpuThreads,
        contextSize: settings.contextSize,
        batchSize: settings.batchSize,
      );
    } catch (e) {
      debugPrint("Auto-preload on resume notice (non-fatal): $e");
    }
  }

  bool isGenerating(int conversationId) {
    return _activeJobs.containsKey(conversationId);
  }

  bool get isAnyGenerating => _activeJobs.isNotEmpty;

  bool hasUnreadCompletion(int conversationId) {
    return _unreadCompletedIds.contains(conversationId);
  }

  void markConversationAsRead(int conversationId) {
    if (_unreadCompletedIds.contains(conversationId)) {
      _unreadCompletedIds.remove(conversationId);
      notifyListeners();
    }
  }

  ActiveGenerationJob? getJob(int conversationId) {
    return _activeJobs[conversationId];
  }

  ValueNotifier<String>? getNotifier(
    int conversationId,
    int assistantMessageId,
  ) {
    final job = _activeJobs[conversationId];
    if (job != null && job.assistantMessageId == assistantMessageId) {
      return job.notifier;
    }
    return null;
  }

  Future<void> startGeneration({
    required int conversationId,
    required int assistantMessageId,
    required String prompt,
    String? systemPrompt,
    required List<Message> conversationHistory,
    required DateTime createdAt,
    int? budId,
  }) async {
    _unreadCompletedIds.remove(conversationId);

    if (_activeJobs.containsKey(conversationId) ||
        !_startingConversationIds.add(conversationId)) {
      return;
    }
    try {
      final settings = await settingsRepository.getSettings();
      final AiService aiService;

      if (settings.engineType == 'llama_cpp') {
        aiService = LlamaCppAiService(
          modelPath: settings.modelPath,
          cpuThreads: settings.cpuThreads,
          contextSize: settings.contextSize,
          batchSize: settings.batchSize,
        );
      } else {
        aiService = MacAiService(
          serverIp: settings.serverIp ?? '192.168.1.74',
          modelName: settings.selectedModel ?? 'qwen3:0.6b',
        );
      }

      final job = ActiveGenerationJob(
        conversationId: conversationId,
        assistantMessageId: assistantMessageId,
        prompt: prompt,
        systemPrompt: systemPrompt,
        conversationHistory: List.unmodifiable(conversationHistory),
        createdAt: createdAt,
        budId: budId,
        aiService: aiService,
      );

      _activeJobs[conversationId] = job;
      notifyListeners();
      unawaited(_runGenerationJob(job));
    } catch (error, stackTrace) {
      debugPrint(
        'Could not start generation for $conversationId: $error\n$stackTrace',
      );
      try {
        await messageRepository.saveMessageAndTouchConversation(
          Message(
            id: assistantMessageId,
            conversationId: conversationId,
            text: '',
            role: MessageRole.assistant,
            status: MessageStatus.failed,
            createdAt: createdAt,
            budId: budId,
          ),
        );
      } catch (persistError) {
        debugPrint('Could not persist startup failure: $persistError');
      }
      _unreadCompletedIds.add(conversationId);
      notifyListeners();
    } finally {
      _startingConversationIds.remove(conversationId);
    }
  }

  Future<void> _runGenerationJob(ActiveGenerationJob job) async {
    var lastPublished = DateTime.fromMillisecondsSinceEpoch(0);
    MessageStatus finalStatus = MessageStatus.completed;

    try {
      await for (final token in job.aiService.generateResponse(
        prompt: job.prompt,
        systemPrompt: job.systemPrompt,
        conversationHistory: job.conversationHistory,
      )) {
        job.accumulatedText.write(token);
        final currentTime = DateTime.now();
        if (currentTime.difference(lastPublished).inMilliseconds >= 16) {
          job.notifier.value = job.accumulatedText.toString();
          lastPublished = currentTime;
        }
      }
      job.notifier.value = job.accumulatedText.toString();
      finalStatus = MessageStatus.completed;
    } on AiServiceException catch (e) {
      debugPrint(
        "Background AI Service Error ($e) in conv ${job.conversationId}",
      );
      finalStatus = MessageStatus.failed;
    } catch (e, stackTrace) {
      debugPrint(
        "Background Stream Error ($e) in conv ${job.conversationId}\n$stackTrace",
      );
      finalStatus = MessageStatus.failed;
    } finally {
      final finalText = job.accumulatedText.toString();
      job.notifier.value = finalText;

      await _persistMessageResponse(job, finalText, finalStatus);

      job.isCompleted = true;
      _activeJobs.remove(job.conversationId);
      _unreadCompletedIds.add(job.conversationId);
      notifyListeners();

      job.notifier.dispose();
    }
  }

  Future<void> stopGeneration(int conversationId) async {
    final job = _activeJobs[conversationId];
    if (job != null) {
      job.aiService.stopGeneration();
    }
  }

  Future<void> _persistMessageResponse(
    ActiveGenerationJob job,
    String text,
    MessageStatus status,
  ) async {
    try {
      final msg = Message(
        id: job.assistantMessageId,
        conversationId: job.conversationId,
        text: text,
        role: MessageRole.assistant,
        status: status,
        createdAt: job.createdAt,
        budId: job.budId,
      );
      await messageRepository.saveMessageAndTouchConversation(msg);
    } catch (e) {
      debugPrint(
        "Could not persist background message ${job.assistantMessageId}: $e",
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final job in _activeJobs.values) {
      job.aiService.stopGeneration();
      job.notifier.dispose();
    }
    _activeJobs.clear();
    _unreadCompletedIds.clear();
    super.dispose();
  }
}
