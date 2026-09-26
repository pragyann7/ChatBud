import 'package:isar/isar.dart';

part 'app_settings.g.dart';

@collection
class AppSettings {
  Id id;
  final String theme;
  final String? selectedModel;

  AppSettings({
    this.id = 1,
    this.theme = 'system',
    this.selectedModel,
  });

  AppSettings copyWith({
    Id? id,
    String? theme,
    String? selectedModel,
    bool clearSelectedModel = false,
  }) {
    return AppSettings(
      id: id ?? this.id,
      theme: theme ?? this.theme,
      selectedModel:
          clearSelectedModel ? null : (selectedModel ?? this.selectedModel),
    );
  }
}
