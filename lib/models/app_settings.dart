import 'package:isar/isar.dart';

part 'app_settings.g.dart';

@collection
class AppSettings {
  Id id;
  final String theme;
  final String? selectedModel;
  final String? serverIp;

  AppSettings({
    this.id = 1,
    this.theme = 'system',
    this.selectedModel,
    this.serverIp = '192.168.1.74',
  });

  AppSettings copyWith({
    Id? id,
    String? theme,
    String? selectedModel,
    bool clearSelectedModel = false,
    String? serverIp,
  }) {
    return AppSettings(
      id: id ?? this.id,
      theme: theme ?? this.theme,
      selectedModel:
          clearSelectedModel ? null : (selectedModel ?? this.selectedModel),
      serverIp: serverIp ?? this.serverIp,
    );
  }
}
