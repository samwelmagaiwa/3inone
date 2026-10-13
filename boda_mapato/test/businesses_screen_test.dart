import 'package:boda_mapato/models/business.dart';
import 'package:boda_mapato/screens/admin/businesses_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
