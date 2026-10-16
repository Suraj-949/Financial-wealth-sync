import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/models.dart';
import '../../services/finance_repository.dart';
import '../../services/sms_inbox_service.dart';
import '../../widgets/common.dart';

/// Interactive front-end for the two-stage SMS pipeline.
///
/// Stage 1 filters spam/noise; stage 2 labels legitimate transactions as
/// credit/debit/other. Now supports auto-fetching from the device inbox.
class SmsClassifierScreen extends StatefulWidget {
  const SmsClassifierScreen({super.key, this.repository});

  final FinanceRepository? repository;

  @override
  State<SmsClassifierScreen> createState() => _SmsClassifierScreenState();
}

class _SmsClassifierScreenState extends State<SmsClassifierScreen>
    with SingleTickerProviderStateMixin {
  late final FinanceRepository _repo =
      widget.repository ?? getApiRepository();
  final _smsService = SmsInboxService();
  final TextEditingController _controller = TextEditingController();

  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  SmsClassification? _result;
  bool _loading = false;
  String? _error;

  // Inbox tab state
  List<InboxSms> _inboxMessages = [];
  bool _loadingInbox = false;
  String? _inboxError;
  bool _permissionGranted = false;
  final Map<int, SmsClassification> _inboxResults = {};
  final Map<int, bool> _classifyingIndex = {};

  static const _examples = <String>[
    'ALERT: Acct *112 has been credited with USD 450.00.',
    'You spent USD 4.50 at McDonalds.',
    r'Congratulations! You won a lottery of $1,000,000! Call now.',
    "Hey, let's catch up over coffee tonight.",
  ];

  @override
  void dispose() {
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // â”€â”€ Manual classify â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _classify() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repo.classifySms(text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
      _showTransactionNotification(result);
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

  // â”€â”€ Inbox fetch â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _fetchInbox() async {
    setState(() {
      _loadingInbox = true;
      _inboxError = null;
      _inboxResults.clear();
    });
    try {
      final msgs = await _smsService.fetchBankSms(limit: 100);
      if (!mounted) return;
      setState(() {
        _inboxMessages = msgs;
        _loadingInbox = false;
        _permissionGranted = true;
      });
    } on PermissionDeniedException {
      if (!mounted) return;
      setState(() {
        _loadingInbox = false;
        _inboxError = 'SMS permission denied. Please allow in Settings.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingInbox = false;
        _inboxError = e.toString();
      });
    }
  }

  Future<void> _classifyInboxMessage(int index) async {
    final text = _inboxMessages[index].body;
    setState(() => _classifyingIndex[index] = true);
    try {
      final result = await _repo.classifySms(text);
      if (!mounted) return;
      setState(() {
        _inboxResults[index] = result;
        _classifyingIndex[index] = false;
      });
      _showTransactionNotification(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _classifyingIndex[index] = false);
    }
  }

  void _showTransactionNotification(SmsClassification result) {
    if (!result.isTransaction) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Transaction SMS detected: ${result.displayCategory}.',
        ),
      ),
    );
  }
  Future<void> _classifyAll() async {
    for (int i = 0; i < _inboxMessages.length; i++) {
      if (!_inboxResults.containsKey(i)) {
        await _classifyInboxMessage(i);
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
            Tab(icon: Icon(Icons.inbox, size: 18), text: 'Inbox'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildManualTab(),
          _buildInboxTab(),
        ],
      ),
    );
  }

  // â”€â”€ Manual Tab â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
                  label: Text(_loading ? 'Classifyingâ€¦' : 'Classify'),
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

  // â”€â”€ Inbox Tab â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildInboxTab() {
    if (!_permissionGranted && _inboxMessages.isEmpty) {
      return _buildPermissionPrompt();
    }

    return Column(
      children: [
        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_inboxMessages.length} bank SMS found',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13),
                ),
              ),
              TextButton.icon(
                onPressed: _loadingInbox ? null : _fetchInbox,
                icon: _loadingInbox
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed:
                    _loadingInbox || _inboxMessages.isEmpty
                        ? null
                        : _classifyAll,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.auto_awesome, size: 15),
                label: const Text('Classify All'),
              ),
            ],
          ),
        ),
        if (_inboxError != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorState(
                message: _inboxError!, onRetry: _fetchInbox),
          )
        else if (_loadingInbox)
          const Expanded(
              child: Center(child: CircularProgressIndicator()))
        else if (_inboxMessages.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'No bank/transaction SMS found in the last 90 days.',
                style:
                    TextStyle(color: AppColors.textMuted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _inboxMessages.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: 10),
              itemBuilder: (_, i) => _InboxMessageCard(
                sms: _inboxMessages[i],
                result: _inboxResults[i],
                classifying: _classifyingIndex[i] == true,
                onClassify: () => _classifyInboxMessage(i),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPermissionPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sms_outlined,
                  color: AppColors.accent, size: 36),
            ),
            const SizedBox(height: 20),
            const Text('Auto-fetch Bank SMS',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text(
              'WealthSync will read your SMS inbox, filter bank/transaction '
              'messages, and classify them using AI â€” all on-device or via '
              'the local backend.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13.5,
                  height: 1.5),
            ),
            const SizedBox(height: 8),
            const Text(
              'Only messages matching bank keywords are processed.\n'
              'No data leaves your device without your consent.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loadingInbox ? null : _fetchInbox,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: _loadingInbox
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.inbox_outlined),
                label: Text(_loadingInbox
                    ? 'Loading inboxâ€¦'
                    : 'Allow & Load Inbox'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Inbox Message Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _InboxMessageCard extends StatelessWidget {
  const _InboxMessageCard({
    required this.sms,
    required this.onClassify,
    this.result,
    this.classifying = false,
  });

  final InboxSms sms;
  final SmsClassification? result;
  final bool classifying;
  final VoidCallback onClassify;

  @override
  Widget build(BuildContext context) {
    final hasResult = result != null;
    final approved = hasResult && result!.isTransaction;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: sender + date
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  sms.address,
                  style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(sms.date),
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // SMS body
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
          // Result or Classify button
          if (classifying)
            const Row(children: [
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Classifyingâ€¦',
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
            ])
          else if (hasResult)
            Row(
              children: [
                Pill(
                  approved ? 'Transaction' : 'Spam/Other',
                  color: approved ? AppColors.income : AppColors.danger,
                  filled: true,
                  icon: approved
                      ? Icons.check_circle
                      : Icons.block,
                ),
                const SizedBox(width: 6),
                Pill(result!.displayCategory, color: AppColors.ai),
                const Spacer(),
                Text(
                  '${result!.confidence.toStringAsFixed(0)}% conf.',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            )
          else
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

  static String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// â”€â”€ Shared widgets (kept from original) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ExampleChip extends StatelessWidget {
  const _ExampleChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = text.length > 34 ? '${text.substring(0, 34)}â€¦' : text;
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
