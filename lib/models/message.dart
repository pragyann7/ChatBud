import 'package:isar/isar.dart';

part 'message.g.dart';

enum MessageRole {
  user,
  assistant,
  system,
}

enum MessageStatus {
  pending,
  completed,
  failed,
}

@collection
class Message {
  Id id;

  @Index()
  final int conversationId;

  final String text;

  @Enumerated(EnumType.name)
  final MessageRole role;

  @Enumerated(EnumType.name)
  final MessageStatus status;

  @Index()
  final DateTime createdAt;

  final int? budId;

  Message({
    this.id = Isar.autoIncrement,
    required this.conversationId,
    required this.text,
    required this.role,
    this.status = MessageStatus.completed,
    required this.createdAt,
    this.budId,
  });

  bool get isUser => role == MessageRole.user;
}
