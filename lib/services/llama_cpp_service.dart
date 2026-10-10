import 'dart:async';
import 'dart:io';

import 'package:chatbud/models/message.dart';
import 'package:chatbud/services/ai_service.dart';
import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

/// Runs one local model at a time and owns its native runtime for the process.
///
/// llama_cpp_dart 0.9 packages Android's llama.cpp libraries as native assets;
/// Android must use the packaged default library name (`libllama.so`) instead
/// of trying to open the old, unbundled `libmtmd.so` name directly.
class LlamaCppAiService implements AiService {
  final String? modelPath;
  final int cpuThreads;
  final int contextSize;
  final int batchSize;

  static LlamaEngine? _engine;
  static String? _loadedModelPath;
  static Future<void>? _loading;
  static StreamController<String>? _activeOutput;
  static StreamSubscription<GenerationEvent>? _activeGeneration;

  /// Industry-standard idle keep-alive timeout (5 minutes, matching LM Studio, Ollama, & PocketPal AI).
  static const Duration defaultKeepAliveDuration = Duration(minutes: 5);
  static Timer? _inactivityTimer;

  static final ValueNotifier<bool> isModelLoadingNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<bool> isModelLoadedNotifier =
      ValueNotifier<bool>(false);

  static bool get isModelLoading =>
      _loading != null || isModelLoadingNotifier.value;
  static bool get isModelLoaded => _engine != null;
  static String? get loadedModelPath => _loadedModelPath;

  LlamaCppAiService({
    this.modelPath,
    this.cpuThreads = 4,
    this.contextSize = 2048,
    this.batchSize = 512,
  });

  static Future<void> loadModel(
    String path, {
    int cpuThreads = 4,
    int contextSize = 2048,
    int batchSize = 512,
  }) async {
    if (!Platform.isAndroid) {
      throw AiServiceException(
        'The packaged local model runtime is currently available on Android only.',
      );
    }

    final normalizedPath = File(path).absolute.path;
    if (_activeOutput != null) {
      throw AiServiceException(
        'Stop the current response before changing models.',
      );
    }
    if (_engine != null && _loadedModelPath == normalizedPath) {
      _scheduleInactivityUnload();
      return;
    }
    if (_loading != null) {
      await _loading;
      if (_engine != null && _loadedModelPath == normalizedPath) {
        _scheduleInactivityUnload();
        return;
      }
    }

    isModelLoadingNotifier.value = true;
    final completer = Completer<void>();
    _loading = completer.future;
    try {
      await _disposeRuntime();
      final modelFile = File(normalizedPath);
      if (!await modelFile.exists() || await modelFile.length() < 4) {
        throw AiServiceException(
          'The selected model file is missing or empty.',
        );
      }

      // On Android the package's native-assets hook puts the CPU llama.cpp
      // runtime in the APK.
      final engine = await LlamaEngine.spawn(
        modelParams: ModelParams(path: normalizedPath),
        contextParams: ContextParams.mobile(
          nCtx: contextSize.clamp(256, 131072),
          nBatch: batchSize.clamp(32, 4096),
          nUbatch: batchSize.clamp(32, 4096),
        ).copyWith(
          nThreads: cpuThreads.clamp(1, 64),
          nThreadsBatch: cpuThreads.clamp(1, 64),
        ),
      ).timeout(const Duration(minutes: 3));

      _engine = engine;
      _loadedModelPath = normalizedPath;
      isModelLoadedNotifier.value = true;
      _scheduleInactivityUnload();
    } catch (error) {
      _loadedModelPath = null;
      isModelLoadedNotifier.value = false;
      if (error is AiServiceException) rethrow;
      throw AiServiceException('Could not load the local model: $error');
    } finally {
      _loading = null;
      isModelLoadingNotifier.value = false;
      if (!completer.isCompleted) completer.complete();
    }
  }

  static void _scheduleInactivityUnload([Duration? duration]) {
    _inactivityTimer?.cancel();
    if (!isModelLoaded) return;
    final timeout = duration ?? defaultKeepAliveDuration;
    _inactivityTimer = Timer(timeout, () {
      if (_activeGeneration == null && _activeOutput == null) {
        debugPrint(
          'llama.cpp model idle for ${timeout.inMinutes} minutes. '
          'Auto-unloading from RAM according to production standard.',
        );
        unawaited(unloadModel());
      } else {
        _scheduleInactivityUnload();
      }
    });
  }

  static void _cancelInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  /// Extends the model keep-alive TTL during active user interaction.
  static void touchActivity() {
    if (isModelLoaded && _activeGeneration == null) {
      _scheduleInactivityUnload();
    }
  }

  static Future<void> _disposeRuntime() async {
    final engine = _engine;
    _engine = null;
    _loadedModelPath = null;
    isModelLoadedNotifier.value = false;
    if (engine == null) return;
    try {
      await engine.dispose();
    } catch (error) {
      debugPrint('Error disposing llama.cpp runtime: $error');
    }
  }

  static Future<void> unloadModel() async {
    _cancelInactivityTimer();
    await stopActiveGeneration();
    await _disposeRuntime();
  }

  static Future<void> stopActiveGeneration() async {
    final generation = _activeGeneration;
    _activeGeneration = null;
    if (generation != null) {
      try {
        await generation.cancel();
      } catch (error) {
        debugPrint('Error stopping llama.cpp generation: $error');
      }
    }
    final output = _activeOutput;
    if (output != null && !output.isClosed) await output.close();
    _activeOutput = null;
  }

