import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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
    );
  }
}

/// Single source of truth for all data the UI renders. Widgets depend only on
/// this interface, never on repository internals or hardcoded numbers.
abstract class FinanceRepository {
  Future<DashboardData> fetchDashboard();
  Future<List<Transaction>> fetchTransactions({int limit = 100});
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
}

/// In-memory repository used while backend endpoints are being stood up.
/// Add a small delay so loading/skeleton states are exercised in the UI.
class MockFinanceRepository implements FinanceRepository {
  int _delayMs = 650;

  /// Set to 0 to disable artificial latency (used by tests).
  void setDelay(int milliseconds) => _delayMs = milliseconds;

  Future<T> _slow<T>(T value) {
    // A zero delay must not schedule a timer: inside testWidgets' fake-async
    // zone an awaited `Future.delayed` before the first pump never completes.
    if (_delayMs <= 0) return Future.value(value);
    return Future<void>.delayed(Duration(milliseconds: _delayMs)).then((_) => value);
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
  Future<List<Transaction>> fetchTransactions({int limit = 100}) =>
      _slow(MockData.transactions().take(limit).toList());

  @override
  Future<List<BudgetItem>> fetchBudget() => _slow(MockData.budgets);

  @override
  Future<List<Goal>> fetchGoals() => _slow(MockData.goals);

  @override
  Future<List<Recommendation>> fetchRecommendations() => _slow(MockData.recommendations);

  @override
  Future<List<AlertItem>> fetchAlerts() async {
    if (_delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: _delayMs));
    }
    return MockData.alerts.map((a) => AlertItem(id: a.id, emoji: a.emoji, text: a.text, time: a.time, read: a.read)).toList();
  }

  @override
  Future<List<Account>> fetchAccounts() => _slow(MockData.accounts);

  @override
  Future<List<ShapFactor>> fetchXaiFactors() => _slow(MockData.shapFactors);

  @override
  Future<List<PaymentOffer>> fetchPaymentOffers() => _slow(MockData.paymentSuggestion.offers);

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
      text: 'Here is what your data shows for that question. Grounding sources used:',
      bullets: ['Your transaction history', 'ML predictions', 'Explainable (SHAP) results', 'Personalised recommendations'],
    );
  }

  @override
  Future<SpendingPrediction> fetchSpendingPrediction() => _slow(const SpendingPrediction(
        predictedSpending: 15516.58,
        currency: 'USD',
        unit: 'dollars',
        note: 'Predicted next-quarter total expenditure in USD',
      ));

  @override
  Future<InrForecast> fetchInrForecast() => _slow(InrForecast(
        predictedSpending: MockData.predictedExpense,
        predictedSavings: MockData.summary.savings,
        wellnessScore: MockData.summary.wellnessScore,
        wellnessLevel: MockData.summary.wellnessLevel,
        note: 'Demo forecast — live values arrive when the backend is reachable.',
      ));

  @override
  Future<RiskPrediction> fetchRiskPrediction() => _slow(const RiskPrediction(
        defaultProbability: 0.128,
        riskScore: 12.8,
        riskLevel: 'Low',
        note: 'Risk score = predicted probability × 100; bands: 0-30 Low, 31-60 Medium, 61-100 High',
      ));

  @override
  Future<ShapExplanation> fetchRiskExplanation() => _slow(ShapExplanation(
        top: MockData.shapFactors
            .map((f) => ShapExplanationItem(
                  shap: f.positive ? -f.magnitude : f.magnitude,
                  transformedFeature: f.label,
                  rawInputReference: f.detail,
                ))
            .toList(),
      ));
}

/// Access point for the rest of the app.
///
/// Returns the offline mock so screens paint instantly and widget tests stay
/// hermetic. Screens upgrade to live predictions best-effort through
/// [getApiRepository] (failures keep the mock content on screen).
FinanceRepository getRepository() => MockFinanceRepository();

