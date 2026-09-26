import 'package:isar/isar.dart';
import 'package:chatbud/models/app_settings.dart';

class SettingsRepository {
  final Isar isar;

  static const int _settingsId = 1;

  SettingsRepository(this.isar);

  Future<AppSettings> getSettings() async {
    final settings = await isar.appSettings.get(_settingsId);
    if (settings != null) return settings;

    final defaultSettings = AppSettings(
      id: _settingsId,
      theme: 'system',
    );
    await saveSettings(defaultSettings);
    return defaultSettings;
  }

  Future<void> saveSettings(AppSettings settings) async {
    final settingsToSave = AppSettings(
      id: _settingsId, // Enforce fixed ID 1
      theme: settings.theme,
      selectedModel: settings.selectedModel,
    );
    await isar.writeTxn(() async {
      await isar.appSettings.put(settingsToSave);
    });
  }

  Stream<AppSettings?> watchSettings() {
    return isar.appSettings.watchObject(_settingsId, fireImmediately: true);
  }

  Future<void> updateTheme(String newTheme) async {
    final current = await getSettings();
    await saveSettings(current.copyWith(theme: newTheme));
  }

  Future<void> updateSelectedModel(String? newModel) async {
    final current = await getSettings();
    await saveSettings(current.copyWith(selectedModel: newModel));
  }
}
