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
    if (_engine != null && _loadedModelPath == normalizedPath) return;
    if (_loading != null) {
      await _loading;
      if (_engine != null && _loadedModelPath == normalizedPath) return;
    }

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
      // runtime in the APK. Passing libmtmd.so here bypassed that packaging and
      // failed because that standalone library was never shipped by 0.2.x.
      final engine = await LlamaEngine.spawn(
        modelParams: ModelParams(path: normalizedPath),
        contextParams:
            ContextParams.mobile(
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
    } catch (error) {
      _loadedModelPath = null;
      if (error is AiServiceException) rethrow;
      throw AiServiceException('Could not load the local model: $error');
    } finally {
      _loading = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  static Future<void> _disposeRuntime() async {
    final engine = _engine;
    _engine = null;
    _loadedModelPath = null;
    if (engine == null) return;
    try {
      await engine.dispose();
    } catch (error) {
      debugPrint('Error disposing llama.cpp runtime: $error');
    }
  }

  static Future<void> unloadModel() async {
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
    EngineChat? chat;
    try {
      chat = await _engine!.createChat();
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
        chat.addSystem(systemPrompt.trim());
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
          chat.addUser(message.text);
          if (message.text == prompt) includesCurrentPrompt = true;
        } else {
          chat.addAssistant(message.text);
        }
      }
      if (!includesCurrentPrompt) chat.addUser(prompt);

      _activeGeneration = chat
          .generate(
            sampler: const SamplerParams(temperature: 0.7, topK: 40, topP: 0.9),
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
      yield* output.stream;
    } finally {
      final generation = _activeGeneration;
      _activeGeneration = null;
      if (generation != null) await generation.cancel();
      await chat?.dispose();
      if (!output.isClosed) await output.close();
      if (identical(_activeOutput, output)) _activeOutput = null;
    }
  }

  @override
  void stopGeneration() {
    unawaited(stopActiveGeneration());
  }
}
