import 'package:intl/intl.dart';

/// INR formatting helpers (Indian digit grouping: 1,23,456).
class Formatters {
  static final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);
  static final _inrDec = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 2);
  static final _num = NumberFormat.decimalPattern('en_IN');
  static final _usd = NumberFormat.currency(locale: 'en_US', symbol: r'$', decimalDigits: 2);
  static final _plain = NumberFormat.currency(locale: 'en_US', symbol: '', decimalDigits: 2);

  static String inr(num value) => _inr.format(value);

  /// Formats [value] in the [currency] the value is actually denominated in
  /// (ISO 4217 code, e.g. `USD`, `INR`).
  ///
  /// The ML models forecast in USD while the rest of the dashboard is INR, so
  /// amounts must be rendered with their own symbol rather than forcing `₹`.
  /// Unknown codes fall back to `CODE 1,234.56` so nothing is ever silently
  /// shown with the wrong symbol.
  static String money(num value, String currency) {
    switch (currency.toUpperCase()) {
      case 'USD':
        return _usd.format(value);
      case 'INR':
        return _inr.format(value);
      default:
        return '${currency.toUpperCase()} ${_plain.format(value)}';
    }
  }

  static String inrDec(num value) => _inrDec.format(value);

  static String integer(num value) => _num.format(value);

  static String pct(num value, {int digits = 1}) => '${value.toStringAsFixed(digits)}%';

  static String signedPct(num value) {
    final s = pct(value.abs());
    return value >= 0 ? '↑ $s' : '↓ $s';
  }

  static String signedMoney(num value) =>
      value >= 0 ? '+${_inr.format(value)}' : '−${_inr.format(value.abs())}';

  static String dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    // Keep older entries unambiguous across year boundaries.
    if (d.year == now.year) return DateFormat('MMM d').format(d);
    return DateFormat('MMM d, yyyy').format(d);
  }

  static String timeLabel(DateTime d) => DateFormat('h:mm a').format(d);

  static String fullDate(DateTime d) => DateFormat('MMM d, yyyy').format(d);

  /// e.g. "May 20 – Jun 20, 2024"
  static String currentRange() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(const Duration(days: 31));
    return '${DateFormat('MMM d').format(start)} – ${DateFormat('MMM d, yyyy').format(end)}';
  }

  static String greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }
}