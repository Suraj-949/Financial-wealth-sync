import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/models.dart';
import 'mock_data.dart';

/// Aggregate object returned for the dashboard screen.
///
/// [mlPrediction] is the BLS quarterly USD forecast (applied best-effort when
/// the backend is reachable, otherwise null and the mock trend is shown).
/// [inrForecast] is the INR monthly bundle (spending/savings/wellness) from
/// `POST /predict/{spending,savings,wellness}`, merged into [summary] when
/// live values arrive.
class DashboardData {
  final FinancialSummary summary;
  final List<SpendingCategory> categories;
  final List<double> historicExpense;
  final double predictedExpense;
  final double predictionConfidence;
  final double predictedDeltaPct;
  final List<String> monthLabels;
  final List<AiInsight> insights;
  final PaymentSuggestion paymentSuggestion;
  final List<Account> accounts;
  final List<Transaction> recentTransactions;
  final SpendingPrediction? mlPrediction;
  final InrForecast? inrForecast;

  /// True when every value came from the signed-in user's PostgreSQL records.
  final bool isLive;

  const DashboardData({
    required this.summary,
    required this.categories,
    required this.historicExpense,
    required this.predictedExpense,
    required this.predictionConfidence,
    required this.predictedDeltaPct,
    required this.monthLabels,
    required this.insights,
    required this.paymentSuggestion,
    required this.accounts,
    required this.recentTransactions,
    this.mlPrediction,
    this.inrForecast,
    this.isLive = false,
  });

  DashboardData copyWith({
    FinancialSummary? summary,
    SpendingPrediction? mlPrediction,
    InrForecast? inrForecast,
  }) {
    return DashboardData(
      summary: summary ?? this.summary,
      categories: categories,
      historicExpense: historicExpense,
      predictedExpense: predictedExpense,
      predictionConfidence: predictionConfidence,
      predictedDeltaPct: predictedDeltaPct,
      monthLabels: monthLabels,
      insights: insights,
      paymentSuggestion: paymentSuggestion,
      accounts: accounts,
      recentTransactions: recentTransactions,
      mlPrediction: mlPrediction ?? this.mlPrediction,
      inrForecast: inrForecast ?? this.inrForecast,
      isLive: isLive,
    );
  }
}

/// Single source of truth for all data the UI renders. Widgets depend only on
/// this interface, never on repository internals or hardcoded numbers.
abstract class FinanceRepository {
  Future<DashboardData> fetchDashboard();
  Future<List<Transaction>> fetchTransactions({int limit = 100});
  Future<void> addTransaction(Transaction transaction);
  Future<void> deleteTransaction(String id);
  Future<List<BudgetItem>> fetchBudget();
  Future<List<Goal>> fetchGoals();
  Future<List<Recommendation>> fetchRecommendations();
  Future<List<AlertItem>> fetchAlerts();
  Future<List<Account>> fetchAccounts();
  Future<List<ShapFactor>> fetchXaiFactors();
  Future<List<PaymentOffer>> fetchPaymentOffers();

  /// Returns a GROUNDED copilot reply. Flutter only renders; the grounding
  /// pipeline (query -> user data + ML + XAI + recommendations -> LLM) lives
  /// on the backend. This mock mirrors the expected response schema.
  Future<CopilotReply> copilotAsk(String query);

  /// BLS quarterly USD spending forecast (`POST /api/ml/spending/predict`).
  /// Painted on its own card — never mixed into the monthly INR trend.
  Future<SpendingPrediction> fetchSpendingPrediction();

  /// INR monthly bundle (`POST /predict/{spending,savings,wellness}`).
  /// Used to upgrade the dashboard summary once mock content is on screen.
  Future<InrForecast> fetchInrForecast();

  /// UCI credit-risk score (`POST /api/ml/risk/predict`).
  Future<RiskPrediction> fetchRiskPrediction();

  /// Ranked SHAP drivers for the UCI risk model (`POST /explain/risk`).
  /// Falls back to wellness drivers when the risk explainer is unavailable.
  Future<ShapExplanation> fetchRiskExplanation();

  /// Two-stage SMS classifier (`POST /api/sms/classify`).
  /// Stage 1 filters spam/noise, stage 2 assigns credit/debit/other.
  Future<SmsClassification> classifySms(String text);
}

/// In-memory repository used while backend endpoints are being stood up.
/// Add a small delay so loading/skeleton states are exercised in the UI.
class MockFinanceRepository implements FinanceRepository {
  int _delayMs = 650;
  final List<Transaction> _smsTransactions = [];

  /// Set to 0 to disable artificial latency (used by tests).
  void setDelay(int milliseconds) => _delayMs = milliseconds;

  Future<T> _slow<T>(T value) {
    // A zero delay must not schedule a timer: inside testWidgets' fake-async
    // zone an awaited `Future.delayed` before the first pump never completes.
    if (_delayMs <= 0) return Future.value(value);
    return Future<void>.delayed(
      Duration(milliseconds: _delayMs),
    ).then((_) => value);
  }

