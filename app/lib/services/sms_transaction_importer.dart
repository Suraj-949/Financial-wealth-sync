import '../models/models.dart';
import 'finance_repository.dart';

/// Converts an approved bank SMS into a ledger transaction.
class SmsTransactionImporter {
  SmsTransactionImporter._();

  static final _amountPattern = RegExp(
    '(?:${String.fromCharCode(0x20b9)}|rs\\.?|inr|usd|\\\$)\\s*([0-9,]+(?:\\.\\d{1,2})?)',
    caseSensitive: false,
  );
  static final _merchantPattern = RegExp(
    r'\b(?:at|to|from|for)\s+([A-Za-z][A-Za-z0-9 &._-]{1,40})',
    caseSensitive: false,
  );

  static Transaction fromSms({
    required String sms,
    required String sender,
    required DateTime date,
    required TxnType type,
    String? messageId,
  }) {
    final amountMatch = _amountPattern.firstMatch(sms);
    if (amountMatch == null) {
      throw const FormatException('No transaction amount was found in this SMS.');
    }

    final amount = double.tryParse(amountMatch.group(1)!.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      throw const FormatException('The amount in this SMS is not valid.');
    }

    final merchantMatch = _merchantPattern.firstMatch(sms);
    final merchant = merchantMatch?.group(1)?.trim();
    final identity = messageId ?? '${date.toIso8601String()}|$sender|$sms';
    final stableId = _stableHash(identity);

    return Transaction(
      id: 'sms-$stableId',
      merchant: merchant == null || merchant.isEmpty ? sender : merchant,
      category: type == TxnType.income ? TxnCategory.income : _expenseCategory(sms),
      type: type,
      amount: amount,
      date: date,
      note: 'Added from bank SMS',
    );
  }

  static TxnCategory _expenseCategory(String sms) {
    final text = sms.toLowerCase();
    if (_containsAny(text, const [
      'swiggy', 'zomato', 'eats', 'feast', 'restaurant', 'food', 'cafe',
      'coffee', 'bakery', 'dining',
    ])) {
      return TxnCategory.food;
    }
    if (_containsAny(text, const [
      'uber', 'ola', 'rapido', 'petrol', 'fuel', 'metro', 'train', 'bus',
      'taxi', 'cab', 'parking',
    ])) {
      return TxnCategory.transport;
    }
    if (_containsAny(text, const [
      'electricity', 'water bill', 'gas bill', 'broadband', 'recharge',
      'mobile bill', 'internet bill', 'insurance', 'emi', 'rent',
    ])) {
      return TxnCategory.bills;
    }
    if (_containsAny(text, const [
      'movie', 'cinema', 'netflix', 'spotify', 'concert', 'theatre',
      'gaming',
    ])) {
      return TxnCategory.entertainment;
    }
    if (_containsAny(text, const [
      'amazon', 'flipkart', 'myntra', 'shopping', 'retail', 'store',
      'printbuddy',
    ])) {
      return TxnCategory.shopping;
    }
    return TxnCategory.others;
  }

  static bool _containsAny(String text, List<String> terms) =>
      terms.any(text.contains);

  static Future<void> import({
    required FinanceRepository repository,
    required String sms,
    required String sender,
    required DateTime date,
    required TxnType type,
    String? messageId,
  }) {
    return repository.addTransaction(
      fromSms(
        sms: sms,
        sender: sender,
        date: date,
        type: type,
        messageId: messageId,
      ),
    );
  }

  // A deterministic ID lets the repository's upsert overwrite the same SMS
  // record on later scans instead of creating duplicate ledger entries.
  static String _stableHash(String value) {
    var first = 0x811c9dc5;
    var second = 0x9e3779b9;
    for (final unit in value.codeUnits) {
      first = ((first ^ unit) * 0x01000193) & 0xffffffff;
      second = ((second ^ unit) * 0x85ebca6b) & 0xffffffff;
    }
    return '${first.toRadixString(16).padLeft(8, '0')}${second.toRadixString(16).padLeft(8, '0')}';
  }
}
