import 'package:flutter_test/flutter_test.dart';
import 'package:chatbud/main.dart';
import 'package:chatbud/models/conversation.dart';
import 'package:chatbud/repositories/chat_repository.dart';
import 'package:provider/provider.dart';

class _FakeChatRepository implements ChatRepository {
  @override
  Stream<List<Conversation>> watchConversations() => Stream.value([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      Provider<ChatRepository>.value(
        value: _FakeChatRepository(),
        child: const MyApp(),
      ),
    );

    expect(find.text('ChatBud'), findsWidgets);
  });
}
