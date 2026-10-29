import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

/// Represents a single SMS message read from the device inbox.
class InboxSms {
  /// Platform SMS id, when the device exposes one. Used as the stable identity
  /// of the message across refreshes, month filters and pagination.
  final int? id;
  final String address; // sender (bank name / number)
  final String body;
  final DateTime date;

  const InboxSms({
    this.id,
    required this.address,
    required this.body,
    required this.date,
  });

  /// Stable key for per-message UI state. Indices cannot be used because the
  /// visible list is filtered by month and grows when older pages load.
  String get key => id != null
      ? 'id:$id'
      : '${date.microsecondsSinceEpoch}:${address.hashCode}:${body.hashCode}';

  DateTime get day => DateTime(date.year, date.month, date.day);

  DateTime get month => DateTime(date.year, date.month);
}

/// One page of inbox scanning.
class InboxScan {
  /// Bank/transaction messages found in this page, newest first.
  final List<InboxSms> messages;

  /// Raw inbox offset the next scan should start from. This is *not* the
  /// number of bank messages, because non-bank SMS are filtered out.
  final int nextStart;

  /// Whether the device may hold older messages still to scan.
  final bool hasMore;

  const InboxScan({
    required this.messages,
    required this.nextStart,
    required this.hasMore,
  });

  static const InboxScan empty =
      InboxScan(messages: <InboxSms>[], nextStart: 0, hasMore: false);
}

/// Service that reads the device SMS inbox and filters likely bank/transaction
/// messages using keyword heuristics before sending them to the classifier.
class SmsInboxService {
  SmsInboxService();

  /// `flutter_sms_inbox` caps a single query window at 1,000 messages.
  static const int maxWindow = 1000;

  /// Default page size. 500 keeps the first load fast while leaving room to
  /// page further back (up to [maxWindow]) when the user browses older months.
  static const int defaultPageSize = 500;

  SmsQuery? _query;
  SmsQuery get _smsQuery => _query ??= SmsQuery();

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

  /// True when the user selected "Don't allow" permanently, so the system
  /// dialog will no longer appear and Settings must be used instead.
  Future<bool> isPermanentlyDenied() async {
    final status = await Permission.sms.status;
    return status.isPermanentlyDenied;
  }

  /// Opens the OS app settings page so the user can grant SMS access.
  Future<bool> openSettings() => openAppSettings();

  /// Scan a page of the inbox and return only bank/transaction messages.
  ///
  /// [start] is the raw inbox offset to resume from (as returned by a previous
  /// [InboxScan.nextStart]); [count] is how many raw messages to scan. The
  /// device does not support querying by date, so the screen filters the
  /// returned messages by month/year.
  Future<InboxScan> scanBankSms({
    int start = 0,
    int count = defaultPageSize,
  }) async {
    final granted = await requestPermission();
    if (!granted) throw PermissionDeniedException();

    final size = count <= 0
        ? defaultPageSize
        : (count > maxWindow ? maxWindow : count);

    final raw = await _smsQuery.querySms(
      kinds: <SmsQueryKind>[SmsQueryKind.inbox],
      start: start,
      count: size,
    );

    final filtered = <InboxSms>[];
    for (final msg in raw) {
      final body = msg.body ?? '';
      final address = msg.sender ?? '';
      final date = msg.date ?? msg.dateSent;
      if (date == null) continue;
      if (_bankKeywords.hasMatch(body) && !_spamKeywords.hasMatch(body)) {
        filtered.add(InboxSms(
          id: msg.id,
          address: address,
          body: body,
          date: date,
        ));
      }
    }

    filtered.sort((a, b) => b.date.compareTo(a.date));

    final consumed = start + raw.length;
    return InboxScan(
      messages: filtered,
      nextStart: consumed,
      // The plugin cannot page past its 1,000-message window.
      hasMore: raw.length >= size && consumed < maxWindow,
    );
  }
}

class PermissionDeniedException implements Exception {
  @override
  String toString() => 'SMS permission denied by user.';
}
