import 'package:isar/isar.dart';

part 'bud.g.dart';

@collection
class Bud {
  Id id = Isar.autoIncrement;
  final String name;
  final String systemPrompt;

  Bud({
    this.id = Isar.autoIncrement,
    required this.name,
    required this.systemPrompt,
});
}