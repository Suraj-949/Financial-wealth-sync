import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wealthsync/main.dart';
import 'package:wealthsync/services/finance_repository.dart';

void main() {
  setUpAll(() {
    // Remove artificial latency so the widget test does not flake.
    (getRepository() as MockFinanceRepository).setDelay(0);
  });

  testWidgets('WealthSync app boots to the dashboard shell', (tester) async {
    await tester.pumpWidget(const WealthSyncApp());

    // Guard against the animation-heavy skeleton: pump past it with fixed frames.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('dashboard renders financial summary after load', (tester) async {
    await tester.pumpWidget(const WealthSyncApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('Financial Summary'), findsOneWidget);
  });
}