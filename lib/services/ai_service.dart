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
  final String baseUrl;
  final String modelName;
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  MacAiService({
    this.baseUrl = 'http://10.177.114.245:11434',
    this.modelName = 'llama3.2:1b',
  });

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
        'stream': true,
      };

      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        bodyMap['system'] = systemPrompt;
      }

      request.body = jsonEncode(bodyMap);

      _client = http.Client();

      final response = await _client!
          .send(request)
          .timeout(const Duration(seconds: 15));

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

      await for (final line in lines) {
        if (line.trim().isEmpty) continue;

        final data = jsonDecode(line) as Map<String, dynamic>;

        if (data['done'] == true) {
          break;
        }

        final token = data['response'] as String?;
        if (token != null) {
          yield token;
        }
      }
    } on SocketException {
      if (!_isCancelled) {
        throw AiServiceException('Could not connect to Ollama.');
      }
    } on http.ClientException {
      if (!_isCancelled) {
        throw AiServiceException('Could not connect to Ollama.');
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
