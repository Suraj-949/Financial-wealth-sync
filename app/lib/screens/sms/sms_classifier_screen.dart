import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../models/models.dart';
import '../../services/finance_repository.dart';
import '../../services/sms_inbox_service.dart';
import '../../services/sms_transaction_importer.dart';
import '../../widgets/common.dart';

/// Interactive front-end for the two-stage SMS pipeline.
///
/// Stage 1 filters spam/noise; stage 2 labels legitimate transactions as
/// credit/debit/other. The Timeline tab keeps every fetched bank SMS with its
/// full date and lets the user step back through months and years.
class SmsClassifierScreen extends StatefulWidget {
  const SmsClassifierScreen({
    super.key,
    this.repository,
    this.inboxService,
  });

  final FinanceRepository? repository;
  final SmsInboxService? inboxService;

  @override
  State<SmsClassifierScreen> createState() => _SmsClassifierScreenState();
}

class _SmsClassifierScreenState extends State<SmsClassifierScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final FinanceRepository _repo =
      widget.repository ?? getApiRepository();
  late final SmsInboxService _smsService =
      widget.inboxService ?? SmsInboxService();
  final TextEditingController _controller = TextEditingController();

  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  static final _monthFormat = DateFormat('MMMM yyyy');
  static final _monthShort = DateFormat('MMM');
  static final _shortDateFormat = DateFormat('d MMM yyyy');
  static final _moneyCue = RegExp(
    r'(?:₹|rs\.?|inr|\$)\s*[0-9][0-9,]*(?:\.\d{1,2})?',
    caseSensitive: false,
  );
  static final _accountCue = RegExp(
    r'\b(?:a/?c|account|upi|neft|imps|rtgs|txn|transaction)\b',
    caseSensitive: false,
  );
  static final _debitCue = RegExp(
    r'\b(?:sent|debited|deducted|withdrawn|spent|paid|purchased)\b',
    caseSensitive: false,
  );
  static final _creditCue = RegExp(
    r'\b(?:credited|deposited|received|refunded|reversed)\b',
    caseSensitive: false,
  );

  SmsClassification? _result;
  bool _loading = false;
  String? _error;

  // ── Timeline state ────────────────────────────────────────────────────────
  final List<InboxSms> _inboxMessages = [];
  final Map<String, SmsClassification> _inboxResults = {};
  final Set<String> _classifying = {};
  final Set<String> _imported = {};
  StreamSubscription<InboxSms>? _incomingSmsSubscription;

  bool _permissionGranted = false;
  bool _permissionPermanentlyDenied = false;
  bool _loadingInbox = false;
  bool _loadingOlder = false;
  bool _classifyingAll = false;
  String? _inboxError;
  int _nextScanStart = 0;
  bool _hasOlder = false;

  DateTime _selectedMonth = _currentMonth;
  bool _monthPickedByUser = false;

  static DateTime get _currentMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  static const _examples = <String>[
    'ALERT: Acct *112 has been credited with USD 450.00.',
    'You spent USD 4.50 at McDonalds.',
    r'Congratulations! You won a lottery of $1,000,000! Call now.',
    "Hey, let's catch up over coffee tonight.",
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (defaultTargetPlatform == TargetPlatform.android) {
      _incomingSmsSubscription = _smsService.incomingMessages.listen(
        _handleIncomingSms,
        onError: (Object error) {
          if (mounted) _showSnack('Incoming SMS listener error: $error');
        },
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchInbox();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _permissionGranted &&
        !_loadingInbox &&
        !_loadingOlder) {
      _fetchInbox();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingSmsSubscription?.cancel();
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Manual classify ───────────────────────────────────────────────────────

  Future<void> _classify() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = _resolveDirectionFromStrongSmsCues(
        await _repo.classifySms(text),
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
      await _processInboxClassification(
        InboxSms(
          address: 'Manual SMS',
          body: text,
          date: DateTime.now(),
        ),
        result,
        notify: true,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _useExample(String text) {
    _controller.text = text;
    _controller.selection =
        TextSelection.collapsed(offset: text.length);
    setState(() {});
  }

  // ── Inbox fetch / timeline ────────────────────────────────────────────────

  DateTime? get _latestDataMonth => _inboxMessages.isEmpty
      ? null
      : DateTime(
          _inboxMessages.first.date.year,
          _inboxMessages.first.date.month,
        );

  List<InboxSms> get _monthMessages => _inboxMessages
      .where((m) =>
          m.date.year == _selectedMonth.year &&
          m.date.month == _selectedMonth.month)
      .toList();

  bool get _canGoForward => _selectedMonth.isBefore(_currentMonth);

  Future<void> _fetchInbox({bool older = false}) async {
    if (_loadingInbox || _loadingOlder) return;
    if (older && !_hasOlder) return;

    setState(() {
      if (older) {
        _loadingOlder = true;
      } else {
        _loadingInbox = true;
        _inboxError = null;
      }
    });

    final previousCount = _inboxMessages.length;

    try {
      final scan = await _smsService.scanBankSms(
        start: older ? _nextScanStart : 0,
      );
      if (!mounted) return;
      setState(() {
        _mergeMessages(scan.messages);
        _nextScanStart = scan.nextStart;
        _hasOlder = scan.hasMore;
        _permissionGranted = true;
        _permissionPermanentlyDenied = false;
        _inboxError = null;
        _loadingInbox = false;
        _loadingOlder = false;
        if (!_monthPickedByUser) {
          _selectedMonth = _latestDataMonth ?? _currentMonth;
        }
      });

      // Loading the inbox also runs the classifier and imports valid
      // credit/debit messages, so they reach the ledger without a second tap.
      final pending = scan.messages
          .where((message) => !_inboxResults.containsKey(message.key))
          .toList();
      for (final message in pending) {
        if (!mounted) return;
        await _classifyInbox(message, notify: false);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      if (pending.isNotEmpty && mounted) {
        final saved = pending
            .where((message) => _imported.contains(message.key))
            .length;
        _showSnack(
          saved > 0
              ? 'Saved $saved detected transaction${saved == 1 ? '' : 's'} to the ledger.'
              : 'No credit/debit transactions were saved. Check Demo mode and database connection.',
        );
      }

      if (older && _inboxMessages.length == previousCount) {
        _showSnack('No older bank SMS found on this device.');
      }
    } on PermissionDeniedException {
      final permanent = await _smsService.isPermanentlyDenied();
      if (!mounted) return;
      setState(() {
        _loadingInbox = false;
        _loadingOlder = false;
        _permissionGranted = false;
        _permissionPermanentlyDenied = permanent;
        _inboxError = permanent
            ? 'SMS access is blocked. Allow it from Settings to load your timeline.'
            : 'SMS permission was denied. Allow access to load your bank SMS.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingInbox = false;
        _loadingOlder = false;
        _inboxError = e.toString();
      });
    }
  }

  /// Merges a new page into the timeline, de-duplicating by stable SMS key and
  /// keeping the list newest-first.
  void _mergeMessages(List<InboxSms> messages) {
    final byKey = <String, InboxSms>{
      for (final message in _inboxMessages) message.key: message,
    };
    for (final message in messages) {
      byKey[message.key] = message;
    }
    _inboxMessages
      ..clear()
      ..addAll(byKey.values)
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _handleIncomingSms(InboxSms sms) async {
    if (!_permissionGranted || !_smsService.isBankSmsCandidate(sms.body)) return;
    if (_inboxMessages.any((message) => message.key == sms.key)) return;
    if (!mounted) return;
    setState(() {
      _mergeMessages([sms]);
      if (!_monthPickedByUser) {
        _selectedMonth = DateTime(sms.date.year, sms.date.month);
      }
    });
    await _classifyInbox(sms);
  }

  void _stepMonth(int delta) {
    final next = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    if (next.isAfter(_currentMonth)) return;
    setState(() {
      _selectedMonth = DateTime(next.year, next.month);
      _monthPickedByUser = true;
    });
  }

  Future<void> _pickMonth() async {
    var year = _selectedMonth.year;
    final now = DateTime.now();
    final counts = <String, int>{};
    for (final message in _inboxMessages) {
      final key = '${message.date.year}-${message.date.month}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final latest = _latestDataMonth;

    final picked = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              titlePadding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
              title: Row(
                children: [
                  IconButton(
                    onPressed: () => setDialogState(() => year--),
                    tooltip: 'Previous year',
                    icon: const Icon(Icons.chevron_left),
                    color: AppColors.textMuted,
                  ),
                  Expanded(
                    child: Text(
                      '$year',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: year >= now.year
                        ? null
                        : () => setDialogState(() => year++),
                    tooltip: 'Next year',
                    icon: const Icon(Icons.chevron_right),
                    color: AppColors.textMuted,
                    disabledColor: AppColors.line,
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1.55,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: [
                        for (var month = 1; month <= 12; month++)
                          _MonthTile(
                            label: _monthShort.format(DateTime(year, month)),
                            count: counts['$year-$month'] ?? 0,
                            selected: year == _selectedMonth.year &&
                                month == _selectedMonth.month,
                            disabled: DateTime(year, month)
                                .isAfter(DateTime(now.year, now.month)),
                            onTap: () => Navigator.of(dialogContext)
                                .pop(DateTime(year, month)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(dialogContext)
                                .pop(DateTime(now.year, now.month)),
                            child: const Text('This month'),
                          ),
                        ),
                        if (latest != null)
                          Expanded(
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(latest),
                              child: const Text('Latest SMS'),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month);
      _monthPickedByUser = true;
    });
  }

  Future<void> _classifyInbox(InboxSms sms, {bool notify = true}) async {
    if (_classifying.contains(sms.key)) return;
    setState(() => _classifying.add(sms.key));
    try {
      final result = _resolveDirectionFromStrongSmsCues(
        await _repo.classifySms(sms.body),
      );
      if (!mounted) return;
      setState(() {
        _inboxResults[sms.key] = result;
        _classifying.remove(sms.key);
      });
      await _processInboxClassification(sms, result, notify: notify);
    } catch (e) {
      if (!mounted) return;
      setState(() => _classifying.remove(sms.key));
      if (notify) _showSnack('Could not classify this SMS: $e');
    }
  }

  Future<void> _classifyMonth() async {
    final targets = _monthMessages
        .where((message) =>
            !_inboxResults.containsKey(message.key) &&
            !_classifying.contains(message.key))
        .toList();
    if (targets.isEmpty) {
      _showSnack('Every SMS in ${_monthFormat.format(_selectedMonth)} is already classified.');
      return;
    }

    setState(() => _classifyingAll = true);
    for (final message in targets) {
      if (!mounted) return;
      await _classifyInbox(message, notify: false);
      // Let the UI breathe between requests so progress stays visible.
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    if (!mounted) return;
    setState(() => _classifyingAll = false);
    _showSnack('Classified ${targets.length} SMS in ${_monthFormat.format(_selectedMonth)}.');
  }

  SmsClassification _resolveDirectionFromStrongSmsCues(
    SmsClassification result,
  ) {
    if (result.isSpam || !result.isTransaction) return result;
    final text = result.text;
    if (!_moneyCue.hasMatch(text) || !_accountCue.hasMatch(text)) return result;

    final debit = _debitCue.hasMatch(text);
    final credit = _creditCue.hasMatch(text);
    if (debit == credit) return result;

    final category = debit ? 'debit' : 'credit';
    return SmsClassification(
      text: result.text,
      isSpam: false,
      isTransaction: true,
      status: result.status,
      category: category,
      displayCategory: debit ? 'Debit' : 'Credit',
      confidence: 100,
      spamProbability: result.spamProbability,
      categoryProbabilities: {category: 100},
      resolvedFromText: true,
    );
  }

  bool _canAutoImport(SmsClassification result) =>
      !result.isSpam &&
      result.isTransaction &&
      (result.isCredit || result.isDebit);

  Future<void> _processInboxClassification(
    InboxSms sms,
    SmsClassification result, {
    required bool notify,
  }) async {
    if (_canAutoImport(result)) {
      await _importDetectedTransaction(sms, result, notify: notify);
      return;
    }
    if (notify) {
      _showSnack(
        result.isSpam
            ? 'Model classified this SMS as spam; it was not saved.'
            : 'Model did not classify this SMS as credit or debit; it was not saved.',
      );
    }
  }

  Future<void> _importDetectedTransaction(
    InboxSms sms,
    SmsClassification result, {
    required bool notify,
  }) async {
    if (_imported.contains(sms.key)) return;
    final type = result.isCredit ? TxnType.income : TxnType.expense;
    await _saveInboxTransaction(sms, result, type, notify: notify);
  }

  Future<void> _saveInboxTransaction(
    InboxSms sms,
    SmsClassification result,
    TxnType type, {
    required bool notify,
  }) async {
    if (_imported.contains(sms.key)) return;
    if (demoModeEnabled) {
      _showSnack('Demo mode is on. Turn it off in Settings to save to PostgreSQL.');
      return;
    }
    try {
      await SmsTransactionImporter.import(
        repository: _repo,
        sms: result.text,
        sender: sms.address,
        date: sms.date,
        type: type,
        messageId: sms.key,
      );
      if (!mounted) return;
      setState(() => _imported.add(sms.key));
      if (notify) {
        _showSnack(
          '${type == TxnType.income ? 'Credit' : 'Expense'} saved to Transactions.',
        );
      }
    } on FormatException catch (error) {
      if (notify) _showSnack(error.message);
    } catch (error) {
      if (notify) _showSnack('Could not save the transaction: $error');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openSettings() async {
    await _smsService.openSettings();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.mark_email_unread_outlined,
                size: 18, color: AppColors.ai),
            SizedBox(width: 8),
            Text('SMS Payments'),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(icon: Icon(Icons.edit_note, size: 18), text: 'Manual'),
            Tab(icon: Icon(Icons.timeline, size: 18), text: 'Timeline'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildManualTab(),
          _buildTimelineTab(),
        ],
      ),
    );
  }

  // ── Manual tab ────────────────────────────────────────────────────────────

  Widget _buildManualTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
      children: [
        const _PipelineNote(),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Paste a bank / transaction SMS',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                minLines: 3,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                    height: 1.4),
                decoration: InputDecoration(
                  hintText:
                      'e.g. Your account XX445 has been credited with USD 120.00',
                  hintStyle: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.surfaceAlt,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.accent),
                  ),
                ),
                onSubmitted: (_) => _classify(),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final example in _examples)
                    _ExampleChip(
                      text: example,
                      onTap: () => _useExample(example),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _classify,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.bolt, size: 18),
                  label: Text(_loading ? 'Classifying…' : 'Classify'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          ErrorState(message: _error!, onRetry: _classify)
        else if (_loading)
          const Column(children: [
            Skeleton(height: 120, radius: 16),
            SizedBox(height: 12),
            Skeleton(height: 60, radius: 12),
          ])
        else if (_result != null)
          _ResultCard(result: _result!),
      ],
    );
  }

  // ── Timeline tab ──────────────────────────────────────────────────────────

  Widget _buildTimelineTab() {
    if (!_permissionGranted && _inboxMessages.isEmpty) {
      return _buildPermissionPrompt();
    }

    final messages = _monthMessages;

    return Column(
      children: [
        _buildTimelineToolbar(),
        _buildMonthNavigator(messages),
        if (_inboxError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ErrorState(
              message: _inboxError!,
              onRetry: () => _fetchInbox(),
            ),
          )
        else if (_loadingInbox)
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _fetchInbox(),
              color: AppColors.accent,
              child: messages.isEmpty
                  ? _buildEmptyMonth()
                  : _buildTimelineList(messages),
            ),
          ),
      ],
    );
  }

  Widget _buildTimelineToolbar() {
    final canClassify = _monthMessages
        .any((message) => !_inboxResults.containsKey(message.key));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_inboxMessages.length} bank SMS tracked',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_inboxMessages.isNotEmpty)
                  Text(
                    '${_shortDateFormat.format(_inboxMessages.last.date)}'
                    ' – '
                    '${_shortDateFormat.format(_inboxMessages.first.date)}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed:
                _loadingInbox || _loadingOlder ? null : () => _fetchInbox(),
            tooltip: 'Refresh inbox',
            icon: _loadingInbox && !_loadingOlder
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 20),
            color: AppColors.textMuted,
          ),
          FilledButton.icon(
            onPressed: _loadingInbox || _classifyingAll || !canClassify
                ? null
                : _classifyMonth,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: _classifyingAll
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.auto_awesome, size: 15),
            label: Text(_classifyingAll ? 'Classifying…' : 'Classify all'),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthNavigator(List<InboxSms> messages) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => _stepMonth(-1),
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left),
                  color: AppColors.textMuted,
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickMonth,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _monthFormat.format(_selectedMonth),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.expand_more,
                                  size: 17, color: AppColors.textMuted),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _monthSummary(messages),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _canGoForward ? () => _stepMonth(1) : null,
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right),
                  color: AppColors.textMuted,
                  disabledColor: AppColors.line,
                ),
              ],
            ),
            if (_hasOlder)
              TextButton.icon(
                onPressed:
                    _loadingOlder ? null : () => _fetchInbox(older: true),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  visualDensity: VisualDensity.compact,
                ),
                icon: _loadingOlder
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.history, size: 15),
                label: Text(
                  _loadingOlder ? 'Loading older SMS…' : 'Load older SMS',
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _monthSummary(List<InboxSms> messages) {
    if (messages.isEmpty) return 'No bank SMS this month';

    var credits = 0;
    var debits = 0;
    var classified = 0;
    for (final message in messages) {
      final result = _inboxResults[message.key];
      if (result == null) continue;
      classified++;
      if (result.isCredit) credits++;
      if (result.isDebit) debits++;
    }

    final parts = <String>['${messages.length} SMS'];
    if (credits > 0) {
      parts.add('$credits credit${credits == 1 ? '' : 's'}');
    }
    if (debits > 0) {
      parts.add('$debits debit${debits == 1 ? '' : 's'}');
    }
    if (classified == 0) {
      parts.add('not classified yet');
    } else if (classified < messages.length) {
      parts.add('${messages.length - classified} pending');
    }
    return parts.join(' · ');
  }

  Widget _buildTimelineList(List<InboxSms> messages) {
    final dayCounts = <String, int>{};
    for (final message in messages) {
      final key =
          '${message.date.year}-${message.date.month}-${message.date.day}';
      dayCounts[key] = (dayCounts[key] ?? 0) + 1;
    }

    final children = <Widget>[];
    DateTime? lastDay;
    for (final sms in messages) {
      if (lastDay == null || sms.day != lastDay) {
        lastDay = sms.day;
        children.add(_DayHeader(
          date: sms.date,
          count: dayCounts[
                  '${sms.date.year}-${sms.date.month}-${sms.date.day}'] ??
              1,
        ));
      }

      final result = _inboxResults[sms.key];
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _InboxMessageCard(
          sms: sms,
          result: result,
          classifying: _classifying.contains(sms.key),
          imported: _imported.contains(sms.key),
          eligible: result != null && _canAutoImport(result),
          onClassify: () => _classifyInbox(sms),
        ),
      ));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
      children: children,
    );
  }

  Widget _buildEmptyMonth() {
    final latest = _latestDataMonth;
    final hasHistory = _inboxMessages.isNotEmpty;
    final isLatestSelected = latest != null &&
        latest.year == _selectedMonth.year &&
        latest.month == _selectedMonth.month;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
      children: [
        const Icon(Icons.event_note_outlined,
            size: 44, color: AppColors.textMuted),
        const SizedBox(height: 12),
        Text(
          'No bank SMS in ${_monthFormat.format(_selectedMonth)}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hasHistory
              ? 'Step to another month, jump to a year, or load older messages to go further back.'
              : 'No bank or transaction messages were found in your inbox yet.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        if (latest != null && !isLatestSelected)
          Center(
            child: FilledButton.tonalIcon(
              onPressed: () => setState(() {
                _selectedMonth = latest;
                _monthPickedByUser = true;
              }),
              icon: const Icon(Icons.bolt, size: 16),
              label: Text('Go to ${_monthFormat.format(latest)}'),
            ),
          ),
        const SizedBox(height: 6),
        Center(
          child: TextButton.icon(
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month, size: 16),
            label: const Text('Choose month / year'),
          ),
        ),
        if (_hasOlder)
          Center(
            child: TextButton.icon(
              onPressed:
                  _loadingOlder ? null : () => _fetchInbox(older: true),
              icon: _loadingOlder
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history, size: 16),
              label: Text(_loadingOlder ? 'Loading…' : 'Load older SMS'),
            ),
          ),
      ],
    );
  }

  Widget _buildPermissionPrompt() {
    final denied = _inboxError != null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sms_outlined,
                  color: AppColors.accent, size: 36),
            ),
            const SizedBox(height: 20),
            const Text('Build your SMS timeline',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text(
              'WealthSync reads your SMS inbox, keeps only bank/transaction '
              'messages, and shows them in a dated timeline you can browse by '
              'month and year. Each message is classified on-device or via the '
              'local backend.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13.5,
                  height: 1.5),
            ),
            const SizedBox(height: 8),
            const Text(
              'Likely bank messages are classified automatically. With live mode on, '
              'transaction SMS text is sent to the configured backend for classification '
              'and valid transactions are saved to your finance database.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.4),
            ),
            if (denied) ...[
              const SizedBox(height: 14),
              Text(
                _inboxError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.danger, fontSize: 12.5, height: 1.4),
              ),
            ],
            const SizedBox(height: 24),
            if (_loadingInbox)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Requesting SMS access and loading your inbox...'),
                ],
              )
            else if (!denied)
              const Text(
                'SMS inbox loads automatically when you open this screen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
            if (_permissionPermanentlyDenied) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: const Text('Open app settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Timeline widgets ────────────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.count});

  final DateTime date;
  final int count;

  static final _format = DateFormat('EEE, d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    final prefix = diff == 0
        ? 'Today · '
        : diff == 1
            ? 'Yesterday · '
            : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$prefix${_format.format(date)}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '$count SMS',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthTile extends StatelessWidget {
  const _MonthTile({
    required this.label,
    required this.count,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasData = count > 0;
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: .22)
              : hasData
                  ? AppColors.surfaceAlt
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: disabled
                    ? AppColors.line
                    : hasData
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (hasData)
              Text(
                '$count',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Inbox message card ──────────────────────────────────────────────────────

class _InboxMessageCard extends StatelessWidget {
  const _InboxMessageCard({
    required this.sms,
    required this.onClassify,
    this.result,
    this.classifying = false,
    this.imported = false,
    this.eligible = false,
  });

  final InboxSms sms;
  final SmsClassification? result;
  final bool classifying;
  final bool imported;
  final bool eligible;
  final VoidCallback onClassify;

  static final _timeFormat = DateFormat('h:mm a');

  @override
  Widget build(BuildContext context) {
    final hasResult = result != null;
    final isTransaction = hasResult && eligible;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: sender + received time. The day header above the card
          // carries the full date, so the timestamp stays compact here.
          Row(
            children: [
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    sms.address.isEmpty ? 'Unknown sender' : sms.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Spacer(),
              const Icon(Icons.schedule, size: 13, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                _timeFormat.format(sms.date),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            sms.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                height: 1.4),
          ),
          const SizedBox(height: 10),
          if (classifying)
            const Row(children: [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Classifying…',
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
            ])
          else if (hasResult) ...[
            Row(
              children: [
                Pill(
                  imported
                      ? 'Saved'
                      : isTransaction
                          ? 'Transaction'
                          : 'Skipped by model',
                  color: imported || isTransaction
                      ? AppColors.income
                      : AppColors.danger,
                  filled: true,
                  icon: imported || isTransaction
                      ? Icons.check_circle
                      : Icons.block,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Pill(result!.displayCategory, color: AppColors.ai),
                  ),
                ),
                Text(
                  result!.resolvedFromText
                      ? 'Text cue'
                      : '${result!.confidence.toStringAsFixed(0)}% conf.',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
            if (imported) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: const Pill(
                  'Added to transactions',
                  color: AppColors.income,
                  icon: Icons.check_circle,
                ),
              ),
            ],
          ] else
            SizedBox(
              height: 32,
              child: OutlinedButton.icon(
                onPressed: onClassify,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.bolt, size: 14),
                label: const Text('Classify', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared widgets ──────────────────────────────────────────────────────────

class _ExampleChip extends StatelessWidget {
  const _ExampleChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = text.length > 34 ? '${text.substring(0, 34)}…' : text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: Text(label,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 12)),
      ),
    );
  }
}

class _PipelineNote extends StatelessWidget {
  const _PipelineNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, size: 16, color: AppColors.ai),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Two-stage model: first a spam/noise filter, then a credit / debit / other '
              'categoriser (TF-IDF + Naive Bayes). Confidence is shown per stage.',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final SmsClassification result;

  @override
  Widget build(BuildContext context) {
    final approved = result.isTransaction;
    final statusColor =
        approved ? AppColors.income : AppColors.danger;
    final sortedProbs = result.categoryProbabilities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill(
                approved ? 'Approved' : 'Discarded',
                color: statusColor,
                filled: true,
                icon: approved ? Icons.check_circle : Icons.block,
              ),
              const SizedBox(width: 8),
              Pill(result.displayCategory, color: AppColors.ai),
            ],
          ),
          const SizedBox(height: 14),
          _bar('Confidence', result.confidence, statusColor),
          const SizedBox(height: 10),
          _bar('Spam probability', result.spamProbability,
              AppColors.warning),
          const SizedBox(height: 14),
          if (sortedProbs.isNotEmpty) ...[
            const Text('Category breakdown',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final entry in sortedProbs)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _bar(
                    _titleCase(entry.key), entry.value, AppColors.savings),
              ),
            const SizedBox(height: 6),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('"${result.text}"',
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
  }

  Widget _bar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 12.5)),
            ),
            Text('${value.toStringAsFixed(1)}%',
                style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (value / 100).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: AppColors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  static String _titleCase(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}
