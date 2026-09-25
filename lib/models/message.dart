import 'package:isar/isar.dart';

part 'message.g.dart';

enum MessageRole {
  user,
  assistant,
  system,
}

@collection
class Message {
  Id id;
  final int conversationId;
  final String text;

  @Enumerated(EnumType.name)
  final MessageRole role;

  final DateTime createdAt;

  Message({
    this.id = Isar.autoIncrement,
    this.conversationId = 0,
    required this.text,
    required this.role,
    required this.createdAt,
  });

  bool get isUser => role == MessageRole.user;
}
