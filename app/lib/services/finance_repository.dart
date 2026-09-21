import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';
import 'mock_data.dart';

/// Aggregate object returned for the dashboard screen.
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
  });
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
}

/// In-memory repository used while backend endpoints are being stood up.
/// Add a small delay so loading/skeleton states are exercised in the UI.
class MockFinanceRepository implements FinanceRepository {
  int _delayMs = 650;

  /// Set to 0 to disable artificial latency (used by tests).
  void setDelay(int milliseconds) => _delayMs = milliseconds;

  Future<T> _slow<T>(T value) async {
    await Future<void>.delayed(Duration(milliseconds: _delayMs));
    return value;
  }

  @override
  Future<DashboardData> fetchDashboard() async {
    await Future<void>.delayed(Duration(milliseconds: _delayMs));
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
    await Future<void>.delayed(Duration(milliseconds: _delayMs));
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
    await Future<void>.delayed(Duration(milliseconds: _delayMs + 400));
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
}

/// Access point for the rest of the app.
FinanceRepository getRepository() => MockFinanceRepository();

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

  Future<Map<String, dynamic>> models() => _get('/models') as Future<Map<String, dynamic>>;

  Future<List<Map<String, dynamic>>> sample(String model) async {
    final json = await _get('/sample/$model') as Map<String, dynamic>;
    return (json['samples'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> predict(String model, Map<String, double> features) =>
      _post('/predict/$model', {'features': features}) as Future<Map<String, dynamic>>;

  Future<Map<String, dynamic>> explain(String model, Map<String, double> features) =>
      _post('/explain/$model', {'features': features}) as Future<Map<String, dynamic>>;

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