  @override
  Future<DashboardData> fetchDashboard() async {
    if (_delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: _delayMs));
    }
    return DashboardData(
      summary: MockData.summary,
      categories: MockData.categories,
      historicExpense: MockData.historicExpense,
      predictedExpense: MockData.predictedExpense,
      predictionConfidence: MockData.predictionConfidence,
      predictedDeltaPct: MockData.predictedDeltaPct,
      monthLabels: MockData.monthLabels,
      insights: MockData.insights,
      paymentSuggestion: MockData.paymentSuggestion,
      accounts: MockData.accounts,
      recentTransactions: MockData.transactions().take(5).toList(),
    );
  }

  @override
  Future<List<Transaction>> fetchTransactions({int limit = 100}) {
    final transactions = [..._smsTransactions, ...MockData.transactions()]
      ..sort((a, b) => b.date.compareTo(a.date));
    return _slow(transactions.take(limit).toList());
  }

  @override
  Future<void> addTransaction(Transaction transaction) {
    if (_smsTransactions.any((item) => item.id == transaction.id)) {
      return Future.value();
    }
    _smsTransactions.add(transaction);
    return Future.value();
  }

  @override
  Future<void> deleteTransaction(String id) {
    _smsTransactions.removeWhere((item) => item.id == id);
    return Future.value();
  }

  @override
  Future<List<BudgetItem>> fetchBudget() => _slow(MockData.budgets);

  @override
  Future<List<Goal>> fetchGoals() => _slow(MockData.goals);

  @override
  Future<List<Recommendation>> fetchRecommendations() =>
      _slow(MockData.recommendations);

  @override
  Future<List<AlertItem>> fetchAlerts() async {
    if (_delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: _delayMs));
    }
    return MockData.alerts
        .map(
          (a) => AlertItem(
            id: a.id,
            emoji: a.emoji,
            text: a.text,
            time: a.time,
            read: a.read,
          ),
        )
        .toList();
  }

  @override
  Future<List<Account>> fetchAccounts() => _slow(MockData.accounts);

  @override
  Future<List<ShapFactor>> fetchXaiFactors() => _slow(MockData.shapFactors);

  @override
  Future<List<PaymentOffer>> fetchPaymentOffers() =>
      _slow(MockData.paymentSuggestion.offers);

  @override
  Future<CopilotReply> copilotAsk(String query) async {
    if (_delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: _delayMs + 400));
    }
    final q = query.toLowerCase();
    if (q.contains('score')) {
      return const CopilotReply(
        text: 'Your score decreased mainly because:',
        bullets: [
          'Credit card utilization increased (55% → 72%)',
          'Shopping expenses increased 18%',
          'Savings rate decreased vs last quarter',
        ],
      );
    }
    if (q.contains('save')) {
      return const CopilotReply(
        text: 'Based on your data, saving ₹2,000/month is achievable:',
        bullets: [
          'Cap shopping at ₹12,000 this month',
          'Switch to the HDFC card for Amazon (save up to ₹500)',
          'Auto-transfer ₹2,000 to your goal on salary day',
        ],
      );
    }
    if (q.contains('payment')) {
      return const CopilotReply(
        text: 'For your ₹5,000 Amazon purchase, the best option is:',
        bullets: [
          'HDFC Credit Card — 10% cashback up to ₹500 (recommended)',
          'SBI Credit Card — 5% discount up to ₹300',
          'UPI — 5% cashback up to ₹250',
        ],
      );
    }
    if (q.contains('phone')) {
      return const CopilotReply(
        text: 'Affordability check for a ₹45,000 phone:',
        bullets: [
          'Pay upfront would use 72% of this month’s savings — tight',
          '0% EMI over 6 months frees your emergency fund',
          'Your wellness score impact: -4 (new EMI pressure)',
        ],
      );
    }
    return const CopilotReply(
      text:
          'Here is what your data shows for that question. Grounding sources used:',
      bullets: [
        'Your transaction history',
        'ML predictions',
        'Explainable (SHAP) results',
        'Personalised recommendations',
      ],
    );
  }

  @override
  Future<SpendingPrediction> fetchSpendingPrediction() => _slow(
    const SpendingPrediction(
      predictedSpending: 15516.58,
      currency: 'USD',
      unit: 'dollars',
      note: 'Predicted next-quarter total expenditure in USD',
    ),
  );

  @override
  Future<InrForecast> fetchInrForecast() => _slow(
    InrForecast(
      predictedSpending: MockData.predictedExpense,
      predictedSavings: MockData.summary.savings,
      wellnessScore: MockData.summary.wellnessScore,
      wellnessLevel: MockData.summary.wellnessLevel,
      note: 'Demo forecast — live values arrive when the backend is reachable.',
    ),
  );

  @override
  Future<RiskPrediction> fetchRiskPrediction() => _slow(
    const RiskPrediction(
      defaultProbability: 0.128,
      riskScore: 12.8,
      riskLevel: 'Low',
      note:
          'Risk score = predicted probability × 100; bands: 0-30 Low, 31-60 Medium, 61-100 High',
    ),
  );

  @override
  Future<ShapExplanation> fetchRiskExplanation() => _slow(
    ShapExplanation(
      top: MockData.shapFactors
          .map(
            (f) => ShapExplanationItem(
              shap: f.positive ? -f.magnitude : f.magnitude,
              transformedFeature: f.label,
              rawInputReference: f.detail,
            ),
          )
          .toList(),
    ),
  );

  /// Offline stand-in for the SMS pipeline. Keyword rules mirror the trained
  /// model's decision boundaries closely enough for UI development/tests; the
  /// live model runs on the backend via [ApiFinanceRepository].
  @override
  Future<SmsClassification> classifySms(String text) =>
      _slow(_mockClassify(text));
}

