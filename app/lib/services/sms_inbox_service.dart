import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

/// Represents a single SMS message read from the device inbox.
class InboxSms {
  final String address; // sender (bank name / number)
  final String body;
  final DateTime date;

  const InboxSms({
    required this.address,
    required this.body,
    required this.date,
  });
}

/// Service that reads the device SMS inbox and filters likely bank/transaction
/// messages using keyword heuristics before sending them to the classifier.
class SmsInboxService {
  static final SmsInboxService _instance = SmsInboxService._internal();
  factory SmsInboxService() => _instance;
  SmsInboxService._internal();

  final SmsQuery _query = SmsQuery();

  // ── Bank keyword patterns (common Indian & global banks / keywords) ────────
  static final _bankKeywords = RegExp(
    r'\b(credited|debited|deposited|withdrawn|transfer|txn|transaction|'
    r'payment|paid|received|spent|balance|a\/c|acct|account|'
    r'upi|neft|rtgs|imps|ifsc|otp|inr|rs\.|rupee|'
    r'hdfc|icici|sbi|axis|kotak|pnb|bob|canara|union|'
    r'amazon|flipkart|paytm|phonepe|gpay|swiggy|zomato)\b',
    caseSensitive: false,
  );

  // ── Spam / noise filters ──────────────────────────────────────────────────
  static final _spamKeywords = RegExp(
    r'\b(lottery|won|prize|offer|discount|sale|click|link|verify|'
    r'congratulation|free|gift|earn|investment opportunity)\b',
    caseSensitive: false,
  );

  /// Request READ_SMS permission. Returns true if granted.
  Future<bool> requestPermission() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  /// Check if permission is already granted (no dialog).
  Future<bool> hasPermission() async {
    return await Permission.sms.isGranted;
  }

  /// Fetch the last 90 days of SMS and return only bank/transaction messages.
  Future<List<InboxSms>> fetchBankSms({int limit = 200}) async {
    final granted = await requestPermission();
    if (!granted) throw PermissionDeniedException();

    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    final messages = await _query.querySms(
      kinds: [SmsQueryKind.inbox],
      count: 500, // fetch more, then filter
    );

    final filtered = <InboxSms>[];

    for (final msg in messages) {
      if (filtered.length >= limit) break;
      final body = msg.body ?? '';
      final address = msg.sender ?? '';
      final date = msg.date ?? DateTime(2000);

      if (date.isBefore(cutoff)) continue;
      if (_bankKeywords.hasMatch(body) && !_spamKeywords.hasMatch(body)) {
        filtered.add(InboxSms(address: address, body: body, date: date));
      }
    }

    return filtered;
  }
}

class PermissionDeniedException implements Exception {
  @override
  String toString() => 'SMS permission denied by user.';
}
