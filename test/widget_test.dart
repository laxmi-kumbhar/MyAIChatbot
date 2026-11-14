import 'package:flutter_test/flutter_test.dart';
import 'package:my_ai_chatbot/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App renders successfully smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MyAIChatbotApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('MyAIChatbot'), findsWidgets);
  });
}
