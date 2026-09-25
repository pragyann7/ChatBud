import 'package:isar/isar.dart';
import 'package:chatbud/models/conversation.dart';
import 'package:chatbud/models/message.dart';

class ChatRepository {
  final Isar isar;

  ChatRepository(this.isar);

  Future<int> saveConversation(Conversation conversation) async {
    return await isar.writeTxn(() async {
      return await isar.conversations.put(conversation);
    });
  }

  Future<List<Conversation>> getConversations() async {
    return await isar.conversations.where().sortByUpdatedAtDesc().findAll();
  }

  Future<Conversation?> getConversation(int id) async {
    return await isar.conversations.get(id);
  }

  Future<Conversation> createNewConversation([String title = "New Chat"]) async {
    final newConv = Conversation(
      title: title,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final id = await saveConversation(newConv);
    final saved = await getConversation(id);
    return saved ?? newConv;
  }

  Future<int> saveMessageAndTouchConversation(Message message) async {
    return await isar.writeTxn(() async {
      final msgId = await isar.messages.put(message);
      message.id = msgId;
      final conv = await isar.conversations.get(message.conversationId);
      if (conv != null) {
        final updatedConv = Conversation(
          id: conv.id,
          title: conv.title,
          createdAt: conv.createdAt,
          updatedAt: DateTime.now(),
          budId: conv.budId,
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
      );
      final persistedAssistantMessage = Message(
        conversationId: conversationId,
        text: assistantMessage.text,
        role: assistantMessage.role,
        status: assistantMessage.status,
        createdAt: assistantMessage.createdAt,
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

  Stream<List<Conversation>> watchConversations() {
    return isar.conversations.where().sortByUpdatedAtDesc().watch(fireImmediately: true);
  }

  Stream<List<Message>> watchMessagesForConversation(int conversationId) {
    return isar.messages
        .filter()
        .conversationIdEqualTo(conversationId)
        .sortByCreatedAt()
        .watch(fireImmediately: true);
  }
}