const _spamKeywords = [
  'congratulations',
  'won',
  'lottery',
  'gift card',
  'click here',
  'claim',
  'free',
  'otp',
  'suspicious',
  'verify',
];
const _creditKeywords = [
  'credited',
  'credit',
  'received',
  'salary',
  'deposited',
  'deposit',
  'refund',
  'paycheck',
];
const _debitKeywords = [
  'debited',
  'debit',
  'spent',
  'charged',
  'purchase',
  'sent',
  'paid',
  'txn',
  'payment',
];

SmsClassification _mockClassify(String rawText) {
  final text = rawText.trim();
  final lower = text.toLowerCase();
  final spam = _spamKeywords.any(lower.contains);

  if (spam) {
    return SmsClassification(
      text: text,
      isSpam: true,
      isTransaction: false,
      status: 'DISCARDED (SPAM/NOISE)',
      category: 'N/A',
      displayCategory: 'Spam / Noise',
      confidence: 88.0,
      spamProbability: 88.0,
    );
  }

  if (_creditKeywords.any(lower.contains)) {
    return SmsClassification(
      text: text,
      isSpam: false,
      isTransaction: true,
      status: 'APPROVED (TRANSACTION)',
      category: 'credit',
      displayCategory: 'Credit',
      confidence: 91.0,
      spamProbability: 4.0,
      categoryProbabilities: const {'credit': 91.0, 'debit': 6.0, 'other': 3.0},
    );
  }

  if (_debitKeywords.any(lower.contains)) {
    return SmsClassification(
      text: text,
      isSpam: false,
      isTransaction: true,
      status: 'APPROVED (TRANSACTION)',
      category: 'debit',
      displayCategory: 'Debit',
      confidence: 89.0,
      spamProbability: 6.0,
      categoryProbabilities: const {'credit': 5.0, 'debit': 89.0, 'other': 6.0},
    );
  }

  return SmsClassification(
    text: text,
    isSpam: true,
    isTransaction: false,
    status: 'DISCARDED (SPAM/NOISE)',
    category: 'N/A',
    displayCategory: 'Spam / Noise',
    confidence: 70.0,
    spamProbability: 70.0,
  );
}

/// Access point for the rest of the app.
///
/// Returns the offline mock so screens paint instantly and widget tests stay
/// hermetic. Screens upgrade to live predictions best-effort through
/// [getApiRepository] (failures keep the mock content on screen).
final MockFinanceRepository _sharedMockRepository = MockFinanceRepository();
final ApiFinanceRepository _sharedApiRepository = ApiFinanceRepository();

/// Prototype mode is enabled by default so a fresh install opens with a
/// complete, clearly labelled sample experience. The choice survives restarts.
bool demoModeEnabled = true;

/// Fires whenever the user flips demo mode, so mounted shells can rebuild and
/// reload from the correct source instead of keeping stale sample rows.
final ValueNotifier<bool> demoModeListenable = ValueNotifier<bool>(true);

/// Fires after a successful write, so other tabs can refresh without asking
/// the user to pull-to-refresh.
final ValueNotifier<int> financeDataRevision = ValueNotifier<int>(0);

void notifyFinanceDataChanged() => financeDataRevision.value++;

/// Namespace for the current user's PostgreSQL rows.
///
/// The prototype has no sign-in yet, so a stable per-install id is used. It is
/// persisted locally and sent to the backend on every data request.
String currentUserId = 'local-user';

Future<void> loadUserIdentity() async {
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString('user_id');
  if (id == null || id.trim().isEmpty) {
    id = 'local-user';
    await prefs.setString('user_id', id);
  }
  currentUserId = id;
}

Future<void> setUserIdentity(String id) async {
  final trimmed = id.trim();
  if (trimmed.isEmpty) throw ArgumentError.value(id, 'id', 'User id is empty');
  currentUserId = trimmed;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('user_id', trimmed);
  notifyFinanceDataChanged();
}

Future<void> loadDemoModePreference() async {
  final prefs = await SharedPreferences.getInstance();
  demoModeEnabled = prefs.getBool('demo_mode_enabled') ?? true;
  demoModeListenable.value = demoModeEnabled;
}

Future<void> setDemoModeEnabled(bool enabled) async {
  demoModeEnabled = enabled;
  demoModeListenable.value = enabled;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('demo_mode_enabled', enabled);
  notifyFinanceDataChanged();
}

FinanceRepository getRepository() => _sharedApiRepository;

/// Live backend repository. Every ML call hits the API; anything without a
/// backend endpoint (transactions, budgets, goals, ...) is served from the
/// same mock data so the UI contract never changes.
FinanceRepository getApiRepository() => _sharedApiRepository;

/// Demo BLS payload matching `ml/models/spending/random forest/feature_columns.json`.
/// Used for the quarterly USD forecast card (see backend/test_ml_api.py).
const Map<String, double> blsSpendingPayload = {
  'age_ref': 45,
  'age2': 2025,
  'fam_size': 3,
  'educ_ref': 4,
  'seq': 1,
  'totexppq': 15000,
  'foodpq': 2000,
  'houspq': 6000,
  'transpq': 2500,
  'utilpq': 1000,
  'sheltpq': 500,
  'itbi_q_income': 20000,
  'cuincome_class': 3,
  'total_spend_lag1': 14000,
  'total_spend_pastmean': 14500,
  'total_spend_paststd': 1000,
  'food_lag1': 1900,
  'housing_lag1': 5800,
  'income_lag1': 19500,
  'fam_type': 1,
  'cutenure': 1,
  'bls_urbn': 1,
};

