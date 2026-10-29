import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:wealthsync/screens/sms/sms_classifier_screen.dart';
import 'package:wealthsync/services/finance_repository.dart';
import 'package:wealthsync/services/sms_inbox_service.dart';

/// Inbox stand-in that never touches the platform channel.
class _FakeInboxService extends SmsInboxService {
  _FakeInboxService(this.messages);

  final List<InboxSms> messages;

  @override
  Future<InboxScan> scanBankSms({int start = 0, int count = 500}) async {
    if (start > 0) {
      return InboxScan(
        messages: const <InboxSms>[],
        nextStart: start,
        hasMore: false,
      );
    }
    return InboxScan(
      messages: messages,
      nextStart: messages.length,
      hasMore: false,
    );
  }
}

/// Pumps the screen, opens the Timeline tab and loads the fake inbox.
Future<void> _pumpTimeline(
  WidgetTester tester,
  _FakeInboxService inbox,
) async {
  final repo = MockFinanceRepository()..setDelay(0);
  await tester.pumpWidget(MaterialApp(
    home: SmsClassifierScreen(repository: repo, inboxService: inbox),
  ));
  await tester.tap(find.text('Timeline'));
  await tester.pumpAndSettle();

  final load = find.text('Allow & load inbox');
  if (load.evaluate().isNotEmpty) {
    await tester.tap(load);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('shows received dates for fetched bank SMS', (tester) async {
    final now = DateTime.now();
    final inbox = _FakeInboxService([
      InboxSms(
        id: 1,
        address: 'HDFC Bank',
        body: 'You spent USD 4.50 at McDonalds.',
        date: DateTime(now.year, now.month, 5, 10, 30),
      ),
      InboxSms(
        id: 2,
        address: 'SBI',
        body: 'Your account has been credited with USD 120.00.',
        date: DateTime(now.year, now.month, 3, 9, 15),
      ),
    ]);

    await _pumpTimeline(tester, inbox);

    expect(find.text('2 bank SMS tracked'), findsOneWidget);
    expect(
      find.text(DateFormat('MMMM yyyy').format(now)),
      findsOneWidget,
    );
    // Full date in the day header, time on the card.
    expect(
      find.textContaining(DateFormat('d MMM yyyy').format(inbox.messages.first.date)),
      findsWidgets,
    );
    expect(
      find.textContaining(DateFormat('h:mm a').format(inbox.messages.first.date)),
      findsWidgets,
    );
  });

  testWidgets('steps back to the previous month', (tester) async {
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1, 12, 18, 0);
    final inbox = _FakeInboxService([
      InboxSms(
        id: 1,
        address: 'HDFC Bank',
        body: 'You spent USD 4.50 at McDonalds.',
        date: DateTime(now.year, now.month, 5, 10, 30),
      ),
      InboxSms(
        id: 2,
        address: 'ICICI',
        body: 'You spent USD 20.00 at Amazon.',
        date: previousMonth,
      ),
    ]);

    await _pumpTimeline(tester, inbox);
    expect(find.textContaining('McDonalds'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();

    expect(
      find.text(DateFormat('MMMM yyyy').format(previousMonth)),
      findsOneWidget,
    );
    expect(find.textContaining('Amazon'), findsOneWidget);
    expect(find.textContaining('McDonalds'), findsNothing);
    expect(find.text('1 SMS · not classified yet'), findsOneWidget);
  });

  testWidgets('month picker highlights months that have SMS', (tester) async {
    final now = DateTime.now();
    final inbox = _FakeInboxService([
      InboxSms(
        id: 1,
        address: 'HDFC Bank',
        body: 'You spent USD 4.50 at McDonalds.',
        date: DateTime(now.year, now.month, 5, 10, 30),
      ),
    ]);

    await _pumpTimeline(tester, inbox);
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    // Year header + month labels are visible in the picker.
    expect(find.text('${now.year}'), findsOneWidget);
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
}
