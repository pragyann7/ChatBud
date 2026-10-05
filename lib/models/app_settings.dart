import 'package:isar/isar.dart';

part 'app_settings.g.dart';

@collection
class AppSettings {
  Id id;
  final String theme;
  final String? selectedModel;
  final String? serverIp;
  final String engineType; // 'ollama' or 'llama_cpp'
  final String? modelPath; // Path to local .gguf file
  final int cpuThreads; // Default: 4 CPU threads
  final int contextSize; // Default: 2048 token window
  final int batchSize; // Default: 512 tokens

  AppSettings({
    this.id = 1,
    this.theme = 'system',
    this.selectedModel,
    this.serverIp = '192.168.1.74',
    this.engineType = 'ollama',
    this.modelPath,
    this.cpuThreads = 4,
    this.contextSize = 2048,
    this.batchSize = 512,
  });

  AppSettings copyWith({
    Id? id,
    String? theme,
    String? selectedModel,
    bool clearSelectedModel = false,
    String? serverIp,
    String? engineType,
    String? modelPath,
    bool clearModelPath = false,
    int? cpuThreads,
    int? contextSize,
    int? batchSize,
  }) {
    return AppSettings(
      id: id ?? this.id,
      theme: theme ?? this.theme,
      selectedModel:
          clearSelectedModel ? null : (selectedModel ?? this.selectedModel),
      serverIp: serverIp ?? this.serverIp,
      engineType: engineType ?? this.engineType,
      modelPath: clearModelPath ? null : (modelPath ?? this.modelPath),
      cpuThreads: cpuThreads ?? this.cpuThreads,
      contextSize: contextSize ?? this.contextSize,
      batchSize: batchSize ?? this.batchSize,
    );
  }
}