/// Demo UCI payload matching `ml/models/risk/gradient boosting/feature_columns.json`.
const Map<String, double> uciRiskPayload = {
  'LIMIT_BAL': 100000,
  'AGE': 35,
  'PAY_0': 0,
  'PAY_2': 0,
  'PAY_3': 0,
  'PAY_4': 0,
  'PAY_5': 0,
  'PAY_6': 0,
  'BILL_AMT1': 5000,
  'BILL_AMT2': 4500,
  'BILL_AMT3': 4000,
  'BILL_AMT4': 3500,
  'BILL_AMT5': 3000,
  'BILL_AMT6': 2500,
  'PAY_AMT1': 2000,
  'PAY_AMT2': 2000,
  'PAY_AMT3': 2000,
  'PAY_AMT4': 2000,
  'PAY_AMT5': 2000,
  'PAY_AMT6': 2000,
  'util_mean6': 0.3,
  'repay_ratio_mean6': 0.8,
  'max_delinq_6m': 0,
  'SEX': 1,
  'EDUCATION': 2,
  'MARRIAGE': 1,
};

/// Live implementation of [FinanceRepository] backed by the WealthSync API.
///
/// Pipeline per model family:
/// - BLS spending (USD, quarterly): `POST /api/ml/spending/predict`
/// - INR spending/savings/wellness: `GET /sample/{model}` then
///   `POST /predict/{model}` (exact trained columns, trained order)
/// - UCI risk: `POST /api/ml/risk/predict`; drivers via `POST /explain/risk`
/// - Wellness drivers: `POST /explain/wellness`
class ApiFinanceRepository implements FinanceRepository {
  ApiFinanceRepository({FinanceRepository? fallback})
    : _fallback = fallback ?? _sharedMockRepository;

  final FinanceRepository _fallback;
  static const _timeout = Duration(seconds: 12);

  @override
  Future<DashboardData> fetchDashboard() async {
    if (demoModeEnabled) return _fallback.fetchDashboard();
    return _fetchLiveDashboard();
  }

  @override
  Future<List<Transaction>> fetchTransactions({int limit = 100}) =>
      demoModeEnabled
      ? _fallback.fetchTransactions(limit: limit)
      : _fetchTransactions(limit);

  @override
  Future<List<BudgetItem>> fetchBudget() =>
      demoModeEnabled ? _fallback.fetchBudget() : _fetchBudget();

  @override
  Future<List<Goal>> fetchGoals() =>
      demoModeEnabled ? _fallback.fetchGoals() : _fetchGoals();

  @override
  Future<List<Recommendation>> fetchRecommendations() => demoModeEnabled
      ? _fallback.fetchRecommendations()
      : _fetchRecommendations();

  @override
  Future<List<AlertItem>> fetchAlerts() =>
      demoModeEnabled ? _fallback.fetchAlerts() : _fetchAlerts();

  @override
  Future<List<Account>> fetchAccounts() =>
      demoModeEnabled ? _fallback.fetchAccounts() : _fetchAccounts();

  @override
  Future<List<PaymentOffer>> fetchPaymentOffers() => demoModeEnabled
      ? _fallback.fetchPaymentOffers()
      : Future.value(const <PaymentOffer>[]);

  @override
  Future<CopilotReply> copilotAsk(String query) async {
    if (demoModeEnabled) return _fallback.copilotAsk(query);
    try {
      final data = await _fetchLiveDashboard();
      final summary = data.summary;
      final q = query.toLowerCase();
      final top = data.insights.take(3).map((i) => i.text).toList();

      if (q.contains('score')) {
        return CopilotReply(
          text:
              'Your wellness score is ${summary.wellnessScore}/100 '
              '(${summary.wellnessLevel}).',
          bullets: top.isEmpty
              ? ['Add transactions to generate score drivers.']
              : top,
        );
      }
      if (q.contains('save')) {
        return CopilotReply(
          text:
              'This month you saved ₹${summary.savings.toStringAsFixed(0)} '
              'on ₹${summary.income.toStringAsFixed(0)} of income.',
          bullets: top.isEmpty
              ? ['Record your income and expenses to get saving ideas.']
              : top,
        );
      }
      if (q.contains('payment')) {
        final suggestion = data.paymentSuggestion;
        if (suggestion.amount > 0) {
          return CopilotReply(
            text:
                'Your latest expense was ₹${suggestion.amount.toStringAsFixed(0)} '
                'at ${suggestion.merchant}.',
            bullets: const [
              'No stored card/UPI offers match this purchase yet.',
              'Add offers under recommendations to rank payment methods.',
            ],
          );
        }
        return const CopilotReply(
          text: 'There is no recent purchase to optimise yet.',
          bullets: ['Add a transaction, then ask again.'],
        );
      }
      return CopilotReply(
        text:
            'This month: income ₹${summary.income.toStringAsFixed(0)}, '
            'expenses ₹${summary.expenses.toStringAsFixed(0)}, '
            'savings ₹${summary.savings.toStringAsFixed(0)}.',
        bullets: top.isEmpty
            ? ['Add transactions to unlock grounded answers.']
            : top,
      );
    } catch (_) {
      return const CopilotReply(
        text: 'I could not reach your saved data right now.',
        bullets: ['Check the backend connection in Settings, then retry.'],
      );
    }
  }

  @override
  Future<SpendingPrediction> fetchSpendingPrediction() {
    return ApiClient.instance
        .predictSpendingBLS(blsSpendingPayload)
        .timeout(_timeout);
  }

