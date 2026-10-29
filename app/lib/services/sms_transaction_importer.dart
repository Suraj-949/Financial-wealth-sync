import '../models/models.dart';
import 'finance_repository.dart';

/// Converts an approved bank SMS into a ledger transaction.
class SmsTransactionImporter {
  SmsTransactionImporter._();

  static final _amountPattern = RegExp(
    r'(?:₹|rs\.?|inr|usd|\$)\s*([0-9,]+(?:\.\d{1,2})?)',
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

    return Transaction(
      id: 'sms-${date.microsecondsSinceEpoch}-${sms.hashCode}',
      merchant: merchant == null || merchant.isEmpty ? sender : merchant,
      category: type == TxnType.income ? TxnCategory.income : TxnCategory.others,
      type: type,
      amount: amount,
      date: date,
      note: 'Added from bank SMS',
    );
  }

  static Future<void> import({
    required FinanceRepository repository,
    required String sms,
    required String sender,
    required DateTime date,
    required TxnType type,
  }) {
    return repository.addTransaction(
      fromSms(sms: sms, sender: sender, date: date, type: type),
    );
  }
}