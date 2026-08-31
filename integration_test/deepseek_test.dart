import 'package:ai_advent_day_01/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows a real DeepSeek response', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.enterText(
      find.byType(TextField),
      'Reply with exactly this text and nothing else: ADVENT_OK_731',
    );
    await tester.tap(find.text('Отправить'));

    for (var attempt = 0; attempt < 60; attempt++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.textContaining('ADVENT_OK_731').evaluate().isNotEmpty) break;
    }

    expect(find.textContaining('ADVENT_OK_731'), findsOneWidget);
  });
}
