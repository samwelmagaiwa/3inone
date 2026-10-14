import 'dart:async';

import 'package:boda_mapato/models/business_registration.dart';
import 'package:boda_mapato/models/plan_prices.dart';
import 'package:boda_mapato/screens/auth/register_business_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlanCatalog _priced() => const PlanCatalog(
      configured: true,
      offers: <PlanOffer>[
        PlanOffer(plan: 'basic', servicesIncluded: 1, prices: <int, double?>{1: 30000, 3: 85000, 6: 160000, 12: 300000}),
        PlanOffer(plan: 'standard', servicesIncluded: 2, prices: <int, double?>{1: 50000, 3: 140000, 6: 270000, 12: 520000}),
        PlanOffer(plan: 'premium', servicesIncluded: 3, prices: <int, double?>{1: 70000, 3: 200000, 6: 390000, 12: 750000}),
      ],
    );

Widget _host(RegisterBusinessScreen screen) => ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(800, 3200),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: screen),
      ),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 4200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

String _text(WidgetTester t, String key) => (t.widget(_key(key)) as Text).data!;

/// The starfield animates forever, so only pump a little.
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

Future<BusinessRegistrationRequest?> _capture(
  WidgetTester t, {
  PlanCatalog? catalog,
  LoadPlans? load,
  List<String> services = const <String>[],
  String? choosePlan,
  int? months,
  bool submit = false,
}) async {
  _tall(t);
  BusinessRegistrationRequest? sent;
  await t.pumpWidget(_host(RegisterBusinessScreen(
    onLoadPlans: load ?? (() async => catalog ?? _priced()),
    onSubmit: (BusinessRegistrationRequest r) async {
      sent = r;
      return <String, dynamic>{'data': <String, dynamic>{'phone_verification_required': false, 'phone_verified': true}};
    },
  )));
  await _settle(t);

  final Finder f = find.byType(TextFormField);
  await t.enterText(f.at(0), 'Asha Owner');
  await t.enterText(f.at(1), 'asha@example.test');
  await t.enterText(f.at(2), '0743519100');
  await t.enterText(f.at(3), 'secret-pass-1');
  await t.enterText(f.at(4), 'secret-pass-1');
  await t.enterText(f.at(5), 'Asha Rentals');
  for (final String s in services) {
    await t.tap(_key('service_$s'));
    await t.pump();
  }
  if (choosePlan != null) {
    await t.ensureVisible(_key('plan_$choosePlan'));
    await t.tap(_key('plan_$choosePlan'));
    await t.pump();
  }
  if (months != null) {
    await t.ensureVisible(_key('period_$months'));
    await t.tap(_key('period_$months'));
    await t.pump();
  }
  if (submit) {
    await t.ensureVisible(_key('registration_submit'));
    await t.tap(_key('registration_submit'));
    await _settle(t);
  }
  return sent;
}

