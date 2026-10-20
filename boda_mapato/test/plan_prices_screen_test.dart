import 'package:boda_mapato/models/plan_prices.dart';
import 'package:boda_mapato/screens/admin/plan_prices_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlanCatalog _catalog(Map<String, Map<int, double?>> prices, {bool configured = true}) => PlanCatalog(
      offers: <PlanOffer>[
        PlanOffer(plan: 'basic', servicesIncluded: 1, prices: prices['basic'] ?? const <int, double?>{}),
        PlanOffer(plan: 'standard', servicesIncluded: 2, prices: prices['standard'] ?? const <int, double?>{}),
        PlanOffer(plan: 'premium', servicesIncluded: 3, prices: prices['premium'] ?? const <int, double?>{}),
      ],
      configured: configured,
    );

final Map<String, Map<int, double?>> _all = <String, Map<int, double?>>{
  'basic': <int, double?>{1: 30000, 3: 85000, 6: 160000, 12: 300000},
  'standard': <int, double?>{1: 50000, 3: 140000, 6: 270000, 12: 520000},
  'premium': <int, double?>{1: 70000, 3: 200000, 6: 390000, 12: 750000},
};

class _FakeSource implements PlanPricesDataSource {
  _FakeSource(this.catalog);

  PlanCatalog catalog;
  Object? loadError;
  Object? saveError;
  final List<Map<String, Map<int, double?>>> saves = <Map<String, Map<int, double?>>>[];

  @override
  Future<PlanCatalog> load() async {
    if (loadError != null) throw loadError!;
    return catalog;
  }

  @override
  Future<PlanCatalog> save(Map<String, Map<int, double?>> changes) async {
    if (saveError != null) throw saveError!;
    saves.add(changes);
    final Map<String, Map<int, double?>> next = <String, Map<int, double?>>{
      for (final PlanOffer o in catalog.offers) o.plan: Map<int, double?>.of(o.prices),
    };
    changes.forEach((String plan, Map<int, double?> byMonths) => byMonths.forEach((int m, double? v) => next[plan]![m] = v));
    catalog = _catalog(next);
    return catalog;
  }
}

Widget _host(_FakeSource source) => ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(800, 2400),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: PlanPricesScreen(dataSource: source)),
      ),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

String _text(WidgetTester t, String key) => (t.widget(_key(key)) as Text).data!;

String _field(WidgetTester t, String plan, int months) => t.widget<TextField>(_key('price_${plan}_$months')).controller!.text;

