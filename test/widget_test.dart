import 'package:flutter_test/flutter_test.dart';
import 'package:chatbud/main.dart';

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that ChatBud title is displayed.
    expect(find.text('ChatBud'), findsWidgets);
  });
}
