import 'package:isar/isar.dart';
import 'package:chatbud/models/conversation.dart';
import 'package:chatbud/models/message.dart';

class ConversationRepository {
  final Isar isar;

  ConversationRepository(this.isar);

  Future<int> saveConversation(Conversation conversation) async {
    return await isar.writeTxn(() async {
      return await isar.conversations.put(conversation);
    });
  }

  Future<void> togglePinConversation(Conversation conversation) async {
    await isar.writeTxn(() async {
      final updatedConv = conversation.copyWith(
        isPinned: !conversation.isPinned,
      );
      await isar.conversations.put(updatedConv);
    });
  }

  Future<void> renameConversation(
      Conversation conversation, String newTitle) async {
    await isar.writeTxn(() async {
      final updatedConv = conversation.copyWith(
        title: newTitle,
        updatedAt: DateTime.now(),
      );
      await isar.conversations.put(updatedConv);
    });
  }

  Future<bool> deleteConversation(int conversationId) async {
    return await isar.writeTxn(() async {
      // Delete all messages belonging to this conversation
      await isar.messages
          .filter()
          .conversationIdEqualTo(conversationId)
          .deleteAll();

      // Delete the conversation record
      return await isar.conversations.delete(conversationId);
    });
  }

  Future<List<Conversation>> getConversations() async {
    return await isar.conversations
        .where()
        .sortByIsPinnedDesc()
        .thenByUpdatedAtDesc()
        .findAll();
  }

  Future<Conversation?> getConversation(int id) async {
    return await isar.conversations.get(id);
  }

  Future<Conversation> createNewConversation({
    String title = "New Chat",
    int? budId,
  }) async {
    final newConv = Conversation(
      title: title,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      budId: budId,
    );
    final id = await saveConversation(newConv);
    final saved = await getConversation(id);
    return saved ?? newConv;
  }

  Stream<List<Conversation>> watchConversations() {
    return isar.conversations
        .where()
        .sortByIsPinnedDesc()
        .thenByUpdatedAtDesc()
        .watch(fireImmediately: true)
        .asBroadcastStream();
  }
}
