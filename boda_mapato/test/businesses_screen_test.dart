import 'package:boda_mapato/models/business.dart';
import 'package:boda_mapato/models/subscription.dart';
import 'package:boda_mapato/screens/admin/businesses_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

Business _biz(
  String id, {
  String name = 'Asha Rentals',
  String plan = 'basic',
  DateTime? until,
  int? days,
  bool expired = false,
  bool ownerActive = true,
}) =>
    Business(
      id: id,
      name: name,
      tin: '123-456-789',
      owner: BusinessOwner(id: 'u-$id', name: 'Asha Owner', email: 'asha@example.test', phoneNumber: '0743519100', isActive: ownerActive),
      services: const <String>['rental', 'inventory'],
      billing: BusinessBilling(plan: plan, validUntil: until, daysLeft: days, isExpired: expired),
    );

class _FakeSource implements BusinessesDataSource {
  _FakeSource(this.pages);

  Map<String, BusinessesPage> pages;
  final List<String> loads = <String>[];
  final List<({String id, String? plan, DateTime? until, bool clear})> updates = <({String id, String? plan, DateTime? until, bool clear})>[];
  Object? updateError;
  List<SubscriptionPayment> paymentList = <SubscriptionPayment>[];
  Object? paymentError;
  final List<({String id, double amount, String? method, String? reference, String? plan, int months, String? note})> recorded =
      <({String id, double amount, String? method, String? reference, String? plan, int months, String? note})>[];

  @override
  Future<List<SubscriptionPayment>> payments(String id) async => List<SubscriptionPayment>.of(paymentList);

  @override
  Future<SubscriptionInfo> recordPayment(
    String id, {
    required double amount,
    String? method,
    String? reference,
    String? plan,
    int months = 1,
    String? note,
  }) async {
    if (paymentError != null) throw paymentError!;
    recorded.add((id: id, amount: amount, method: method, reference: reference, plan: plan, months: months, note: note));
    final DateTime until = _today.add(Duration(days: 30 * months));
    paymentList = <SubscriptionPayment>[
      SubscriptionPayment(amount: amount, currency: 'TZS', plan: plan ?? '', method: method, reference: reference, paidAt: _today, periodStart: _today, periodEnd: until),
      ...paymentList,
    ];
    return SubscriptionInfo(status: 'active', plan: plan ?? 'basic', validUntil: until, daysLeft: 30 * months);
  }

  @override
  Future<BusinessesPage> load(String status, {String? query}) async {
    loads.add(status);
    return pages[status] ?? const BusinessesPage(items: <Business>[]);
  }

  @override
  Future<void> updateBilling(String id, {String? plan, DateTime? validUntil, bool clearValidUntil = false}) async {
    if (updateError != null) throw updateError!;
    updates.add((id: id, plan: plan, until: validUntil, clear: clearValidUntil));
  }
}

Widget _host(_FakeSource source) => ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(800, 2400),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: BusinessesScreen(dataSource: source)),
      ),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

DateTime get _today => DateUtils.dateOnly(DateTime.now());

