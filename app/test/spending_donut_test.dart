import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wealthsync/models/models.dart';
import 'package:wealthsync/screens/dashboard/widgets/charts.dart';
import 'package:wealthsync/utils/formatters.dart';

const _categories = <SpendingCategory>[
  SpendingCategory(category: TxnCategory.shopping, amount: 1200.0, pct: 30.0),
  SpendingCategory(category: TxnCategory.food, amount: 900.0, pct: 22.0),
  SpendingCategory(category: TxnCategory.bills, amount: 700.0, pct: 17.0),
  SpendingCategory(category: TxnCategory.transport, amount: 500.0, pct: 12.0),
  SpendingCategory(category: TxnCategory.entertainment, amount: 400.0, pct: 10.0),
  SpendingCategory(category: TxnCategory.others, amount: 300.0, pct: 9.0),
];

const _total = 4000.0;

typedef _TouchCallback = void Function(FlTouchEvent, PieTouchResponse?);

/// Renders [SpendingDonut] and returns the touch callback registered on the
/// underlying [PieChart], so tests can simulate what fl_chart reports.
Future<_TouchCallback> _pumpDonut(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: SpendingDonut(categories: _categories, total: _total)),
    ),
  );

  final chart = tester.widget<PieChart>(find.byType(PieChart));
  final callback = chart.data.pieTouchData.touchCallback;
  expect(callback, isNotNull, reason: 'donut should register a touch callback');
  return callback!;
}

/// The amount shown in the middle of the donut. It is the only text styled at
/// 19px (the legend renders at 13/13.5px), so it identifies the selected state.
String _centerAmount(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).firstWhere((t) => t.style?.fontSize == 19).data ??
    '';

/// Mimics fl_chart reporting a touch that did not land on any section
/// (tapped inside the donut hole) - it passes `-1` as the section index.
PieTouchResponse _responseWithIndex(int sectionIndex) => PieTouchResponse(
      touchLocation: Offset.zero,
      touchedSection: PieTouchedSection(
        PieChartSectionData(value: 100.0),
        sectionIndex,
        0,
        0,
      ),
    );

void main() {
  group('safeSectionIndex', () {
    test("maps fl_chart's -1 (touched no section) to null", () {
      expect(safeSectionIndex(-1, 6), isNull);
    });

    test('keeps indices that are in range', () {
      expect(safeSectionIndex(0, 6), 0);
      expect(safeSectionIndex(5, 6), 5);
    });

    test('rejects null and out-of-range indices', () {
      expect(safeSectionIndex(null, 6), isNull);
      expect(safeSectionIndex(6, 6), isNull);
      expect(safeSectionIndex(-1, 0), isNull);
    });
  });

  group('SpendingDonut', () {
    testWidgets('tap that hits no section keeps the total visible (regression)',
        (tester) async {
      final touchCallback = await _pumpDonut(tester);
      expect(_centerAmount(tester), Formatters.inr(_total));

      // Used to throw: RangeError (length): Not in inclusive range 0..5: -1
      touchCallback(FlTapDownEvent(TapDownDetails()), _responseWithIndex(-1));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_centerAmount(tester), Formatters.inr(_total));
      expect(find.text('Total Expenses'), findsOneWidget);
    });

    testWidgets('tap on a section selects that category', (tester) async {
      final touchCallback = await _pumpDonut(tester);

      touchCallback(FlTapDownEvent(TapDownDetails()), _responseWithIndex(2));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Centre now shows the tapped category instead of the total.
      expect(_centerAmount(tester), Formatters.inr(_categories[2].amount));
      expect(find.text('Total Expenses'), findsNothing);
    });
  });
}
