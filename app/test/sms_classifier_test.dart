import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wealthsync/screens/sms/sms_classifier_screen.dart';
import 'package:wealthsync/services/finance_repository.dart';

/// Pumps the screen with an offline mock repository (no network).
Future<void> _pump(WidgetTester tester) async {
  final repo = MockFinanceRepository()..setDelay(0);
  await tester.pumpWidget(MaterialApp(home: SmsClassifierScreen(repository: repo)));
}

Future<void> _classify(WidgetTester tester, String sms) async {
  await tester.enterText(find.byType(TextField), sms);
  final button = find.text('Classify');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('approves a credit SMS and labels it credit', (tester) async {
    await _pump(tester);
    await _classify(tester, 'Your bank account XX445 has been credited with USD 120.00.');

    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Credit'), findsWidgets);
    expect(find.text('Discarded'), findsNothing);
  });

  testWidgets('labels a spend SMS as debit', (tester) async {
    await _pump(tester);
    await _classify(tester, 'You spent USD 4.50 at McDonalds.');

    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Debit'), findsWidgets);
  });

  testWidgets('discards a spam SMS', (tester) async {
    await _pump(tester);
    await _classify(tester, r'Congratulations! You won a lottery of $1,000,000! Call now.');

    expect(find.text('Discarded'), findsOneWidget);
    expect(find.text('Spam / Noise'), findsOneWidget);
    expect(find.text('Approved'), findsNothing);
  });

  testWidgets('shows no result until the first classify', (tester) async {
    await _pump(tester);
    expect(find.text('Approved'), findsNothing);
    expect(find.text('Discarded'), findsNothing);
  });
}