/// Live backend repository. Every ML call hits the API; anything without a
/// backend endpoint (transactions, budgets, goals, ...) is served from the
/// same mock data so the UI contract never changes.
FinanceRepository getApiRepository() => ApiFinanceRepository();

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
      : _fallback = fallback ?? (MockFinanceRepository()..setDelay(0));

  final FinanceRepository _fallback;
  static const _timeout = Duration(seconds: 12);

  @override
  Future<DashboardData> fetchDashboard() => _fallback.fetchDashboard();

  @override
  Future<List<Transaction>> fetchTransactions({int limit = 100}) =>
      _fallback.fetchTransactions(limit: limit);

  @override
  Future<List<BudgetItem>> fetchBudget() => _fallback.fetchBudget();

  @override
  Future<List<Goal>> fetchGoals() => _fallback.fetchGoals();

  @override
  Future<List<Recommendation>> fetchRecommendations() => _fallback.fetchRecommendations();

  @override
  Future<List<AlertItem>> fetchAlerts() => _fallback.fetchAlerts();

  @override
  Future<List<Account>> fetchAccounts() => _fallback.fetchAccounts();

  @override
  Future<List<PaymentOffer>> fetchPaymentOffers() => _fallback.fetchPaymentOffers();

  @override
  Future<CopilotReply> copilotAsk(String query) => _fallback.copilotAsk(query);

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
    final wellness = ((predictions[2]['prediction'] as num).toDouble()).round().clamp(0, 100).toInt();
    return InrForecast(
      predictedSpending: spending,
      predictedSavings: savings,
      wellnessScore: wellness,
      wellnessLevel: InrForecast.levelFor(wellness),
      note: 'Live forecast from the monthly INR models (spending/savings/wellness).',
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
      final explanation = await api.explainModel('wellness', features).timeout(_timeout);
      final items = explanation.top.take(4).toList();
      if (items.isEmpty) return await _fallback.fetchXaiFactors();
      final maxAbs = items.map((e) => e.shap.abs()).reduce((a, b) => a > b ? a : b);
      return [
        for (final e in items)
          ShapFactor(
            label: e.transformedFeature,
            magnitude: maxAbs > 0 ? (e.shap.abs() / maxAbs).clamp(0.02, 1.0) : 0.5,
            positive: e.shap >= 0,
            detail: 'SHAP impact ${e.shap.toStringAsFixed(2)} on the wellness score.',
          ),
      ];
    } catch (_) {
      return _fallback.fetchXaiFactors();
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

/// Thin HTTP client for the WealthSync backend. Typed helpers mirror the API.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final String base = Config.apiBaseUrl;
  final _client = http.Client();

  Future<bool> health() async {
    try {
      final r = await _client.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 10));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> models() async {
    final res = await _get('/models');
    return (res as Map).cast<String, dynamic>();
  }

  Future<List<Map<String, dynamic>>> sample(String model) async {
    final json = await _get('/sample/$model') as Map<String, dynamic>;
    return (json['samples'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> predict(String model, Map<String, double> features) async {
    final res = await _post('/predict/$model', {'features': features});
    return (res as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> explain(String model, Map<String, double> features) async {
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
  Future<SpendingPrediction> predictSpendingBLS(Map<String, double> features) async {
    final resp = await _client
        .post(Uri.parse('$base/api/ml/spending/predict'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode(features))
        .timeout(const Duration(seconds: 30));
    final decoded = _decode(resp) as Map<String, dynamic>;
    return SpendingPrediction.fromJson((decoded['data'] as Map).cast<String, dynamic>());
  }

  /// UCI credit-risk score (`POST /api/ml/risk/predict`).
  Future<RiskPrediction> predictRiskUCI(Map<String, double> features) async {
    final resp = await _client
        .post(Uri.parse('$base/api/ml/risk/predict'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode(features))
        .timeout(const Duration(seconds: 30));
    final decoded = _decode(resp) as Map<String, dynamic>;
    return RiskPrediction.fromJson((decoded['data'] as Map).cast<String, dynamic>());
  }

  /// Ranked SHAP drivers (`POST /explain/{model}`).
  Future<ShapExplanation> explainModel(String model, Map<String, double> features) async {
    final res = await explain(model, features);
    return ShapExplanation.fromJson(res);
  }

  Future<dynamic> _get(String path) async {
    final resp = await _client.get(Uri.parse('$base$path')).timeout(const Duration(seconds: 30));
    return _decode(resp);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> payload) async {
    final resp = await _client
        .post(Uri.parse('$base$path'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 30));
    return _decode(resp);
  }

  dynamic _decode(http.Response resp) {
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final detail = decoded is Map && decoded['detail'] != null ? decoded['detail'] : decoded;
      throw ApiException(resp.statusCode, detail.toString());
    }
    return decoded;
  }
}