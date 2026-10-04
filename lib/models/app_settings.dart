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

  AppSettings({
    this.id = 1,
    this.theme = 'system',
    this.selectedModel,
    this.serverIp = '192.168.1.74',
    this.engineType = 'ollama',
    this.modelPath,
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
  }) {
    return AppSettings(
      id: id ?? this.id,
      theme: theme ?? this.theme,
      selectedModel:
          clearSelectedModel ? null : (selectedModel ?? this.selectedModel),
      serverIp: serverIp ?? this.serverIp,
      engineType: engineType ?? this.engineType,
      modelPath: clearModelPath ? null : (modelPath ?? this.modelPath),
    );
  }
}
