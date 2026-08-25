import 'package:flutter_test/flutter_test.dart';
import 'package:relay_chat/main.dart';

void main() {
  testWidgets('RelayChatApp splash smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RelayChatApp());
    expect(find.text('RelayChat'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}
