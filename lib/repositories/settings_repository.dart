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
      cpuThreads: 4,
      contextSize: 2048,
      batchSize: 512,
    );
    return isar.writeTxn(() async {
      final existing = await isar.appSettings.get(_settingsId);
      if (existing != null) return existing;
      await isar.appSettings.put(defaultSettings);
      return defaultSettings;
    });
  }

  Future<void> saveSettings(AppSettings settings) async {
    _validate(settings);
    final settingsToSave = AppSettings(
      id: _settingsId, // Enforce fixed ID 1
      theme: settings.theme,
      selectedModel: settings.selectedModel,
      serverIp: settings.serverIp,
      engineType: settings.engineType,
      modelPath: settings.modelPath,
      cpuThreads: settings.cpuThreads,
      contextSize: settings.contextSize,
      batchSize: settings.batchSize,
    );
    await isar.writeTxn(() async {
      await isar.appSettings.put(settingsToSave);
    });
  }

  Stream<AppSettings?> watchSettings() {
    return isar.appSettings.watchObject(_settingsId, fireImmediately: true);
  }

  Future<void> updateTheme(String newTheme) async {
    await _update((current) => current.copyWith(theme: newTheme));
  }

  Future<void> updateSelectedModel(String? newModel) async {
    await _update(
      (current) => current.copyWith(
        selectedModel: newModel,
        clearSelectedModel: newModel == null,
      ),
    );
  }

  Future<void> updateServerIp(String ip) async {
    await _update((current) => current.copyWith(serverIp: ip.trim()));
  }

  Future<void> updateEngineType(String engine) async {
    if (engine != 'ollama' && engine != 'llama_cpp') {
      throw ArgumentError.value(engine, 'engine');
    }
    await _update((current) => current.copyWith(engineType: engine));
  }

  Future<void> updateModelPath(String? path) async {
    await _update(
      (current) => current.copyWith(
        modelPath: path,
        clearModelPath: path == null || path.trim().isEmpty,
      ),
    );
  }

  Future<void> updateInferenceParams({
    int? cpuThreads,
    int? contextSize,
    int? batchSize,
  }) async {
    if (cpuThreads != null && (cpuThreads < 1 || cpuThreads > 64)) {
      throw RangeError.range(cpuThreads, 1, 64, 'cpuThreads');
    }
    if (contextSize != null && (contextSize < 256 || contextSize > 131072)) {
      throw RangeError.range(contextSize, 256, 131072, 'contextSize');
    }
    if (batchSize != null && (batchSize < 32 || batchSize > 4096)) {
      throw RangeError.range(batchSize, 32, 4096, 'batchSize');
    }
    await _update(
      (current) => current.copyWith(
        cpuThreads: cpuThreads,
        contextSize: contextSize,
        batchSize: batchSize,
      ),
    );
  }

  Future<void> _update(AppSettings Function(AppSettings) update) async {
    await isar.writeTxn(() async {
      final current =
          await isar.appSettings.get(_settingsId) ??
          AppSettings(
            id: _settingsId,
            theme: 'system',
            serverIp: '192.168.1.74',
            engineType: 'ollama',
            cpuThreads: 4,
            contextSize: 2048,
            batchSize: 512,
          );
      final updated = update(current);
      _validate(updated);
      await isar.appSettings.put(
        AppSettings(
          id: _settingsId,
          theme: updated.theme,
          selectedModel: updated.selectedModel,
          serverIp: updated.serverIp,
          engineType: updated.engineType,
          modelPath: updated.modelPath,
          cpuThreads: updated.cpuThreads,
          contextSize: updated.contextSize,
          batchSize: updated.batchSize,
        ),
      );
    });
  }

  void _validate(AppSettings settings) {
    if (!const {'system', 'light', 'dark'}.contains(settings.theme)) {
      throw ArgumentError.value(settings.theme, 'theme');
    }
    if (settings.engineType != 'ollama' &&
        settings.engineType != 'llama_cpp') {
      throw ArgumentError.value(settings.engineType, 'engineType');
    }
    if (settings.cpuThreads < 1 || settings.cpuThreads > 64) {
      throw RangeError.range(settings.cpuThreads, 1, 64, 'cpuThreads');
    }
    if (settings.contextSize < 256 || settings.contextSize > 131072) {
      throw RangeError.range(settings.contextSize, 256, 131072, 'contextSize');
    }
    if (settings.batchSize < 32 || settings.batchSize > 4096) {
      throw RangeError.range(settings.batchSize, 32, 4096, 'batchSize');
    }
  }
}