  @override
  Stream<String> generateResponse({
    required String prompt,
    String? systemPrompt,
    List<Message>? conversationHistory,
  }) async* {
    final path = modelPath;
    if (path == null || path.trim().isEmpty) {
      throw AiServiceException(
        'Choose a GGUF model before starting local chat.',
      );
    }
    if (_engine == null || _loadedModelPath != File(path).absolute.path) {
      await loadModel(
        path,
        cpuThreads: cpuThreads,
        contextSize: contextSize,
        batchSize: batchSize,
      );
    }
    if (_activeOutput != null) {
      throw AiServiceException(
        'The on-device engine is busy with another conversation. Try again when it finishes.',
      );
    }

    final output = StreamController<String>();
    _activeOutput = output;
    _cancelInactivityTimer();

    EngineChat? chat;
    EngineSession? session;

    try {
      // TIER 1: Native EngineChat Template
      try {
        chat = await _engine!.createChat();
      } catch (chatError) {
        debugPrint(
            'Engine.createChat failed ($chatError), falling back to EngineSession');
      }

      if (chat != null) {
        bool systemAdded = false;
        if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
          try {
            chat.addSystem(systemPrompt.trim());
            systemAdded = true;
          } catch (e) {
            debugPrint(
                "Model template does not support system role, prepending to user prompt: $e");
            systemAdded = false;
          }
        }

        final history = (conversationHistory ?? const <Message>[]).where(
          (message) =>
              message.text.isNotEmpty &&
              message.status != MessageStatus.failed &&
              message.status != MessageStatus.pending,
        );
        var includesCurrentPrompt = false;
        for (final message in history) {
          if (message.isUser) {
            String userText = message.text;
            if (!systemAdded &&
                systemPrompt != null &&
                systemPrompt.trim().isNotEmpty) {
              userText =
                  "System Instruction: ${systemPrompt.trim()}\n\n$userText";
              systemAdded = true;
            }
            chat.addUser(userText);
            if (message.text == prompt) includesCurrentPrompt = true;
          } else {
            chat.addAssistant(message.text);
          }
        }
        if (!includesCurrentPrompt) {
          String userText = prompt;
          if (!systemAdded &&
              systemPrompt != null &&
              systemPrompt.trim().isNotEmpty) {
            userText =
                "System Instruction: ${systemPrompt.trim()}\n\n$userText";
            systemAdded = true;
          }
          chat.addUser(userText);
        }

        _activeGeneration = chat
            .generate(
              sampler:
                  const SamplerParams(temperature: 0.7, topK: 40, topP: 0.9),
              maxTokens: 1024,
            )
            .listen(
              (event) {
                if (event case TokenEvent(:final text) when text.isNotEmpty) {
                  if (!output.isClosed) output.add(text);
                } else if (event case DoneEvent(:final trailingText)
                    when trailingText.isNotEmpty) {
                  if (!output.isClosed) output.add(trailingText);
                }
              },
              onError: (Object error, StackTrace stack) {
                if (!output.isClosed) {
                  output.addError(
                    AiServiceException('Local inference failed: $error'),
                    stack,
                  );
                  output.close();
                }
              },
              onDone: () {
                if (!output.isClosed) output.close();
              },
            );
      } else {
        // TIER 2: EngineSession Turn-Based Fallback
        session = await _engine!.createSession();
        final StringBuffer fullPrompt = StringBuffer();
        if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
          fullPrompt.writeln(
              "<start_of_turn>system\n${systemPrompt.trim()}<end_of_turn>");
        }
        final history = (conversationHistory ?? const <Message>[]).where(
          (message) =>
              message.text.isNotEmpty &&
              message.status != MessageStatus.failed &&
              message.status != MessageStatus.pending,
        );
        var includesCurrentPrompt = false;
        for (final message in history) {
          if (message.isUser) {
            fullPrompt.writeln(
                "<start_of_turn>user\n${message.text}<end_of_turn>");
            if (message.text == prompt) includesCurrentPrompt = true;
          } else {
            fullPrompt.writeln(
                "<start_of_turn>model\n${message.text}<end_of_turn>");
          }
        }
        if (!includesCurrentPrompt) {
          fullPrompt.writeln("<start_of_turn>user\n$prompt<end_of_turn>");
        }
        fullPrompt.write("<start_of_turn>model\n");

        _activeGeneration = session
            .generate(
              prompt: fullPrompt.toString(),
              sampler:
                  const SamplerParams(temperature: 0.7, topK: 40, topP: 0.9),
              maxTokens: 1024,
            )
            .listen(
              (event) {
                if (event case TokenEvent(:final text) when text.isNotEmpty) {
                  if (!output.isClosed) output.add(text);
                } else if (event case DoneEvent(:final trailingText)
                    when trailingText.isNotEmpty) {
                  if (!output.isClosed) output.add(trailingText);
                }
              },
              onError: (Object error, StackTrace stack) {
                if (!output.isClosed) {
                  output.addError(
                    AiServiceException('Local inference failed: $error'),
                    stack,
                  );
                  output.close();
                }
              },
              onDone: () {
                if (!output.isClosed) output.close();
              },
            );
      }

      yield* output.stream;
    } finally {
      final generation = _activeGeneration;
      _activeGeneration = null;
      if (generation != null) await generation.cancel();
      await chat?.dispose();
      await session?.dispose();
      if (!output.isClosed) await output.close();
      if (identical(_activeOutput, output)) _activeOutput = null;
      if (isModelLoaded) {
        _scheduleInactivityUnload();
      }
    }
  }

  @override
  void stopGeneration() {
    unawaited(stopActiveGeneration());
  }
}