  @override
  Future<InrForecast> fetchInrForecast() async {
    final api = ApiClient.instance;
    final results = await Future.wait([
      api.sampleFeatures('spending').timeout(_timeout),
      api.sampleFeatures('savings').timeout(_timeout),
      api.sampleFeatures('wellness').timeout(_timeout),
    ]);
    final spendingFeatures = results[0];
    final savingsFeatures = results[1];
    final wellnessFeatures = results[2];
    final predictions = await Future.wait([
      api.predict('spending', spendingFeatures).timeout(_timeout),
      api.predict('savings', savingsFeatures).timeout(_timeout),
      api.predict('wellness', wellnessFeatures).timeout(_timeout),
    ]);
    final spending = (predictions[0]['prediction'] as num).toDouble();
    final savings = (predictions[1]['prediction'] as num).toDouble();
    final wellness = ((predictions[2]['prediction'] as num).toDouble())
        .round()
        .clamp(0, 100)
        .toInt();
    return InrForecast(
      predictedSpending: spending,
      predictedSavings: savings,
      wellnessScore: wellness,
      wellnessLevel: InrForecast.levelFor(wellness),
      note:
          'Live forecast from the monthly INR models (spending/savings/wellness).',
    );
  }

  @override
  Future<RiskPrediction> fetchRiskPrediction() {
    return ApiClient.instance.predictRiskUCI(uciRiskPayload).timeout(_timeout);
  }

  @override
  Future<ShapExplanation> fetchRiskExplanation() async {
    try {
      return await ApiClient.instance
          .explainModel('risk', uciRiskPayload)
          .timeout(_timeout);
    } catch (_) {
      // The pipeline-model explainer can be unavailable while /predict works;
      // fall back to mock drivers rather than blanking the screen.
      return _fallback.fetchRiskExplanation();
    }
  }

  @override
  Future<List<ShapFactor>> fetchXaiFactors() async {
    try {
      final api = ApiClient.instance;
      final features = await api.sampleFeatures('wellness').timeout(_timeout);
      final explanation = await api
          .explainModel('wellness', features)
          .timeout(_timeout);
      final items = explanation.top.take(4).toList();
      if (items.isEmpty) return await _fallback.fetchXaiFactors();
      final maxAbs = items
          .map((e) => e.shap.abs())
          .reduce((a, b) => a > b ? a : b);
      return [
        for (final e in items)
          ShapFactor(
            label: e.transformedFeature,
            magnitude: maxAbs > 0
                ? (e.shap.abs() / maxAbs).clamp(0.02, 1.0)
                : 0.5,
            positive: e.shap >= 0,
            detail:
                'SHAP impact ${e.shap.toStringAsFixed(2)} on the wellness score.',
          ),
      ];
    } catch (_) {
      return _fallback.fetchXaiFactors();
    }
  }

  @override
  Future<void> addTransaction(Transaction transaction) async {
    if (demoModeEnabled) {
      await _fallback.addTransaction(transaction);
    } else {
      await _saveTransaction(transaction);
    }
    notifyFinanceDataChanged();
  }

  @override
  Future<void> deleteTransaction(String id) async {
    if (demoModeEnabled) {
      await _fallback.deleteTransaction(id);
    } else {
      await ApiClient.instance.deleteData('transactions', id);
    }
    notifyFinanceDataChanged();
  }

  Future<List<Transaction>> _fetchTransactions(int limit) async {
    final rows = await ApiClient.instance.listData('transactions');
    final items = rows.map(_transactionFromJson).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return items.take(limit).toList();
  }

  /// Fetches the signed-in user's rows and aggregates them into the dashboard.
  Future<DashboardData> _fetchLiveDashboard() async {
    final api = ApiClient.instance;
    final results = await Future.wait([
      api.listData('transactions'),
      api.listData('accounts'),
      api.listData('budgets'),
      api.listData('goals'),
    ]);

    return buildDashboardFromRecords(
      transactions: results[0].map(_transactionFromJson).toList(),
      accounts: results[1].map(_accountFromJson).toList(),
      budgets: results[2].map(_budgetFromJson).toList(),
      goals: results[3].map(_goalFromJson).toList(),
    );
  }

  Future<List<BudgetItem>> _fetchBudget() async =>
      (await ApiClient.instance.listData('budgets'))
          .map(_budgetFromJson)
          .toList();

  Future<List<Goal>> _fetchGoals() async =>
      (await ApiClient.instance.listData('goals')).map(_goalFromJson).toList();

  Future<List<Recommendation>> _fetchRecommendations() async =>
      (await ApiClient.instance.listData('recommendations'))
          .map(_recommendationFromJson)
          .toList();

  Future<List<AlertItem>> _fetchAlerts() async =>
      (await ApiClient.instance.listData('alerts')).map(_alertFromJson).toList();

  Future<List<Account>> _fetchAccounts() async =>
      (await ApiClient.instance.listData('accounts'))
          .map(_accountFromJson)
          .toList();

  Future<void> _saveTransaction(Transaction transaction) =>
      ApiClient.instance.saveData(
        'transactions',
        transaction.id,
        _transactionToJson(transaction),
      );

  @override
  Future<SmsClassification> classifySms(String text) async {
    if (demoModeEnabled) return _fallback.classifySms(text);
    try {
      return await ApiClient.instance.classifySms(text).timeout(_timeout);
    } catch (_) {
      // Backend unreachable: fall back to the on-device heuristic so the
      // interactive screen still responds.
      return _fallback.classifySms(text);
    }
  }
}

