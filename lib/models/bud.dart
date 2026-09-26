import 'package:isar/isar.dart';

part 'bud.g.dart';

@collection
class Bud {
  Id id;
  final String name;
  final String systemPrompt;
  final String iconName;
  final bool isDefault;

  Bud({
    this.id = Isar.autoIncrement,
    required this.name,
    required this.systemPrompt,
    this.iconName = 'smart_toy',
    this.isDefault = false,
  });

  Bud copyWith({
    Id? id,
    String? name,
    String? systemPrompt,
    String? iconName,
    bool? isDefault,
  }) {
    return Bud(
      id: id ?? this.id,
      name: name ?? this.name,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      iconName: iconName ?? this.iconName,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
