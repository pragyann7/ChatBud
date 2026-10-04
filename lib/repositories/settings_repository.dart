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
      serverIp: '192.168.1.74',
      engineType: 'ollama',
    );
    await saveSettings(defaultSettings);
    return defaultSettings;
  }

  Future<void> saveSettings(AppSettings settings) async {
    final settingsToSave = AppSettings(
      id: _settingsId, // Enforce fixed ID 1
      theme: settings.theme,
      selectedModel: settings.selectedModel,
      serverIp: settings.serverIp,
      engineType: settings.engineType,
      modelPath: settings.modelPath,
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
    await saveSettings(
      current.copyWith(
        selectedModel: newModel,
        clearSelectedModel: newModel == null,
      ),
    );
  }

  Future<void> updateServerIp(String ip) async {
    final current = await getSettings();
    await saveSettings(current.copyWith(serverIp: ip.trim()));
  }

  Future<void> updateEngineType(String engine) async {
    final current = await getSettings();
    await saveSettings(current.copyWith(engineType: engine));
  }

  Future<void> updateModelPath(String? path) async {
    final current = await getSettings();
    await saveSettings(
      current.copyWith(
        modelPath: path,
        clearModelPath: path == null || path.trim().isEmpty,
      ),
    );
  }
}
