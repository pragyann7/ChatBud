import 'package:isar/isar.dart';
import 'package:chatbud/models/conversation.dart';
import 'package:chatbud/models/message.dart';

class MessageRepository {
  final Isar isar;

  MessageRepository(this.isar);

  Future<int> saveMessageAndTouchConversation(Message message) async {
    return await isar.writeTxn(() async {
      final msgId = await isar.messages.put(message);
      message.id = msgId;
      final conv = await isar.conversations.get(message.conversationId);
      if (conv != null) {
        final updatedConv = conv.copyWith(
          updatedAt: DateTime.now(),
        );
        await isar.conversations.put(updatedConv);
      }
      return msgId;
    });
  }

  Future<List<Message>> saveMessagePairAndTouchConversation({
    required Conversation conversation,
    required Message userMessage,
    required Message assistantMessage,
  }) async {
    return isar.writeTxn(() async {
      final conversationId = await isar.conversations.put(conversation);
      conversation.id = conversationId;
      final persistedUserMessage = Message(
        conversationId: conversationId,
        text: userMessage.text,
        role: userMessage.role,
        status: userMessage.status,
        createdAt: userMessage.createdAt,
        budId: userMessage.budId,
      );
      final persistedAssistantMessage = Message(
        conversationId: conversationId,
        text: assistantMessage.text,
        role: assistantMessage.role,
        status: assistantMessage.status,
        createdAt: assistantMessage.createdAt,
        budId: assistantMessage.budId,
      );
      persistedUserMessage.id = await isar.messages.put(persistedUserMessage);
      persistedAssistantMessage.id =
          await isar.messages.put(persistedAssistantMessage);
      return [persistedUserMessage, persistedAssistantMessage];
    });
  }

  Future<List<Message>> getMessagesForConversation(int conversationId) async {
    return await isar.messages
        .filter()
        .conversationIdEqualTo(conversationId)
        .sortByCreatedAt()
        .findAll();
  }

  Stream<List<Message>> watchMessagesForConversation(int conversationId) {
    return isar.messages
        .filter()
        .conversationIdEqualTo(conversationId)
        .sortByCreatedAt()
        .watch(fireImmediately: true);
  }

  Future<void> deleteMessagesForConversation(int conversationId) async {
    await isar.writeTxn(() async {
      await isar.messages
          .filter()
          .conversationIdEqualTo(conversationId)
          .deleteAll();
    });
  }
}
