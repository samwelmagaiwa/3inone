import 'package:boda_mapato/models/subscription.dart';
import 'package:boda_mapato/screens/settings/subscription_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Source implements SubscriptionDataSource {
  _Source(this.answers);

  /// One answer per call: a [SubscriptionInfo] is returned, anything else is thrown.
  final List<Object> answers;
  int calls = 0;

  @override
  Future<SubscriptionInfo> load() async {
    final Object next = answers[calls < answers.length ? calls : answers.length - 1];
    calls++;
    if (next is SubscriptionInfo) return next;
    throw next;
  }
}

DateTime get _today => DateUtils.dateOnly(DateTime.now());

String _d(DateTime d) => DateFormat('dd MMM yyyy').format(d);

SubscriptionPayment _payment({double amount = 45000, int paidDaysAgo = 10, String method = 'mobile_money', String? reference = 'MP2610A1'}) {
  final DateTime paid = _today.subtract(Duration(days: paidDaysAgo));
  return SubscriptionPayment(
    amount: amount,
    currency: 'TZS',
    plan: 'basic',
    method: method,
    reference: reference,
    paidAt: paid,
    periodStart: paid.add(const Duration(days: 1)),
    periodEnd: paid.add(const Duration(days: 31)),
  );
}

SubscriptionInfo _info({
  String status = 'active',
  String plan = 'basic',
  bool owner = true,
  int? days = 20,
  bool blocked = false,
  bool enforced = true,
  List<SubscriptionPayment>? payments,
  String contact = '',
  bool noEnd = false,
}) {
  final SubscriptionPayment last = _payment();
  return SubscriptionInfo(
    status: noEnd ? 'never' : status,
    plan: plan,
    businessName: 'Asha Rentals',
    isOwner: owner,
    startedAt: _today.subtract(const Duration(days: 9)),
    validUntil: noEnd ? null : _today.add(Duration(days: days ?? 0)),
    daysLeft: noEnd ? null : days,
    graceEndsAt: noEnd ? null : _today.add(Duration(days: (days ?? 0) + 7)),
    enforced: enforced,
    blocked: blocked,
    contactPhone: contact,
    lastPayment: last,
    payments: owner ? (payments ?? <SubscriptionPayment>[last]) : const <SubscriptionPayment>[],
  );
}

Widget _host(SubscriptionDataSource source) => ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(800, 2400),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: SubscriptionScreen(dataSource: source)),
      ),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

Future<void> _open(WidgetTester t, SubscriptionInfo info) async {
  _tall(t);
  await t.pumpWidget(_host(_Source(<Object>[info])));
  await t.pumpAndSettle();
}

String _text(WidgetTester t, String key) => (t.widget(_key(key)) as Text).data!;

/// Every text on screen, so a word of the other language can be spotted.
List<String> _allTexts(WidgetTester t) => <String>[
      for (final Text w in t.widgetList<Text>(find.byType(Text)))
        if (w.data != null) w.data!,
    ];

const Set<String> _swahiliWords = <String>{
  'siku', 'hadi', 'malipo', 'usajili', 'tafadhali', 'lipia', 'huduma', 'mpango', 'kipindi', 'unaisha', 'umeisha',
  'imesimamishwa', 'mmiliki', 'msimamizi', 'toka', 'nimelipa', 'angalia', 'tena', 'ulianza', 'zimebaki', 'taslimu',
  'historia', 'hakuna', 'unatumika', 'unakaribia', 'piga',
};

const Set<String> _englishWords = <String>{
  'please', 'pay', 'ends', 'started', 'plan', 'payment', 'payments', 'period', 'days', 'left', 'your', 'service',
  'hold', 'subscription', 'history', 'ended', 'active', 'check', 'again', 'paid', 'sign', 'cash', 'owner', 'call',
  'continue', 'recorded', 'ending', 'soon',
};