Future<_FakeSource> _open(WidgetTester t, {Map<String, Map<int, double?>>? prices, bool configured = true}) async {
  _tall(t);
  final _FakeSource source = _FakeSource(_catalog(prices ?? _all, configured: configured));
  await t.pumpWidget(_host(source));
  await t.pumpAndSettle();
  return source;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(() => LocalizationService.instance.changeLanguage('sw'));

  testWidgets('shows the three plans with what each covers and every price filled in', (t) async {
    await _open(t);

    expect(_text(t, 'plan_covers_basic'), 'Huduma MOJA');
    expect(_text(t, 'plan_covers_standard'), 'Huduma 2');
    expect(_text(t, 'plan_covers_premium'), 'Hadi huduma 3');
    expect(_text(t, 'plans_intro'), allOf(contains('huduma MOJA'), contains('huduma 2'), contains('hadi huduma 3'), contains('mara moja')));

    expect(_field(t, 'basic', 1), '30000');
    expect(_field(t, 'basic', 12), '300000');
    expect(_field(t, 'standard', 3), '140000');
    expect(_field(t, 'premium', 6), '390000');
    expect(find.text('Mwezi 1'), findsNWidgets(3));
    expect(find.text('Mwaka 1'), findsNWidgets(3));
  });

  testWidgets('with no price set yet the fields are empty and say so', (t) async {
    await _open(t, prices: <String, Map<int, double?>>{}, configured: false);

    expect(_field(t, 'basic', 1), '');
    expect(_text(t, 'hint_basic_1'), 'Bado haijawekwa');
    expect(_text(t, 'preview_basic'), 'Msingi · Huduma MOJA · bei haijawekwa');
    expect(t.widget<FilledButton>(_key('save_prices')).onPressed, isNull, reason: 'nothing to save');
    expect(find.text('Hakuna mabadiliko'), findsOneWidget);
  });

  testWidgets('changing prices enables Save, which sends only what changed', (t) async {
    final _FakeSource source = await _open(t);
    expect(t.widget<FilledButton>(_key('save_prices')).onPressed, isNull);

    await t.enterText(_key('price_basic_1'), '35000');
    await t.enterText(_key('price_premium_12'), '799,999');
    await t.pump();
    expect(find.text('Hifadhi bei'), findsOneWidget);

    await t.ensureVisible(_key('save_prices'));
    await t.tap(_key('save_prices'));
    await t.pumpAndSettle();

    expect(source.saves, hasLength(1));
    expect(source.saves.single, <String, Map<int, double?>>{
      'basic': <int, double?>{1: 35000},
      'premium': <int, double?>{12: 799999},
    }, reason: 'the other ten prices are not sent');
    expect(_field(t, 'basic', 1), '35000');
    expect(_field(t, 'premium', 12), '799999', reason: 'the server answer is what is shown');
    expect(find.text('Hakuna mabadiliko'), findsOneWidget, reason: 'saved: nothing left to save');
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('emptying a field clears that price', (t) async {
    final _FakeSource source = await _open(t);

    await t.enterText(_key('price_standard_6'), '');
    await t.pump();
    await t.ensureVisible(_key('save_prices'));
    await t.tap(_key('save_prices'));
    await t.pumpAndSettle();

    expect(source.saves.single, <String, Map<int, double?>>{
      'standard': <int, double?>{6: null},
    });
    expect(_text(t, 'hint_standard_6'), 'Bado haijawekwa');
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('a price that is not a number above zero is refused before anything is sent', (t) async {
    final _FakeSource source = await _open(t);

    await t.enterText(_key('price_basic_1'), '0');
    await t.pump();
    expect(find.text('Si sahihi'), findsOneWidget);
    expect(t.widget<FilledButton>(_key('save_prices')).onPressed, isNull, reason: 'the only change is not a price');

    // with a real change beside it, Save can be pressed and says what is wrong
    await t.enterText(_key('price_premium_12'), '799999');
    await t.pump();
    await t.ensureVisible(_key('save_prices'));
    await t.tap(_key('save_prices'));
    await t.pump();
    expect(_text(t, 'prices_error'), contains('bei isiyo sahihi'));
    expect(source.saves, isEmpty, reason: 'not even the good price is sent');

    // letters cannot even be typed
    await t.enterText(_key('price_basic_3'), 'abc');
    expect(_field(t, 'basic', 3), '', reason: 'only digits, commas and a dot are taken');
  });

  testWidgets('says what each longer period comes to a month and what it saves', (t) async {
    await _open(t);

    // 85,000 / 3 = 28,333 a month against 30,000: saves about 6%
    expect(_text(t, 'hint_basic_3'), allOf(contains('TZS 28,333'), contains('unaokoa 6%')));
    expect(_text(t, 'hint_basic_12'), allOf(contains('TZS 25,000'), contains('unaokoa 17%')));

    await t.enterText(_key('price_basic_6'), '200000');
    await t.pump();
    expect(_text(t, 'hint_basic_6'), contains('ghali kuliko kulipa kila mwezi'), reason: '200,000 for 6 months is more than 6 x 30,000');
  });

  testWidgets('warns when a bigger plan costs less than a smaller one, but still lets it be saved', (t) async {
    final _FakeSource source = await _open(t);
    expect(_key('price_warnings'), findsNothing);

    await t.enterText(_key('price_premium_1'), '40000');
    await t.pump();
    expect(_key('price_warnings'), findsOneWidget);
    expect(find.textContaining('Premium (Mwezi 1) ni rahisi kuliko Kawaida'), findsOneWidget);

    await t.ensureVisible(_key('save_prices'));
    await t.tap(_key('save_prices'));
    await t.pumpAndSettle();
    expect(source.saves, hasLength(1), reason: 'a warning is not a refusal');
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('the preview shows what a client will read for one month, as typed', (t) async {
    await _open(t);

    expect(_text(t, 'preview_basic'), 'Msingi · Huduma MOJA · TZS 30,000');
    expect(_text(t, 'preview_standard'), 'Kawaida · Huduma 2 · TZS 50,000');
    expect(_text(t, 'preview_premium'), 'Premium · Hadi huduma 3 · TZS 70,000');

    await t.enterText(_key('price_standard_1'), '55000');
    await t.pump();
    expect(_text(t, 'preview_standard'), 'Kawaida · Huduma 2 · TZS 55,000');
  });

  testWidgets('a refusal from the server is shown and what was typed stays', (t) async {
    final _FakeSource source = await _open(t);
    source.saveError = Exception('Bei lazima iwe namba kubwa kuliko sifuri. / A price must be a number above zero.');

    await t.enterText(_key('price_basic_1'), '1000');
    await t.pump();
    await t.ensureVisible(_key('save_prices'));
    await t.tap(_key('save_prices'));
    await t.pumpAndSettle();

    expect(_text(t, 'prices_error'), 'Bei lazima iwe namba kubwa kuliko sifuri.', reason: 'one language');
    expect(_field(t, 'basic', 1), '1000');
    expect(t.widget<FilledButton>(_key('save_prices')).onPressed, isNotNull, reason: 'it can be tried again');
  });

  testWidgets('a failed load shows the reason and a retry', (t) async {
    _tall(t);
    final _FakeSource source = _FakeSource(_catalog(_all))..loadError = Exception('Server error');
    await t.pumpWidget(_host(source));
    await t.pumpAndSettle();

    expect(find.text('Server error'), findsOneWidget);
    source.loadError = null;
    await t.tap(find.text('Jaribu tena'));
    await t.pumpAndSettle();
    expect(_field(t, 'basic', 1), '30000');
  });

  testWidgets('reads in English when the app does, with no Swahili left', (t) async {
    await LocalizationService.instance.changeLanguage('en');
    await _open(t);
    await t.enterText(_key('price_premium_1'), '40000');
    await t.pump();

    expect(find.text('Plans & Prices'), findsOneWidget);
    expect(_text(t, 'plan_covers_basic'), 'ONE service');
    expect(_text(t, 'plan_covers_standard'), 'TWO services');
    expect(_text(t, 'plan_covers_premium'), 'UP TO 3 services');
    expect(_text(t, 'preview_basic'), 'Basic · ONE service · TZS 30,000');
    expect(_text(t, 'hint_basic_3'), contains('a month'));
    expect(find.textContaining('costs less than Standard'), findsOneWidget);
    expect(find.text('Save prices'), findsOneWidget);

    final Set<String> words = <String>{
      for (final Text w in t.widgetList<Text>(find.byType(Text))) ...RegExp(r'[a-z]+').allMatches((w.data ?? '').toLowerCase()).map((RegExpMatch m) => m.group(0)!),
    };
    const Set<String> swahili = <String>{'huduma', 'bei', 'mwezi', 'miezi', 'mwaka', 'hifadhi', 'mpango', 'unaokoa', 'kawaida', 'msingi', 'moja', 'zote', 'bado', 'haijawekwa', 'mteja', 'ataona'};
    expect(words.intersection(swahili), isEmpty, reason: 'English screen shows ${words.intersection(swahili)}');
  });

  testWidgets('reads in Swahili with no English left', (t) async {
    await _open(t);
    await t.enterText(_key('price_premium_1'), '40000');
    await t.pump();

    final Set<String> words = <String>{
      for (final Text w in t.widgetList<Text>(find.byType(Text))) ...RegExp(r'[a-z]+').allMatches((w.data ?? '').toLowerCase()).map((RegExpMatch m) => m.group(0)!),
    };
    const Set<String> english = <String>{'service', 'services', 'month', 'months', 'year', 'save', 'saves', 'price', 'prices', 'costs', 'less', 'client', 'sees', 'plan', 'plans', 'one', 'two', 'all', 'dearer', 'paying', 'monthly'};
    expect(words.intersection(english), isEmpty, reason: 'Swahili screen shows ${words.intersection(english)}');
  });
}
