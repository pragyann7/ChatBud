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

  Future<int> saveMessage(Message message) async {
    return await isar.writeTxn(() async {
      return await isar.messages.put(message);
    });
  }

  Future<List<Message>> getMessagesForConversation(int conversationId) async {
    return await isar.messages
        .filter()
        .conversationIdEqualTo(conversationId)
        .sortByCreatedAt()
        .findAll();
  }

  Future<void> cleanUpEmptyConversations() async {
    final conversations = await getConversations();
    for (final conv in conversations) {
      final count = await isar.messages
          .filter()
          .conversationIdEqualTo(conv.id)
          .count();
      if (count == 0) {
        await isar.writeTxn(() async {
          await isar.conversations.delete(conv.id);
        });
      }
    }
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