/* -------------------------------------------------------------------------- */
/*  Real API plumbing (ready for when GET /api/dashboard etc. land).           */
/*  The ML endpoints below ALREADY exist and are used by the ML demo screen.   */
/* -------------------------------------------------------------------------- */

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);

  @override
  String toString() => '[$status] $message';
}

TxnCategory _categoryFromJson(dynamic raw) {
  final value = raw?.toString().toLowerCase();
  return TxnCategory.values.firstWhere(
    (category) =>
        category.name == value || category.label.toLowerCase() == value,
    orElse: () => TxnCategory.others,
  );
}

Transaction _transactionFromJson(Map<String, dynamic> row) => Transaction(
  id: '${row['id']}',
  merchant: '${row['merchant']}',
  category: _categoryFromJson(row['category']),
  type: '${row['type']}'.toLowerCase() == 'income'
      ? TxnType.income
      : TxnType.expense,
  amount: (row['amount'] as num).toDouble(),
  date: DateTime.parse('${row['date']}'),
  note: row['note'] as String?,
);

Map<String, dynamic> _transactionToJson(Transaction transaction) => {
  'id': transaction.id,
  'merchant': transaction.merchant,
  'category': transaction.category.name,
  'type': transaction.type.name,
  'amount': transaction.amount,
  'date': transaction.date.toIso8601String(),
  if (transaction.note != null) 'note': transaction.note,
};

Account _accountFromJson(Map<String, dynamic> row) => Account(
  id: '${row['id']}',
  bank: '${row['bank'] ?? row['name'] ?? 'Account'}',
  subLabel: '${row['subLabel'] ?? ''}',
  balance: (row['balance'] as num?)?.toDouble() ?? 0,
  icon: Icons.account_balance,
  color: const Color(0xFF36B4FF),
);

BudgetItem _budgetFromJson(Map<String, dynamic> row) => BudgetItem(
  category: _categoryFromJson(row['category']),
  spent: (row['spent'] as num?)?.toDouble() ?? 0,
  limit: (row['limit'] as num?)?.toDouble() ?? 0,
);

Goal _goalFromJson(Map<String, dynamic> row) => Goal(
  id: '${row['id']}',
  title: '${row['title'] ?? ''}',
  icon: '${row['icon'] ?? '🎯'}',
  saved: (row['saved'] as num?)?.toDouble() ?? 0,
  target: (row['target'] as num?)?.toDouble() ?? 0,
  note: '${row['note'] ?? ''}',
);

AlertItem _alertFromJson(Map<String, dynamic> row) => AlertItem(
  id: '${row['id']}',
  emoji: '${row['emoji'] ?? '🔔'}',
  text: '${row['text'] ?? ''}',
  time: '${row['time'] ?? ''}',
  read: row['read'] == true,
);

Recommendation _recommendationFromJson(Map<String, dynamic> row) =>
    Recommendation(
      id: '${row['id']}',
      category: '${row['category'] ?? 'General'}',
      title: '${row['title'] ?? ''}',
      description: '${row['description'] ?? ''}',
      action: '${row['action'] ?? 'View suggestion'}',
    );

bool _inMonth(DateTime value, DateTime monthStart) =>
    !value.isBefore(DateTime(monthStart.year, monthStart.month)) &&
    value.isBefore(DateTime(monthStart.year, monthStart.month + 1));

double _sumWhere(List<Transaction> rows, {required bool income}) => rows
    .where((t) => t.isIncome == income)
    .fold<double>(0, (sum, t) => sum + t.amount);

double _monthlyExpense(List<Transaction> transactions, DateTime monthStart) =>
    transactions
        .where((t) => !t.isIncome && _inMonth(t.date, monthStart))
        .fold<double>(0, (sum, t) => sum + t.amount);

double _pctDelta(double current, double previous) {
  if (previous == 0) return current == 0 ? 0 : 100;
  return (current - previous) / previous * 100;
}

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _monthLabel(DateTime value) => _monthNames[value.month - 1];

