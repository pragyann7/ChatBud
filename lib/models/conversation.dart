import 'package:isar/isar.dart';

part 'conversation.g.dart';

@collection
class Conversation{
  Id id = Isar.autoIncrement;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? budId;

  Conversation({
    this.id = Isar.autoIncrement,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.budId,
});
}