Future<void> _pick(WidgetTester t, List<String> services) async {
  for (final String s in services) {
    await t.ensureVisible(_key('service_$s'));
    await t.tap(_key('service_$s'));
    await t.pump();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(() => LocalizationService.instance.changeLanguage('sw'));

  group('the package follows the services chosen', () {
    testWidgets('one service: Basic fits, with its price, and the client is told it is ONE service', (t) async {
      await _capture(t, services: <String>['rental']);

      expect(_key('recommended_basic'), findsOneWidget);
      expect(_key('recommended_standard'), findsNothing);
      expect(_key('recommended_premium'), findsNothing);
      expect(_text(t, 'covers_basic'), 'Huduma MOJA');
      expect(_text(t, 'covers_standard'), 'Huduma 2');
      expect(_text(t, 'covers_premium'), 'Huduma ZOTE 3');
      expect(_text(t, 'price_basic'), 'TZS 30,000 · Mwezi 1');
      expect(_text(t, 'price_standard'), 'TZS 50,000 · Mwezi 1');
      expect(_text(t, 'price_premium'), 'TZS 70,000 · Mwezi 1');

      expect(_text(t, 'package_rule'), contains('huduma MOJA'));
      final String notice = ((t.widget(_key('basic_notice')) as Container).child! as Row).children.whereType<Expanded>().single.child.toString();
      expect(notice, contains('MOJA'));
      expect(find.textContaining('mpango wa Msingi (Basic) ni huduma MOJA tu'), findsOneWidget);

      expect(_text(t, 'package_summary'), 'Utalipa TZS 30,000 kwa mwezi 1: Msingi (huduma moja).');
      expect(_text(t, 'trial_note'), contains('siku 30 za majaribio'));
    });

    testWidgets('two services: Standard fits, three: Premium, and taking one away goes back down', (t) async {
      await _capture(t, services: <String>['rental', 'transport']);
      expect(_key('recommended_standard'), findsOneWidget);
      expect(_key('basic_notice'), findsNothing, reason: 'Basic is not the plan chosen');
      expect(_text(t, 'package_summary'), 'Utalipa TZS 50,000 kwa mwezi 1: Kawaida (huduma 2).');

      await _pick(t, <String>['inventory']);
      // inventory asks what kind of stock business: the package section stays
      expect(_key('recommended_premium'), findsOneWidget);
      expect(_text(t, 'package_summary'), 'Utalipa TZS 70,000 kwa mwezi 1: Premium (huduma zote 3).');

      await _pick(t, <String>['inventory', 'transport']);
      expect(_key('recommended_basic'), findsOneWidget, reason: 'one service again');
      expect(_key('basic_notice'), findsOneWidget);
    });

    testWidgets('a longer period shows its own price on every plan and in the summary', (t) async {
      await _capture(t, services: <String>['rental', 'transport']);

      await t.ensureVisible(_key('period_3'));
      await t.tap(_key('period_3'));
      await t.pump();
      expect(_text(t, 'price_basic'), 'TZS 85,000 · Miezi 3');
      expect(_text(t, 'price_standard'), 'TZS 140,000 · Miezi 3');
      expect(_text(t, 'package_summary'), 'Utalipa TZS 140,000 kwa miezi 3: Kawaida (huduma 2).');

      await t.tap(_key('period_12'));
      await t.pump();
      expect(_text(t, 'price_premium'), 'TZS 750,000 · Mwaka 1');
      expect(_text(t, 'package_summary'), contains('kwa mwaka 1'));
    });

    testWidgets('with nothing chosen yet it says to choose services first', (t) async {
      await _capture(t);

      expect(_key('package_choose_services'), findsOneWidget);
      expect(_key('package_summary'), findsNothing);
      expect(_key('recommended_basic'), findsNothing);
    });
  });

  group('a plan too small for the services', () {
    testWidgets('Basic with two services says so plainly and offers the plan that fits', (t) async {
      await _capture(t, services: <String>['rental', 'transport'], choosePlan: 'basic');

      expect(_key('plan_warning'), findsOneWidget);
      expect(find.textContaining('Mpango wa Msingi ni huduma MOJA tu, na umechagua 2'), findsOneWidget);
      expect(find.textContaining('Kawaida'), findsWidgets);
      expect(_key('package_summary'), findsNothing, reason: 'no price is promised for something that does not fit');

      await t.tap(_key('use_recommended_plan'));
      await t.pump();
      expect(_key('plan_warning'), findsNothing);
      expect(_text(t, 'package_summary'), contains('Kawaida'));
    });

    testWidgets('it cannot be sent, and nothing is lost', (t) async {
      final BusinessRegistrationRequest? sent = await _capture(t, services: <String>['rental', 'transport'], choosePlan: 'basic', submit: true);

      expect(sent, isNull);
      expect(_key('registration_error'), findsOneWidget);
      expect(find.descendant(of: _key('registration_error'), matching: find.textContaining('huduma MOJA tu')), findsOneWidget);
      expect(_key('plan_warning'), findsOneWidget);
      expect(find.byType(TextFormField).evaluate().length, greaterThan(5));
    });

    testWidgets('three services on Standard is refused too, and Premium is the one offered', (t) async {
      await _capture(t, services: <String>['rental', 'transport', 'inventory'], choosePlan: 'standard');

      expect(_key('plan_warning'), findsOneWidget);
      expect(find.textContaining('unahusu huduma 2 tu, na umechagua 3'), findsOneWidget);
      expect(find.text('Tumia Premium'), findsOneWidget);
    });

    testWidgets('choosing services again after a bigger plan was picked keeps the pick', (t) async {
      await _capture(t, services: <String>['rental'], choosePlan: 'premium');
      expect(_key('plan_note'), findsOneWidget, reason: 'Premium for one service is allowed but the client is told');
      expect(find.textContaining('Msingi inatosha kwa huduma ulizochagua'), findsOneWidget);

      await _pick(t, <String>['transport']);
      expect(_key('plan_warning'), findsNothing);
      expect(find.textContaining('Kawaida inatosha kwa huduma ulizochagua'), findsOneWidget, reason: 'two services now: Standard is what would do');
      expect(_text(t, 'package_summary'), contains('Premium'), reason: 'but the choice stays');

      await _pick(t, <String>['inventory']);
      expect(_key('plan_note'), findsNothing, reason: 'three services: Premium is exactly what is needed');
    });
  });

  group('what is sent', () {
    testWidgets('the package and the months go with the registration', (t) async {
      final BusinessRegistrationRequest? sent = await _capture(t, services: <String>['rental', 'transport'], months: 6, submit: true);

      expect(sent, isNotNull);
      expect(sent!.requestedPlan, 'standard');
      expect(sent.requestedMonths, 6);
      expect(sent.toJson()['requested_plan'], 'standard');
      expect(sent.toJson()['requested_months'], 6);
      expect(sent.requestedServices, <String>['rental', 'transport']);
    });

    testWidgets('a bigger plan than needed is the client\'s choice and is sent', (t) async {
      final BusinessRegistrationRequest? sent = await _capture(t, services: <String>['rental'], choosePlan: 'premium', submit: true);

      expect(sent!.requestedPlan, 'premium');
      expect(sent.requestedMonths, 1);
    });

    testWidgets('the confirmation page repeats what was chosen and what it costs', (t) async {
      await _capture(t, services: <String>['rental', 'transport'], months: 3, submit: true);

      expect(_key('registration_done_title'), findsOneWidget);
      expect(_text(t, 'registration_done_package'), 'Kifurushi ulichochagua: Kawaida (huduma 2) · miezi 3 · TZS 140,000');
    });
  });

  group('when there are no prices', () {
    testWidgets('the form still works: plans and what they cover show, the price is to be announced', (t) async {
      final BusinessRegistrationRequest? sent =
          await _capture(t, catalog: PlanCatalog.fallback, services: <String>['rental'], submit: true);

      expect(sent!.requestedPlan, 'basic');
    });

    testWidgets('unpriced plans say the price will be announced', (t) async {
      await _capture(t, catalog: PlanCatalog.fallback, services: <String>['rental']);

      expect(_text(t, 'price_basic'), 'Bei itatangazwa');
      expect(_text(t, 'covers_basic'), 'Huduma MOJA');
      expect(_text(t, 'package_summary'), contains('itatangazwa na msimamizi'));
    });

    testWidgets('a server that cannot be reached changes nothing but the prices', (t) async {
      final BusinessRegistrationRequest? sent = await _capture(
        t,
        load: () async => throw Exception('offline'),
        services: <String>['rental', 'transport'],
        submit: true,
      );

      expect(sent!.requestedPlan, 'standard', reason: 'what each plan covers is known without the server');
    });

    testWidgets('prices that arrive a moment later appear on their own', (t) async {
      _tall(t);
      final Completer<PlanCatalog> later = Completer<PlanCatalog>();
      await t.pumpWidget(_host(RegisterBusinessScreen(onLoadPlans: () => later.future, onSubmit: (_) async => <String, dynamic>{})));
      await _settle(t);
      await _pick(t, <String>['rental']);
      expect(_text(t, 'price_basic'), 'Bei itatangazwa');

      later.complete(_priced());
      await _settle(t);

      expect(_text(t, 'price_basic'), 'TZS 30,000 · Mwezi 1');
      expect(_text(t, 'package_summary'), contains('TZS 30,000'));
    });

    testWidgets('no free-trial line when the server says there are no trial days', (t) async {
      await _capture(t, catalog: const PlanCatalog(offers: <PlanOffer>[PlanOffer(plan: 'basic', servicesIncluded: 1), PlanOffer(plan: 'standard', servicesIncluded: 2), PlanOffer(plan: 'premium', servicesIncluded: 3)], trialDays: 0), services: <String>['rental']);

      expect(_key('trial_note'), findsNothing);
    });
  });

  group('one language at a time', () {
    const Set<String> swahili = <String>{
      'huduma', 'moja', 'zote', 'bei', 'itatangazwa', 'utalipa', 'kwa', 'mwezi', 'miezi', 'mwaka', 'inakufaa', 'kumbuka', 'chagua',
      'tumia', 'mpango', 'kifurushi', 'majaribio', 'malipo', 'ukikubaliwa', 'msimamizi', 'wa', 'ni', 'tu', 'umechagua', 'punguza',
    };
    const Set<String> english = <String>{
      'service', 'services', 'price', 'announced', 'will', 'pay', 'month', 'months', 'year', 'fits', 'please', 'note', 'choose',
      'use', 'plan', 'package', 'trial', 'payment', 'approved', 'covers', 'only', 'you', 'chose', 'fewer', 'one', 'two', 'all',
    };

    Set<String> wordsInPackage(WidgetTester t) {
      final Iterable<Text> texts = t.widgetList<Text>(find.descendant(of: _key('package_section'), matching: find.byType(Text)));
      return <String>{
        for (final Text w in texts) ...RegExp(r'[a-z]+').allMatches((w.data ?? '').toLowerCase()).map((RegExpMatch m) => m.group(0)!),
      };
    }

    for (final String language in <String>['sw', 'en']) {
      testWidgets('the package section uses $language only, for every plan and every situation', (t) async {
        await LocalizationService.instance.changeLanguage(language);
        final Set<String> foreign = language == 'en' ? swahili : english;

        await _capture(t, services: <String>['rental']);
        for (final String plan in <String>['basic', 'standard', 'premium']) {
          await t.ensureVisible(_key('plan_$plan'));
          await t.tap(_key('plan_$plan'));
          await t.pump();
          expect(wordsInPackage(t).intersection(foreign), isEmpty, reason: '$language, one service, $plan: ${wordsInPackage(t).intersection(foreign)}');
        }

        await _pick(t, <String>['transport']);
        for (final String plan in <String>['basic', 'standard', 'premium']) {
          await t.ensureVisible(_key('plan_$plan'));
          await t.tap(_key('plan_$plan'));
          await t.pump();
          expect(wordsInPackage(t).intersection(foreign), isEmpty, reason: '$language, two services, $plan: ${wordsInPackage(t).intersection(foreign)}');
        }

        await t.ensureVisible(_key('period_12'));
        await t.tap(_key('period_12'));
        await t.pump();
        expect(wordsInPackage(t).intersection(foreign), isEmpty, reason: '$language, a year');
      });
    }

    testWidgets('in English the Basic notice says it plainly', (t) async {
      await LocalizationService.instance.changeLanguage('en');
      await _capture(t, services: <String>['rental']);

      expect(find.text('Please note: the Basic plan is ONE service only. For two services choose Standard, or Premium for all three.'), findsOneWidget);
      expect(_text(t, 'package_rule'), 'Basic is ONE service, Standard is TWO, Premium is ALL THREE.');
      expect(_text(t, 'package_summary'), 'You will pay TZS 30,000 for 1 month: Basic (one service).');
      expect(_text(t, 'trial_note'), 'Once you are approved you get 30 days of free trial; payment starts after that.');
    });
  });
}
