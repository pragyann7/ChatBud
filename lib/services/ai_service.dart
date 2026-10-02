import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:chatbud/models/message.dart';

abstract class AiService {
  Stream<String> generateResponse({
    required String prompt,
    String? systemPrompt,
    List<Message>? conversationHistory,
  });
}

class MacAiService implements AiService {
  http.Client? _client;
  final String serverIp;
  final String port;
  final String modelName;
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  MacAiService({
    this.serverIp = '192.168.1.74',
    this.port = '11434',
    // this.modelName = 'llama3.1:8b-instruct-q3_K_M',
    this.modelName = 'qwen3:0.6b',
    // this.modelName = 'llama3.2:1b',
  });

  String get baseUrl {
    final ip = serverIp.trim();
    if (ip.startsWith('http://') || ip.startsWith('https://')) {
      return ip;
    }
    return 'http://$ip:$port';
  }

  @override
  Stream<String> generateResponse({
    required String prompt,
    String? systemPrompt,
    List<Message>? conversationHistory,
  }) async* {
    _isCancelled = false;
    try {
      // 9 & 10. Multi-turn conversation context with sliding window limit (last 10 messages)
      final List<Map<String, String>> chatMessages = [];

      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        chatMessages.add({
          'role': 'system',
          'content': systemPrompt,
        });
      }

      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        // Filter out empty/failed messages
        final validHistory = conversationHistory
            .where((m) => m.text.isNotEmpty && m.status != MessageStatus.failed)
            .toList();

        // Enforce context limit: Take last 10 messages max (~1500 tokens)
        final boundedHistory = validHistory.length > 10
            ? validHistory.sublist(validHistory.length - 10)
            : validHistory;

        for (final msg in boundedHistory) {
          chatMessages.add({
            'role': msg.isUser ? 'user' : 'assistant',
            'content': msg.text,
          });
        }
      } else {
        chatMessages.add({
          'role': 'user',
          'content': prompt,
        });
      }

      // Use Ollama's /api/chat endpoint for multi-turn chat history
      final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'));
      request.headers['Content-Type'] = 'application/json';

      final bodyMap = <String, dynamic>{
        'model': modelName,
        'messages': chatMessages,
        'stream': true,
      };

      // Conditionally pass 'think': true for reasoning models
      final lowerModel = modelName.toLowerCase();
      if (lowerModel.contains('qwen3') ||
          lowerModel.contains('deepseek') ||
          lowerModel.contains('qwq')) {
        bodyMap['think'] = true;
      }

      request.body = jsonEncode(bodyMap);

      _client = http.Client();

      final response = await _client!
          .send(request)
          .timeout(const Duration(seconds: 50));

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw Exception(
          'Ollama request failed: HTTP ${response.statusCode} - $body',
        );
      }

      // Transform raw byte stream into lines (NDJSON)
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 15));

      bool inThinkingState = false;

      await for (final line in lines) {
        if (line.trim().isEmpty) continue;

        Map<String, dynamic> data;
        try {
          data = jsonDecode(line) as Map<String, dynamic>;
        } catch (_) {
          // Handle malformed NDJSON lines safely
          continue;
        }

        if (data['done'] == true) {
          if (inThinkingState) {
            yield '\n</think>\n';
          }
          break;
        }

        // 1. Dedicated 'thinking' or 'reasoning_content' JSON field
        final thinkingChunk = data['thinking'] as String? ??
            data['reasoning_content'] as String? ??
            (data['message'] is Map
                ? data['message']['thinking'] as String?
                : null);

        if (thinkingChunk != null && thinkingChunk.isNotEmpty) {
          if (!inThinkingState) {
            inThinkingState = true;
            yield '<think>\n';
          }
          yield thinkingChunk;
          continue;
        }

        // If thinking ended, close the <think> tag
        if (inThinkingState) {
          inThinkingState = false;
          yield '\n</think>\n';
        }

        // 2. Standard response text field from /api/chat or /api/generate
        final token = (data['message'] is Map
                ? data['message']['content'] as String?
                : null) ??
            data['response'] as String?;

        if (token != null && token.isNotEmpty) {
          yield token;
        }
      }
    } on SocketException {
      if (!_isCancelled) {
        throw AiServiceException('Could not connect to Ollama at $baseUrl.');
      }
    } on http.ClientException {
      if (!_isCancelled) {
        throw AiServiceException('Could not connect to Ollama at $baseUrl.');
      }
    } on TimeoutException {
      if (!_isCancelled) {
        throw AiServiceException('Ollama stopped responding for too long.');
      }
    } catch (e, stackTrace) {
      debugPrint("Ollama Stream Error: $e\n$stackTrace");
      if (!_isCancelled) {
        rethrow;
      }
    }
  }

  void stopGeneration() {
    _isCancelled = true;
    _client?.close();
    _client = null;
  }
}

class AiServiceException implements Exception {
  final String message;

  AiServiceException(this.message);

  @override
  String toString() => message;
}