/// Aggregates a user's rows into the dashboard model.
///
/// Split out from the HTTP repository so the math is deterministic and testable
/// without a running backend. [now] is injectable for month-boundary tests.
DashboardData buildDashboardFromRecords({
  required List<Transaction> transactions,
  required List<Account> accounts,
  required List<BudgetItem> budgets,
  required List<Goal> goals,
  DateTime? now,
}) {
  final sorted = [...transactions]..sort((a, b) => b.date.compareTo(a.date));
  final today = now ?? DateTime.now();
  final currentStart = DateTime(today.year, today.month);
  final previousStart = DateTime(today.year, today.month - 1);

  final current = sorted
      .where((t) => _inMonth(t.date, currentStart))
      .toList();
  final previous = sorted
      .where((t) => _inMonth(t.date, previousStart))
      .toList();

  final income = _sumWhere(current, income: true);
  final expenses = _sumWhere(current, income: false);
  final prevIncome = _sumWhere(previous, income: true);
  final prevExpenses = _sumWhere(previous, income: false);
  final savings = income - expenses;
  final prevSavings = prevIncome - prevExpenses;

  final hasActivity =
      sorted.isNotEmpty || budgets.isNotEmpty || goals.isNotEmpty;
  final score = _wellnessScore(income, expenses, budgets, hasActivity);
  final prevScore = _wellnessScore(
    prevIncome,
    prevExpenses,
    budgets,
    previous.isNotEmpty,
  );

  final byCategory = <TxnCategory, double>{};
  for (final t in current.where((t) => !t.isIncome)) {
    byCategory.update(t.category, (v) => v + t.amount, ifAbsent: () => t.amount);
  }
  final categories = byCategory.entries
      .map(
        (e) => SpendingCategory(
          category: e.key,
          amount: e.value,
          pct: expenses > 0
              ? double.parse((e.value / expenses * 100).toStringAsFixed(1))
              : 0,
        ),
      )
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  final monthStarts = List.generate(
    6,
    (i) => DateTime(today.year, today.month - 5 + i),
  );
  final historic = [
    for (final start in monthStarts) _monthlyExpense(sorted, start),
  ];
  final monthLabels = [
    for (final start in monthStarts) _monthLabel(start),
    '${_monthLabel(DateTime(today.year, today.month + 1))} (Proj.)',
  ];

  // Project from complete months only; the current month is still partial.
  final completed = historic.sublist(0, 5).where((v) => v > 0).toList();
  final predicted = completed.isEmpty
      ? 0.0
      : completed.reduce((a, b) => a + b) / completed.length;
  final predictedDeltaPct = expenses > 0
      ? (predicted - expenses) / expenses * 100
      : 0.0;

  return DashboardData(
    summary: FinancialSummary(
      income: income,
      incomeDeltaPct: _pctDelta(income, prevIncome),
      expenses: expenses,
      expensesDeltaPct: _pctDelta(expenses, prevExpenses),
      savings: savings,
      savingsDeltaPct: _pctDelta(savings, prevSavings),
      wellnessScore: score,
      wellnessLevel: hasActivity
          ? InrForecast.levelFor(score)
          : 'No data yet',
      wellnessDelta: score - prevScore,
      wellnessPrev: prevScore,
    ),
    categories: categories,
    historicExpense: historic,
    predictedExpense: predicted,
    predictionConfidence: completed.isEmpty ? 0 : 0.65,
    predictedDeltaPct: predictedDeltaPct,
    monthLabels: monthLabels,
    insights: _buildInsights(
      categories: categories,
      income: income,
      expenses: expenses,
      budgets: budgets,
      goals: goals,
      hasActivity: hasActivity,
    ),
    paymentSuggestion: _paymentSuggestion(sorted),
    accounts: accounts,
    recentTransactions: sorted.take(5).toList(),
    isLive: true,
  );
}

/// Transparent heuristic (not a trained model): savings rate, penalised when
/// category budgets are close to or over their limits.
int _wellnessScore(
  double income,
  double expenses,
  List<BudgetItem> budgets,
  bool hasActivity,
) {
  if (!hasActivity && income <= 0 && expenses <= 0) return 0;
  final savingsRate = income > 0 ? (income - expenses) / income : 0.0;
  var score = 55 + savingsRate * 45;
  final activeBudgets = budgets.where((b) => b.limit > 0).toList();
  if (activeBudgets.isNotEmpty) {
    final pressure =
        activeBudgets
            .map((b) => (b.spent / b.limit).clamp(0.0, 1.5))
            .fold<double>(0, (sum, v) => sum + v) /
        activeBudgets.length;
    score -= pressure * 15;
  }
  return score.round().clamp(0, 100);
}

List<AiInsight> _buildInsights({
  required List<SpendingCategory> categories,
  required double income,
  required double expenses,
  required List<BudgetItem> budgets,
  required List<Goal> goals,
  required bool hasActivity,
}) {
  final insights = <AiInsight>[];

  if (categories.isNotEmpty && expenses > 0) {
    final top = categories.first;
    insights.add(
      AiInsight(
        id: 'live-category',
        icon: '📊',
        text:
            '${top.category.label} is ${top.pct.toStringAsFixed(0)}% of this month\'s spending.',
        action: top.pct >= 35
            ? 'Review this category to free up cash.'
            : 'Keep tracking to spot trends early.',
        tone: top.pct >= 35 ? InsightTone.highImpact : InsightTone.warning,
      ),
    );
  }

  if (income > 0) {
    final rate = (income - expenses) / income * 100;
    insights.add(
      AiInsight(
        id: 'live-savings',
        icon: '💰',
        text: 'You saved ${rate.toStringAsFixed(0)}% of this month\'s income.',
        action: rate >= 20
            ? 'Move the surplus into a goal or emergency fund.'
            : 'Aim for 20% to build a buffer.',
        tone: rate >= 20 ? InsightTone.positive : InsightTone.warning,
      ),
    );
  } else if (expenses > 0) {
    insights.add(
      const AiInsight(
        id: 'live-income',
        icon: '📥',
        text: 'No income recorded this month.',
        action: 'Add salary or other credits to complete the picture.',
        tone: InsightTone.warning,
      ),
    );
  }

  for (final budget in budgets
      .where((b) => b.limit > 0 && b.spent / b.limit >= 0.8)
      .take(1)) {
    final pct = (budget.spent / budget.limit * 100).round();
    insights.add(
      AiInsight(
        id: 'live-budget-${budget.category.name}',
        icon: '⚠️',
        text: '${budget.category.label} is at $pct% of its budget.',
        action: 'Slow down spending in this category.',
        tone: InsightTone.highImpact,
      ),
    );
  }

  final rankedGoals = goals.where((g) => g.target > 0).toList()
    ..sort((a, b) => (b.saved / b.target).compareTo(a.saved / a.target));
  if (rankedGoals.isNotEmpty) {
    final goal = rankedGoals.first;
    insights.add(
      AiInsight(
        id: 'live-goal-${goal.id}',
        icon: '🎯',
        text:
            '${goal.title} is ${(goal.saved / goal.target * 100).round()}% funded.',
        action: 'Keep contributing to stay on track.',
        tone: InsightTone.positive,
      ),
    );
  }

  if (insights.isEmpty || !hasActivity) {
    insights.add(
      const AiInsight(
        id: 'live-empty',
        icon: '📈',
        text: 'No financial activity recorded yet.',
        action: 'Add a transaction to unlock personalised insights.',
        tone: InsightTone.warning,
      ),
    );
  }
  return insights;
}

