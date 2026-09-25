import 'package:isar/isar.dart';

part 'conversation.g.dart';

@collection
class Conversation {
  Id id = Isar.autoIncrement;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPinned;
  final int? budId;

  Conversation({
    this.id = Isar.autoIncrement,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.budId,
  });

  Conversation copyWith({
    Id? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
    int? budId,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      budId: budId ?? this.budId,
    );
  }
}
