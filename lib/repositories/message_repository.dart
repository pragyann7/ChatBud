import 'package:isar/isar.dart';
import 'package:chatbud/models/conversation.dart';
import 'package:chatbud/models/message.dart';

class MessageRepository {
  final Isar isar;

  MessageRepository(this.isar);

  Future<int?> saveMessageAndTouchConversation(Message message) async {
    return await isar.writeTxn(() async {
      // Verify parent conversation exists inside transaction
      final conv = await isar.conversations.get(message.conversationId);
      if (conv == null) {
        // Parent conversation was deleted mid-generation! Abort saving message.
        return null;
      }
      final msgId = await isar.messages.put(message);
      message.id = msgId;

      final updatedConv = conv.copyWith(
        updatedAt: DateTime.now(),
      );
      await isar.conversations.put(updatedConv);
      return msgId;
    });
  }

  Future<List<Message>?> saveMessagePairAndTouchConversation({
    required Conversation conversation,
    required Message userMessage,
    required Message assistantMessage,
  }) async {
    return isar.writeTxn(() async {
      // If conversation has a persisted ID, verify it wasn't deleted mid-save
      if (conversation.id > 0 && conversation.id != Isar.autoIncrement) {
        final existing = await isar.conversations.get(conversation.id);
        if (existing == null) {
          // Parent conversation was deleted right before message pair save! Abort.
          return null;
        }
      }

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
    final messages = await isar.messages
        .filter()
        .conversationIdEqualTo(conversationId)
        .sortByCreatedAt()
        .findAll();

    // Deterministic tie-breaking sort by ID
    messages.sort((a, b) {
      final cmp = a.createdAt.compareTo(b.createdAt);
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    });
    return messages;
  }

  Future<List<Message>> getMessagesForConversationPaginated(
    int conversationId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final messages = await isar.messages
        .filter()
        .conversationIdEqualTo(conversationId)
        .sortByCreatedAt()
        .offset(offset)
        .limit(limit)
        .findAll();

    // Deterministic tie-breaking sort by ID
    messages.sort((a, b) {
      final cmp = a.createdAt.compareTo(b.createdAt);
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    });
    return messages;
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