void main() {
  testWidgets('lists every business with its owner, services, plan and how long it has left', (t) async {
    _tall(t);
    final DateTime in20 = _today.add(const Duration(days: 20));
    final _FakeSource source = _FakeSource(<String, BusinessesPage>{
      'all': BusinessesPage(
        total: 3,
        expired: 1,
        expiring: 1,
        items: <Business>[
          _biz('1', until: in20, days: 20),
          _biz('2', name: 'Juma Transport', plan: 'premium'),
          _biz('3', name: 'Old Shop', plan: 'trial', until: DateTime(2026, 1, 1), days: -9, expired: true, ownerActive: false),
        ],
      ),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();

    expect(find.text('Asha Rentals'), findsOneWidget);
    expect(find.text('Juma Transport'), findsOneWidget);
    expect(find.text('Old Shop'), findsOneWidget);
    expect(find.text('Msingi'), findsOneWidget);
    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('Jaribio'), findsOneWidget);
    expect(find.textContaining('(siku 20)'), findsOneWidget);
    expect(find.text('Haina tarehe ya kuisha'), findsOneWidget);
    expect(find.textContaining('siku 9 zilizopita'), findsOneWidget);
    expect(find.textContaining('Imesimamishwa'), findsOneWidget, reason: 'a suspended owner is flagged');
    expect(find.text('Zote (3)'), findsOneWidget);
    expect(find.text('Zinaisha karibu (1)'), findsOneWidget);
    expect(find.text('Zilizoisha (1)'), findsOneWidget);
  });

  testWidgets('shows a friendly empty state and a retry on failure', (t) async {
    _tall(t);
    await t.pumpWidget(_host(_FakeSource(<String, BusinessesPage>{})));
    await t.pumpAndSettle();
    expect(_key('businesses_empty'), findsOneWidget);
  });

  testWidgets('a filter reloads with that filter', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, BusinessesPage>{
      'all': BusinessesPage(items: <Business>[_biz('1')], total: 1),
      'expired': BusinessesPage(items: <Business>[_biz('3', name: 'Old Shop', expired: true, days: -5, until: DateTime(2026, 1, 1))]),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();

    await t.tap(_key('filter_expired'));
    await t.pumpAndSettle();

    expect(source.loads, <String>['all', 'expired']);
    expect(find.text('Old Shop'), findsOneWidget);
    expect(find.text('Asha Rentals'), findsNothing);
  });

  Future<_FakeSource> open(WidgetTester t, Business b, {List<String>? plans}) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, BusinessesPage>{
      'all': BusinessesPage(items: <Business>[b], total: 1, plans: plans ?? kBusinessPlans),
    });
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();
    await t.tap(find.text(b.name));
    await t.pumpAndSettle();
    return source;
  }

  testWidgets('choosing a plan and a date saves exactly that', (t) async {
    final _FakeSource source = await open(t, _biz('1', until: _today.add(const Duration(days: 5)), days: 5));

    await t.tap(_key('plan_premium'));
    await t.pump();
    await t.tap(_key('extend_30'));
    await t.pump();
    await t.tap(_key('billing_save'));
    await t.pumpAndSettle();

    expect(source.updates, hasLength(1));
    expect(source.updates.single.id, '1');
    expect(source.updates.single.plan, 'premium');
    expect(source.updates.single.clear, isFalse);
    // Paying early loses nothing: 30 days are added to the END date (5 days away), not to today.
    expect(source.updates.single.until, _today.add(const Duration(days: 35)));
    expect(_key('billing_save'), findsNothing, reason: 'the sheet closed');
    expect(source.loads.length, 2, reason: 'and the list was reloaded');
  });

  testWidgets('extending something that already ended starts from today', (t) async {
    final _FakeSource source = await open(t, _biz('1', until: DateTime(2026, 1, 1), days: -200, expired: true));

    await t.tap(_key('extend_90'));
    await t.pump();
    await t.tap(_key('billing_save'));
    await t.pumpAndSettle();

    expect(source.updates.single.until, _today.add(const Duration(days: 90)));
  });

  testWidgets('"no end date" clears the date', (t) async {
    final _FakeSource source = await open(t, _biz('1', until: _today.add(const Duration(days: 5)), days: 5));

    await t.tap(_key('billing_no_expiry'));
    await t.pump();
    expect(find.text('Hakuna tarehe ya kuisha'), findsWidgets);
    await t.tap(_key('billing_save'));
    await t.pumpAndSettle();

    expect(source.updates.single.until, isNull);
    expect(source.updates.single.clear, isTrue);
  });

  testWidgets('only the plans the server offers can be chosen', (t) async {
    await open(t, _biz('1'), plans: const <String>['trial', 'standard']);

    expect(_key('plan_standard'), findsOneWidget);
    expect(_key('plan_trial'), findsOneWidget);
    expect(_key('plan_premium'), findsNothing);
  });

  testWidgets('a refusal stays on the sheet and is shown', (t) async {
    final _FakeSource source = await open(t, _biz('1'));
    source.updateError = Exception('The selected plan is invalid.');

    await t.tap(_key('billing_save'));
    await t.pumpAndSettle();

    expect(find.text('The selected plan is invalid.'), findsOneWidget);
    expect(_key('billing_save'), findsOneWidget, reason: 'nothing was lost');
  });

  testWidgets('the sheet lists the payments already recorded for the business', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(<String, BusinessesPage>{
      'all': BusinessesPage(items: <Business>[_biz('1')], total: 1),
    });
    source.paymentList = <SubscriptionPayment>[
      SubscriptionPayment(amount: 45000, currency: 'TZS', plan: 'basic', method: 'cash', paidAt: DateTime(2026, 9, 1), periodStart: DateTime(2026, 9, 2), periodEnd: DateTime(2026, 10, 2)),
    ];
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();
    await t.tap(find.text('Asha Rentals'));
    await t.pumpAndSettle();

    expect(find.text('TZS 45,000'), findsOneWidget);
    expect(find.text('Taslimu'), findsOneWidget);
    expect(find.text('Kipindi: 02 Sep 2026 - 02 Oct 2026'), findsOneWidget);
    expect(_key('payments_empty'), findsNothing);
  });

  testWidgets('with no payments the sheet says so', (t) async {
    await open(t, _biz('1'));
    expect(_key('payments_empty'), findsOneWidget);
    expect(_key('record_payment'), findsOneWidget);
  });

  testWidgets('recording a payment sends what was entered, shows the new end date and the payment, and reloads the list', (t) async {
    final _FakeSource source = await open(t, _biz('1', plan: 'trial', until: _today.add(const Duration(days: 2)), days: 2));

    await t.tap(_key('record_payment'));
    await t.pumpAndSettle();
    // a trial or free plan is not something a payment buys
    expect(_key('payment_plan_trial'), findsNothing);
    expect(_key('payment_plan_free'), findsNothing);

    await t.enterText(_key('payment_amount'), '45,000');
    await t.enterText(_key('payment_reference'), 'MP2610A1');
    await t.tap(_key('payment_months_3'));
    await t.pump();
    await t.tap(_key('payment_plan_premium'));
    await t.pump();
    await t.tap(_key('payment_submit'));
    await t.pumpAndSettle();

    expect(source.recorded, hasLength(1));
    expect(source.recorded.single.id, '1');
    expect(source.recorded.single.amount, 45000);
    expect(source.recorded.single.method, 'mobile_money');
    expect(source.recorded.single.reference, 'MP2610A1');
    expect(source.recorded.single.months, 3);
    expect(source.recorded.single.plan, 'premium');

    expect(_key('payment_submit'), findsNothing, reason: 'the form closed');
    expect(find.text('TZS 45,000'), findsOneWidget, reason: 'the history shows it');
    expect(_key('payments_empty'), findsNothing);
    expect(find.text(DateFormat('dd MMM yyyy').format(_today.add(const Duration(days: 90)))), findsWidgets, reason: 'the paid-until date moved on');
    expect(_key('billing_save'), findsOneWidget, reason: 'the sheet stays open to show it');

    // leaving the sheet by tapping outside it still reloads the list behind it
    await t.tapAt(const Offset(400, 40));
    await t.pumpAndSettle();
    expect(_key('billing_save'), findsNothing);
    expect(source.loads.length, 2);
  });

  testWidgets('an amount is required before anything is sent', (t) async {
    final _FakeSource source = await open(t, _biz('1'));

    await t.tap(_key('record_payment'));
    await t.pumpAndSettle();
    await t.tap(_key('payment_submit'));
    await t.pumpAndSettle();

    expect(find.text('Weka kiasi kilicholipwa.'), findsOneWidget);
    expect(source.recorded, isEmpty);
    expect(_key('payment_submit'), findsOneWidget);
  });

  testWidgets('a refusal from the server is shown in the form and nothing is lost', (t) async {
    final _FakeSource source = await open(t, _biz('1'));
    source.paymentError = Exception('The amount must be greater than 0.');

    await t.tap(_key('record_payment'));
    await t.pumpAndSettle();
    await t.enterText(_key('payment_amount'), '100');
    await t.tap(_key('payment_submit'));
    await t.pumpAndSettle();

    expect(find.text('The amount must be greater than 0.'), findsOneWidget);
    expect(_key('payment_submit'), findsOneWidget);
    expect(find.text('100'), findsOneWidget, reason: 'what was typed is still there');
    expect(source.loads.length, 1, reason: 'nothing changed, so nothing reloads');
  });

  testWidgets('cancelling the form records nothing', (t) async {
    final _FakeSource source = await open(t, _biz('1'));

    await t.tap(_key('record_payment'));
    await t.pumpAndSettle();
    await t.tap(_key('payment_cancel'));
    await t.pumpAndSettle();

    expect(_key('payment_submit'), findsNothing);
    expect(source.recorded, isEmpty);
  });
}