/// Uses the latest recorded expense as the "about to spend" prompt. Offers are
/// only shown when the backend/user has stored them, never from sample data.
PaymentSuggestion _paymentSuggestion(List<Transaction> transactions) {
  Transaction? latest;
  for (final t in transactions) {
    if (!t.isIncome) {
      latest = t;
      break;
    }
  }
  return PaymentSuggestion(
    merchant: latest?.merchant ?? '',
    amount: latest?.amount ?? 0,
    offers: const [],
  );
}

/// Thin HTTP client for the WealthSync backend. Typed helpers mirror the API.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final String base = Config.apiBaseUrl;
  final _client = http.Client();

  Future<List<Map<String, dynamic>>> listData(String resource) async {
    final decoded =
        await _get('/api/data/$resource?user_id=${_userIdParam()}')
            as Map<String, dynamic>;
    return (decoded['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> saveData(
    String resource,
    String id,
    Map<String, dynamic> payload,
  ) async {
    await _put(
      '/api/data/$resource/${Uri.encodeComponent(id)}?user_id=${_userIdParam()}',
      payload,
    );
  }

  Future<void> deleteData(String resource, String id) async {
    await _delete(
      '/api/data/$resource/${Uri.encodeComponent(id)}?user_id=${_userIdParam()}',
    );
  }

  static String _userIdParam() =>
      Uri.encodeQueryComponent(currentUserId);

  Future<bool> health() async {
    try {
      final r = await _client
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 10));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> healthDetails() async {
    final decoded = await _get('/health');
    return (decoded as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> models() async {
    final res = await _get('/models');
    return (res as Map).cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> sample(String model) async {
    final json = await _get('/sample/$model') as Map<String, dynamic>;
    return (json['samples'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> predict(
    String model,
    Map<String, double> features,
  ) async {
    final res = await _post('/predict/$model', {'features': features});
    return (res as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> explain(
    String model,
    Map<String, double> features,
  ) async {
    final res = await _post('/explain/$model', {'features': features});
    return (res as Map).cast<String, dynamic>();
  }

  /// First test-window feature row for an INR model (`GET /sample/{model}`).
  ///
  /// The backend rebuilds the exact training-time frame, so the returned map
  /// always carries the trained columns in the trained order.
  Future<Map<String, double>> sampleFeatures(String model) async {
    final samples = await sample(model);
    final features = (samples.first['features'] as Map).cast<String, dynamic>();
    return features.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  /// BLS quarterly USD forecast (`POST /api/ml/spending/predict`).
  Future<SpendingPrediction> predictSpendingBLS(
    Map<String, double> features,
  ) async {
    final resp = await _client
        .post(
          Uri.parse('$base/api/ml/spending/predict'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(features),
        )
        .timeout(const Duration(seconds: 30));
    final decoded = _decode(resp) as Map<String, dynamic>;
    return SpendingPrediction.fromJson(
      (decoded['data'] as Map).cast<String, dynamic>(),
    );
  }

  /// UCI credit-risk score (`POST /api/ml/risk/predict`).
  Future<RiskPrediction> predictRiskUCI(Map<String, double> features) async {
    final resp = await _client
        .post(
          Uri.parse('$base/api/ml/risk/predict'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(features),
        )
        .timeout(const Duration(seconds: 30));
    final decoded = _decode(resp) as Map<String, dynamic>;
    return RiskPrediction.fromJson(
      (decoded['data'] as Map).cast<String, dynamic>(),
    );
  }

  /// Ranked SHAP drivers (`POST /explain/{model}`).
  Future<ShapExplanation> explainModel(
    String model,
    Map<String, double> features,
  ) async {
    final res = await explain(model, features);
    return ShapExplanation.fromJson(res);
  }

  /// Two-stage SMS classification (`POST /api/sms/classify`).
  Future<SmsClassification> classifySms(String text) async {
    final res = await _post('/api/sms/classify', {'text': text});
    final data = ((res as Map)['data'] as Map).cast<String, dynamic>();
    return SmsClassification.fromJson(data);
  }

  Future<dynamic> _get(String path) async {
    final resp = await _client
        .get(Uri.parse('$base$path'))
        .timeout(const Duration(seconds: 30));
    return _decode(resp);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> payload) async {
    final resp = await _client
        .post(
          Uri.parse('$base$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));
    return _decode(resp);
  }

  Future<dynamic> _put(String path, Map<String, dynamic> payload) async {
    final resp = await _client
        .put(
          Uri.parse('$base$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));
    return _decode(resp);
  }

  Future<dynamic> _delete(String path) async {
    final resp = await _client
        .delete(Uri.parse('$base$path'))
        .timeout(const Duration(seconds: 30));
    return _decode(resp);
  }

  dynamic _decode(http.Response resp) {
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final detail = decoded is Map && decoded['detail'] != null
          ? decoded['detail']
          : decoded;
      throw ApiException(resp.statusCode, detail.toString());
    }
    return decoded;
  }
}
