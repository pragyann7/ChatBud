import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

abstract class AiService {
  Stream<String> generateResponse({
    required String prompt,
    String? systemPrompt,
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
  }) async* {
    _isCancelled = false;
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/api/generate'));

      request.headers['Content-Type'] = 'application/json';

      final bodyMap = <String, dynamic>{
        'model': modelName,
        'prompt': prompt,
        'think': true,
        'stream': true,
      };

      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        bodyMap['system'] = systemPrompt;
      }

      request.body = jsonEncode(bodyMap);

      _client = http.Client();

      final response = await _client!
          .send(request)
          .timeout(const Duration(seconds: 35));

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

        final data = jsonDecode(line) as Map<String, dynamic>;

        if (data['done'] == true) {
          if (inThinkingState) {
            yield '\n</think>\n';
          }
          break;
        }

        // 1. Check if Ollama provides a dedicated 'thinking' or 'reasoning_content' JSON field
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

        // If thinking field ended, close the <think> tag
        if (inThinkingState) {
          inThinkingState = false;
          yield '\n</think>\n';
        }

        // 2. Standard response text field (may contain raw <think> tags from models like deepseek-r1)
        final token = data['response'] as String? ??
            (data['message'] is Map
                ? data['message']['content'] as String?
                : null);

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
