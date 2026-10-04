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

  void stopGeneration();
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
    this.modelName = 'qwen3:0.6b',
  });

  String get baseUrl {
    final ip = serverIp.trim();
    if (ip.startsWith('http://') || ip.startsWith('https://')) {
      return ip;
    }
    return 'http://$ip:$port';
  }

  Future<List<String>> fetchAvailableModels() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final List<dynamic> modelsList = data['models'] as List<dynamic>? ?? [];
        return modelsList
            .map((m) => (m is Map ? m['name'] as String? : null) ?? '')
            .where((name) => name.isNotEmpty)
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint("Error fetching Ollama models from $baseUrl/api/tags: $e");
      return [];
    }
  }

  @override
  Stream<String> generateResponse({
    required String prompt,
    String? systemPrompt,
    List<Message>? conversationHistory,
  }) async* {
    _isCancelled = false;
    try {
      final List<Map<String, String>> chatMessages = [];

      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        chatMessages.add({
          'role': 'system',
          'content': systemPrompt,
        });
      }

      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        final validHistory = conversationHistory
            .where((m) => m.text.isNotEmpty && m.status != MessageStatus.failed)
            .toList();

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

      final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'));
      request.headers['Content-Type'] = 'application/json';

      final bodyMap = <String, dynamic>{
        'model': modelName,
        'messages': chatMessages,
        'stream': true,
      };

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
          continue;
        }

        if (data['done'] == true) {
          if (inThinkingState) {
            yield '\n</think>\n';
          }
          break;
        }

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

        if (inThinkingState) {
          inThinkingState = false;
          yield '\n</think>\n';
        }

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

  @override
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
