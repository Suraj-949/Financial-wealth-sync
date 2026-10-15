import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wealthsync/app/app.dart';

void main() {
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