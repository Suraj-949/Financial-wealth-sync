import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wealthsync/models/models.dart';
import 'package:wealthsync/screens/dashboard/widgets/dashboard_sections.dart';
import 'package:wealthsync/services/finance_repository.dart';
import 'package:wealthsync/utils/formatters.dart';

/// Renders [PredictionCard] with [data] and returns the pump handle.
Future<void> _pump(WidgetTester tester, DashboardData data) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: PredictionCard(data: data)),
        ),
      ),
    ),
  );
}

Future<DashboardData> _mockDashboard() async {
  final repo = MockFinanceRepository()..setDelay(0);
  return repo.fetchDashboard();
}

void main() {
  testWidgets('shows the real ML forecast when the model responded',
      (tester) async {
    final data = (await _mockDashboard()).copyWith(
      mlPrediction: const SpendingPrediction(
        predictedSpending: 15516.58,
        currency: 'USD',
        unit: 'dollars',
        note: 'Predicted next-quarter total expenditure in USD',
      ),
    );

    await _pump(tester, data);

    expect(find.text('Model Forecast · Next Quarter'), findsOneWidget);
    // Rendered in the currency the model actually forecasts, not forced to ₹.
    expect(find.text(r'$15,516.58'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);
    expect(
        find.text('Predicted next-quarter total expenditure in USD'), findsOneWidget);

    // Mock (monthly, INR) values must not be shown alongside the real forecast.
    expect(find.text('Predicted Expenses · Next Month'), findsNothing);
    expect(find.text(Formatters.inr(45500.0)), findsNothing);
  });

  testWidgets('falls back to the mock monthly trend without a forecast',
      (tester) async {
    await _pump(tester, await _mockDashboard());

    expect(find.text('Model Forecast · Next Quarter'), findsNothing);
    expect(find.text('Predicted Expenses · Next Month'), findsOneWidget);
    expect(find.text(Formatters.inr(45500.0)), findsOneWidget);
  });
}
