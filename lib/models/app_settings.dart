import 'package:isar/isar.dart';

part 'app_settings.g.dart';

@collection
class AppSettings {
  Id id = 1;
  final String theme;
  final int? selectedBudId;
  final String? selectedModel;

  AppSettings({
    this.id = 1,
    required this.theme,
    this.selectedBudId,
    this.selectedModel,
  });
}