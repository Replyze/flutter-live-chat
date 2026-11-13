import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:replyze_flutter_example/main.dart';

void main() {
  testWidgets('the home screen shows the Support button', (tester) async {
    // Only the home screen: the chat itself needs a real WebView.
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('Sign in as Ana'), findsOneWidget);
  });
}
