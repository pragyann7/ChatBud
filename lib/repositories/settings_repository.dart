import 'package:isar/isar.dart';
import 'package:chatbud/models/app_settings.dart';

class SettingsRepository {
  final Isar isar;

  SettingsRepository(this.isar);

  Future<AppSettings> getSettings() async {
    final settings = await isar.appSettings.get(1);
    if (settings != null) return settings;

    final defaultSettings = AppSettings(
      id: 1,
      theme: 'system',
    );
    await isar.writeTxn(() async {
      await isar.appSettings.put(defaultSettings);
    });
    return defaultSettings;
  }

  Stream<AppSettings?> watchSettings() {
    return isar.appSettings.watchObject(1, fireImmediately: true);
  }

  Future<void> setSelectedBudId(int budId) async {
    final current = await getSettings();
    final updated = AppSettings(
      id: 1,
      theme: current.theme,
      selectedBudId: budId,
      selectedModel: current.selectedModel,
    );
    await isar.writeTxn(() async {
      await isar.appSettings.put(updated);
    });
  }
}