Set<String> _wordsIn(Iterable<String> texts) =>
    <String>{for (final String s in texts) ...RegExp(r'[a-z]+').allMatches(s.toLowerCase()).map((RegExpMatch m) => m.group(0)!)};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(() => LocalizationService.instance.changeLanguage('sw'));

  testWidgets('the owner sees the plan, when it started, when it ends, the days left and every payment', (t) async {
    await _open(t, _info(days: 20, payments: <SubscriptionPayment>[_payment(), _payment(amount: 30000, paidDaysAgo: 40, method: 'cash', reference: null)]));

    expect(find.text('Asha Rentals'), findsOneWidget);
    expect(find.descendant(of: _key('subscription_plan'), matching: find.text('Msingi')), findsOneWidget);
    expect(find.descendant(of: _key('subscription_started'), matching: find.text(_d(_today.subtract(const Duration(days: 9))))), findsOneWidget);
    expect(find.descendant(of: _key('subscription_ends'), matching: find.text(_d(_today.add(const Duration(days: 20))))), findsOneWidget);
    expect(find.descendant(of: _key('subscription_days'), matching: find.text('20')), findsOneWidget);
    expect(_text(t, 'subscription_status_title'), 'Unatumika');
    expect(_text(t, 'subscription_status_message'), contains('siku 20 zimebaki'));

    expect(find.text('Historia ya malipo'), findsOneWidget);
    expect(find.text('TZS 45,000'), findsWidgets, reason: 'the payment, and the last payment line');
    expect(find.text('TZS 30,000'), findsOneWidget);
    final DateTime paid = _today.subtract(const Duration(days: 10));
    expect(find.text('Kipindi: ${_d(paid.add(const Duration(days: 1)))} - ${_d(paid.add(const Duration(days: 31)))}'), findsOneWidget);
    expect(find.text('Pesa za simu · MP2610A1'), findsOneWidget);
    expect(find.text('Taslimu'), findsOneWidget);
  });

  testWidgets('staff see the plan and the dates but not what was paid', (t) async {
    await _open(t, _info(owner: false));

    expect(_key('subscription_ends'), findsOneWidget);
    expect(find.text('Historia ya malipo'), findsNothing);
    expect(find.textContaining('Mwombe mmiliki'), findsOneWidget);
  });

  testWidgets('an owner with no payments yet is told so', (t) async {
    await _open(t, _info(payments: <SubscriptionPayment>[]));
    expect(_key('subscription_no_payments'), findsOneWidget);
  });

  testWidgets('a plan about to end says how many days are left and asks to pay', (t) async {
    await _open(t, _info(status: 'expiring', days: 3));
    expect(_text(t, 'subscription_status_title'), 'Unakaribia kuisha');
    expect(_text(t, 'subscription_status_message'), allOf(contains('siku 3'), contains('Lipia')));
  });

  testWidgets('the last day says "today"', (t) async {
    await _open(t, _info(status: 'expiring', days: 0));
    expect(_text(t, 'subscription_status_message'), contains('leo'));
  });

  testWidgets('in the grace days it says until when the service still works', (t) async {
    await _open(t, _info(status: 'grace', days: -2));
    expect(_text(t, 'subscription_status_title'), 'Umeisha - tafadhali lipia');
    expect(_text(t, 'subscription_status_message'), contains(_d(_today.add(const Duration(days: 5)))));
    expect(find.descendant(of: _key('subscription_days'), matching: find.textContaining('siku 2 zilizopita')), findsOneWidget);
  });

  testWidgets('a held-back business is told the service is on hold', (t) async {
    await _open(t, _info(status: 'expired', days: -12, blocked: true));
    expect(_text(t, 'subscription_status_title'), 'Huduma imesimamishwa');
    expect(_text(t, 'subscription_status_message'), contains('itafunguka mara moja'));
  });

  testWidgets('an ended plan that is not enforced only reminds', (t) async {
    await _open(t, _info(status: 'expired', days: -12, enforced: false));
    expect(_text(t, 'subscription_status_title'), 'Umeisha - tafadhali lipia');
    expect(find.textContaining('imesimamishwa'), findsNothing);
  });

  testWidgets('a plan with no end date says so and shows no days left', (t) async {
    await _open(t, _info(noEnd: true));
    expect(_text(t, 'subscription_status_title'), 'Hakuna tarehe ya kuisha');
    expect(_key('subscription_days'), findsNothing);
    expect(find.descendant(of: _key('subscription_ends'), matching: find.text('Hakuna')), findsOneWidget);
  });

  testWidgets('where to pay is shown when the server knows a number', (t) async {
    await _open(t, _info(contact: '0617919104'));
    expect(find.descendant(of: _key('subscription_contact'), matching: find.text('0617919104')), findsNothing);
    expect(find.text('0617919104'), findsOneWidget);
  });

  testWidgets('the whole screen follows the app language', (t) async {
    await LocalizationService.instance.changeLanguage('en');
    await _open(t, _info(days: 20));

    expect(find.text('My Subscription'), findsOneWidget);
    expect(_text(t, 'subscription_status_title'), 'Active');
    expect(_text(t, 'subscription_status_message'), contains('20 day(s) left'));
    expect(find.text('Payment history'), findsOneWidget);
    expect(find.text('Mobile money · MP2610A1'), findsOneWidget);
    expect(find.text('Unatumika'), findsNothing);
    expect(find.text('Historia ya malipo'), findsNothing);
  });

  testWidgets('a failed load shows the reason and a retry that works', (t) async {
    _tall(t);
    final _Source source = _Source(<Object>[Exception('Server error'), _info()]);
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();

    expect(find.text('Server error'), findsOneWidget);
    await t.tap(find.text('Jaribu tena'));
    await t.pumpAndSettle();

    expect(find.text('Server error'), findsNothing);
    expect(_key('subscription_status_card'), findsOneWidget);
    expect(source.calls, 2);
  });

  for (final String language in <String>['sw', 'en']) {
    testWidgets('no word of the other language on any state of the screen ($language)', (t) async {
      await LocalizationService.instance.changeLanguage(language);
      final Set<String> foreign = language == 'en' ? _swahiliWords : _englishWords;
      final List<SubscriptionInfo> states = <SubscriptionInfo>[
        _info(days: 20, contact: '0617919104'),
        _info(status: 'expiring', days: 3),
        _info(status: 'expiring', days: 0),
        _info(status: 'grace', days: -2),
        _info(status: 'expired', days: -12, blocked: true),
        _info(status: 'expired', days: -12, enforced: false),
        _info(noEnd: true),
        _info(owner: false),
        _info(payments: <SubscriptionPayment>[]),
      ];
      for (final SubscriptionInfo state in states) {
        await _open(t, state);
        final Set<String> leaked = _wordsIn(_allTexts(t)).intersection(foreign);
        expect(leaked, isEmpty, reason: '${state.status}/${state.daysLeft}/owner=${state.isOwner}: $language screen shows $leaked');
        await t.pumpWidget(const SizedBox());
      }
    });
  }
}
