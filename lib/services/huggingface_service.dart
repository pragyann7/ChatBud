import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:chatbud/models/hugging_face_model.dart';

typedef DownloadProgressCallback = void Function(
  int receivedBytes,
  int totalBytes,
);

class HuggingFaceService extends ChangeNotifier {
  static final HuggingFaceService _instance = HuggingFaceService._internal();
  factory HuggingFaceService() => _instance;
  HuggingFaceService._internal();

  final http.Client _client = http.Client();
  final Map<String, Future<File>> _downloadTasks = {};

  // Persistent Download State Tracking across screens
  final Map<String, double> activeDownloadProgress = {};
  final Map<String, String> activeDownloadStatusText = {};
  final Set<String> activeCancelledDownloads = {};
  final Map<String, HttpClientRequest> _activeRequests = {};

  bool isDownloading(String fileName) =>
      activeDownloadProgress.containsKey(fileName);

  double getProgress(String fileName) =>
      activeDownloadProgress[fileName] ?? 0.0;

  String getStatusText(String fileName) =>
      activeDownloadStatusText[fileName] ?? '';

  void cancelDownload(String fileName) {
    activeCancelledDownloads.add(fileName);
    _activeRequests.remove(fileName)?.abort();
    activeDownloadProgress.remove(fileName);
    activeDownloadStatusText.remove(fileName);
    notifyListeners();
  }

  static const List<PresetModel> recommendedModels = [
    PresetModel(
      title: "Qwen 2.5 0.5B Instruct",
      description:
          "Super fast, lightweight 0.5B model. Perfect for all mobile devices.",
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
      description:
          "On-device reasoning model with live <think> thought process stream.",
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
      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception(
          'Hugging Face API returned HTTP ${response.statusCode}',
        );
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
    final cleanRepo = _validatedRepoId(repoId);
    final encodedRepo = cleanRepo.split('/').map(Uri.encodeComponent).join('/');
    final url = Uri.https(
      'huggingface.co',
      '/api/models/$encodedRepo/tree/main',
    );

    try {
      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to load repo files: HTTP ${response.statusCode}',
        );
      }

      final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
      final List<GgufFile> ggufFiles = [];

      for (final item in jsonList) {
        if (item is Map<String, dynamic>) {
          final String path = item['path'] as String? ?? '';
          final String type = item['type'] as String? ?? '';
          final int size = item['size'] as int? ?? 0;

          if (type == 'file' && path.toLowerCase().endsWith('.gguf')) {
            final encodedPath = path
                .split('/')
                .map(Uri.encodeComponent)
                .join('/');
            final downloadUrl =
                'https://huggingface.co/$encodedRepo/resolve/main/$encodedPath';
            final localName =
                '${cleanRepo.replaceAll('/', '_')}_${path.split('/').last}';
            ggufFiles.add(
              GgufFile(
                fileName: localName,
                downloadUrl: downloadUrl,
                sizeBytes: size,
              ),
            );
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
  }) {
    final task = _downloadTasks[fileName];
    if (task != null) return task;
    final safeName = _safeFileName(fileName);
    final future = _startDownload(
      downloadUrl: downloadUrl,
      fileName: safeName,
      progressKey: fileName,
    );
    _downloadTasks[fileName] = future;
    return future.whenComplete(() => _downloadTasks.remove(fileName));
  }

  Future<File> _startDownload({
    required String downloadUrl,
    required String fileName,
    required String progressKey,
  }) async {
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'huggingface.co' ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        downloadUrl,
        'downloadUrl',
        'Only HTTPS downloads from huggingface.co are accepted.',
      );
    }

    activeCancelledDownloads.remove(progressKey);
    activeDownloadProgress[progressKey] = 0.001;
    activeDownloadStatusText[progressKey] = 'Starting download…';
    notifyListeners();

    try {
      final file = await downloadGgufFile(
        downloadUrl: downloadUrl,
        fileName: fileName,
        cancellationKey: progressKey,
        isCancelled: () => activeCancelledDownloads.contains(progressKey),
        onProgress: (received, total) {
          if (!activeCancelledDownloads.contains(progressKey)) {
            if (total > 0) {
              final progress = received / total;
              final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
              final totMb = (total / (1024 * 1024)).toStringAsFixed(1);
              activeDownloadProgress[progressKey] = progress;
              activeDownloadStatusText[progressKey] = '$recMb MB / $totMb MB';
            } else {
              final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
              activeDownloadStatusText[progressKey] = '$recMb MB downloaded';
            }
            notifyListeners();
          }
        },
      );

      activeDownloadProgress.remove(progressKey);
      activeDownloadStatusText.remove(progressKey);
      notifyListeners();
      return file;
    } catch (e) {
      activeDownloadProgress.remove(progressKey);
      activeDownloadStatusText.remove(progressKey);
      notifyListeners();
      rethrow;
    }
  }

  Future<File> downloadGgufFile({
    required String downloadUrl,
    required String fileName,
    String? cancellationKey,
    required DownloadProgressCallback onProgress,
    required bool Function() isCancelled,
  }) async {
    fileName = _safeFileName(fileName);
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'huggingface.co' ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        downloadUrl,
        'downloadUrl',
        'Only HTTPS downloads from huggingface.co are accepted.',
      );
    }
    final modelsDirPath = await getModelsDirectoryPath();
    final destinationFile = File('$modelsDirPath/$fileName');
    final tempFile = File('$modelsDirPath/$fileName.tmp');
    final requestKey = cancellationKey ?? fileName;

    if (await destinationFile.exists()) {
      if (await _hasGgufHeader(destinationFile)) return destinationFile;
      await destinationFile.delete();
    }

    final ioClient = HttpClient();
    ioClient.connectionTimeout = const Duration(seconds: 20);

    try {
      final request = await ioClient.getUrl(Uri.parse(downloadUrl));
      _activeRequests[requestKey] = request;
      if (isCancelled()) {
        request.abort();
        throw Exception('DOWNLOAD_CANCELLED');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );

      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      var receivedBytes = 0;

      final sink = tempFile.openWrite();

      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
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

        if (totalBytes > 0 && receivedBytes != totalBytes) {
          throw Exception(
            'Incomplete model download ($receivedBytes of $totalBytes bytes).',
          );
        }

        if (!await _hasGgufHeader(tempFile)) {
          throw Exception('Downloaded file is not a valid GGUF model.');
        }

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
      _activeRequests.remove(requestKey);
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

  String _validatedRepoId(String repoId) {
    final value = repoId.trim();
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(value)) {
      throw ArgumentError.value(
        repoId,
        'repoId',
        'Invalid Hugging Face repo ID.',
      );
    }
    return value;
  }

  String _safeFileName(String fileName) {
    final baseName = fileName.replaceAll('\\', '/').split('/').last;
    final safe = baseName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.isEmpty ||
        safe == '.' ||
        safe == '..' ||
        !safe.toLowerCase().endsWith('.gguf')) {
      throw ArgumentError.value(fileName, 'fileName', 'Invalid GGUF filename.');
    }
    return safe;
  }

  Future<bool> _hasGgufHeader(File file) async {
    if (await file.length() < 1024 * 1024) return false;
    final handle = await file.open();
    try {
      final header = await handle.read(4);
      return header.length == 4 &&
          header[0] == 0x47 &&
          header[1] == 0x47 &&
          header[2] == 0x55 &&
          header[3] == 0x46;
    } finally {
      await handle.close();
    }
  }
}
