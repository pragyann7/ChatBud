import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:chatbud/models/hugging_face_model.dart';

typedef DownloadProgressCallback = void Function(int receivedBytes, int totalBytes);

class HuggingFaceService extends ChangeNotifier {
  static final HuggingFaceService _instance = HuggingFaceService._internal();
  factory HuggingFaceService() => _instance;
  HuggingFaceService._internal();

  final http.Client _client = http.Client();

  // Persistent Download State Tracking across screens
  final Map<String, double> activeDownloadProgress = {};
  final Map<String, String> activeDownloadStatusText = {};
  final Set<String> activeCancelledDownloads = {};

  bool isDownloading(String fileName) =>
      activeDownloadProgress.containsKey(fileName);

  double getProgress(String fileName) =>
      activeDownloadProgress[fileName] ?? 0.0;

  String getStatusText(String fileName) =>
      activeDownloadStatusText[fileName] ?? '';

  void cancelDownload(String fileName) {
    activeCancelledDownloads.add(fileName);
    activeDownloadProgress.remove(fileName);
    activeDownloadStatusText.remove(fileName);
    notifyListeners();
  }

  static const List<PresetModel> recommendedModels = [
    PresetModel(
      title: "Qwen 2.5 0.5B Instruct",
      description: "Super fast, lightweight 0.5B model. Perfect for all mobile devices.",
      repoId: "Qwen/Qwen2.5-0.5B-Instruct-GGUF",
      fileName: "qwen2.5-0.5b-instruct-q4_k_m.gguf",
      downloadUrl: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf",
      sizeText: "~398 MB",
    ),
    PresetModel(
      title: "Llama 3.2 1B Instruct",
      description: "Meta's lightweight 1B model. Balanced speed and reasoning for phones.",
      repoId: "bartowski/Llama-3.2-1B-Instruct-GGUF",
      fileName: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
      downloadUrl: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf",
      sizeText: "~758 MB",
    ),
    PresetModel(
      title: "DeepSeek R1 Distill Qwen 1.5B",
      description: "On-device reasoning model with live <think> thought process stream.",
      repoId: "unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF",
      fileName: "DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf",
      downloadUrl: "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf",
      sizeText: "~1.1 GB",
    ),
    PresetModel(
      title: "Qwen 2.5 1.5B Instruct",
      description: "High capability 1.5B multilingual instruct model.",
      repoId: "Qwen/Qwen2.5-1.5B-Instruct-GGUF",
      fileName: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
      downloadUrl: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
      sizeText: "~980 MB",
    ),
  ];

  Future<String> getModelsDirectoryPath() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${docsDir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir.path;
  }

  Future<List<HuggingFaceRepo>> searchGgufModels(String query) async {
    if (query.trim().isEmpty) return [];

    final cleanQuery = Uri.encodeComponent(query.trim());
    final url = Uri.parse(
      'https://huggingface.co/api/models?search=$cleanQuery&filter=gguf&limit=25&sort=downloads',
    );

    try {
      final response = await _client.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Hugging Face API returned HTTP ${response.statusCode}');
      }

      final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
      return jsonList
          .map((item) => HuggingFaceRepo.fromJson(item as Map<String, dynamic>))
          .where((repo) => repo.id.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('Error searching Hugging Face models: $e');
      rethrow;
    }
  }

  Future<List<GgufFile>> getRepoGgufFiles(String repoId) async {
    final cleanRepo = repoId.trim();
    final url = Uri.parse('https://huggingface.co/api/models/$cleanRepo/tree/main');

    try {
      final response = await _client.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Failed to load repo files: HTTP ${response.statusCode}');
      }

      final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
      final List<GgufFile> ggufFiles = [];

      for (final item in jsonList) {
        if (item is Map<String, dynamic>) {
          final String path = item['path'] as String? ?? '';
          final String type = item['type'] as String? ?? '';
          final int size = item['size'] as int? ?? 0;

          if (type == 'file' && path.toLowerCase().endsWith('.gguf')) {
            final downloadUrl = 'https://huggingface.co/$cleanRepo/resolve/main/$path';
            ggufFiles.add(GgufFile(
              fileName: path,
              downloadUrl: downloadUrl,
              sizeBytes: size,
            ));
          }
        }
      }

      return ggufFiles;
    } catch (e) {
      debugPrint('Error fetching repo GGUF files: $e');
      rethrow;
    }
  }

  Future<File> startGgufDownload({
    required String downloadUrl,
    required String fileName,
  }) async {
    if (activeDownloadProgress.containsKey(fileName)) {
      final modelsDirPath = await getModelsDirectoryPath();
      return File('$modelsDirPath/$fileName');
    }

    activeCancelledDownloads.remove(fileName);
    activeDownloadProgress[fileName] = 0.001;
    activeDownloadStatusText[fileName] = 'Starting download…';
    notifyListeners();

    try {
      final file = await downloadGgufFile(
        downloadUrl: downloadUrl,
        fileName: fileName,
        isCancelled: () => activeCancelledDownloads.contains(fileName),
        onProgress: (received, total) {
          if (!activeCancelledDownloads.contains(fileName)) {
            if (total > 0) {
              final progress = received / total;
              final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
              final totMb = (total / (1024 * 1024)).toStringAsFixed(1);
              activeDownloadProgress[fileName] = progress;
              activeDownloadStatusText[fileName] = '$recMb MB / $totMb MB';
            } else {
              final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
              activeDownloadStatusText[fileName] = '$recMb MB downloaded';
            }
            notifyListeners();
          }
        },
      );

      activeDownloadProgress.remove(fileName);
      activeDownloadStatusText.remove(fileName);
      notifyListeners();
      return file;
    } catch (e) {
      activeDownloadProgress.remove(fileName);
      activeDownloadStatusText.remove(fileName);
      notifyListeners();
      rethrow;
    }
  }

  Future<File> downloadGgufFile({
    required String downloadUrl,
    required String fileName,
    required DownloadProgressCallback onProgress,
    required bool Function() isCancelled,
  }) async {
    final modelsDirPath = await getModelsDirectoryPath();
    final destinationFile = File('$modelsDirPath/$fileName');
    final tempFile = File('$modelsDirPath/$fileName.tmp');

    if (await destinationFile.exists()) {
      return destinationFile;
    }

    final ioClient = HttpClient();
    ioClient.connectionTimeout = const Duration(seconds: 20);

    try {
      final request = await ioClient.getUrl(Uri.parse(downloadUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      var receivedBytes = 0;

      final sink = tempFile.openWrite();

      try {
        await for (final chunk in response) {
          if (isCancelled()) {
            request.abort();
            throw Exception('DOWNLOAD_CANCELLED');
          }
          sink.add(chunk);
          receivedBytes += chunk.length;
          onProgress(receivedBytes, totalBytes);
        }
        await sink.flush();
        await sink.close();

        if (isCancelled()) {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
          throw Exception('DOWNLOAD_CANCELLED');
        }

        await tempFile.rename(destinationFile.path);
        return destinationFile;
      } catch (e) {
        await sink.close();
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        rethrow;
      }
    } finally {
      ioClient.close();
    }
  }

  Future<List<File>> getDownloadedGgufFiles() async {
    final modelsDirPath = await getModelsDirectoryPath();
    final dir = Directory(modelsDirPath);
    if (!await dir.exists()) return [];

    final files = await dir.list().toList();
    return files
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.gguf'))
        .toList();
  }

  Future<void> deleteDownloadedFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
    notifyListeners();
  }
}
