import 'package:ai_advent_day_01/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows prompt input and send button', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('DeepSeek Chat'), findsOneWidget);
    expect(find.text('Ваш prompt'), findsOneWidget);
    expect(find.text('Отправить'), findsOneWidget);
    expect(find.text('Здесь появится ответ DeepSeek.'), findsOneWidget);
  });

  testWidgets('explains how to provide a missing API key', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.enterText(find.byType(TextField), 'Привет');
    await tester.tap(find.text('Отправить'));
    await tester.pump();

    expect(find.textContaining('API key не найден'), findsOneWidget);
  });
}
