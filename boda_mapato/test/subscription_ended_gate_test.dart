import 'package:boda_mapato/models/subscription.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:boda_mapato/widgets/subscription_ended_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A signed-in person whose business is (or is not) held back; the "server" is the test.
class _Auth extends AuthProvider {
  bool blocked = true;
  SubscriptionInfo? info = SubscriptionInfo(
    status: 'expired',
    plan: 'basic',
    businessName: 'Asha Rentals',
    isOwner: true,
    validUntil: DateTime(2026, 9, 1),
    daysLeft: -43,
    blocked: true,
    enforced: true,
    contactPhone: '0617919104',
  );
  int rechecks = 0;
  int logouts = 0;

  /// What the server will say the next time it is asked.
  bool paidByNextCheck = false;

  @override
  bool get subscriptionBlocked => blocked;

  @override
  SubscriptionInfo? get subscription => info;

  @override
  Future<void> recheckSubscription({Future<Map<String, dynamic>> Function()? fetch}) async {
    rechecks++;
    if (paidByNextCheck) {
      blocked = false;
      notifyListeners();
    }
  }

  @override
  Future<void> logout() async => logouts++;

  void paid() {
    blocked = false;
    notifyListeners();
  }
}

int _appTaps = 0;

Widget _host(_Auth auth, {Duration poll = const Duration(seconds: 30)}) => ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: ScreenUtilInit(
        designSize: const Size(800, 2400),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(
          home: Scaffold(body: Center(child: TextButton(onPressed: () => _appTaps++, child: const Text('THE APP')))),
          builder: (BuildContext context, Widget? navigator) => SubscriptionEndedGate(pollEvery: poll, child: navigator!),
        ),
      ),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

String _text(WidgetTester t, String key) => (t.widget(_key(key)) as Text).data!;

/// Every text on screen, so a word of the other language can be spotted.
List<String> _allTexts(WidgetTester t) => <String>[
      for (final Text w in t.widgetList<Text>(find.byType(Text)))
        if (w.data != null) w.data!,
      for (final SelectableText w in t.widgetList<SelectableText>(find.byType(SelectableText)))
        if (w.data != null) w.data!,
    ];

const Set<String> _swahiliWords = <String>{
  'siku', 'hadi', 'malipo', 'usajili', 'tafadhali', 'lipia', 'huduma', 'mpango', 'kipindi', 'unaisha', 'umeisha',
  'imesimamishwa', 'mmiliki', 'msimamizi', 'toka', 'nimelipa', 'angalia', 'tena', 'ulianza', 'zimebaki', 'taslimu',
  'historia', 'hakuna', 'unatumika', 'unakaribia', 'piga', 'ndugu', 'mteja', 'asante', 'nakili', 'namba', 'imenakiliwa',
  'mjulishe', 'kupitia', 'zimesimama', 'wasiliana', 'bado', 'hayajarekodiwa',
};

const Set<String> _englishWords = <String>{
  'please', 'pay', 'ends', 'started', 'plan', 'payment', 'payments', 'period', 'days', 'left', 'your', 'service',
  'services', 'hold', 'subscription', 'history', 'ended', 'active', 'check', 'again', 'paid', 'sign', 'cash', 'owner',
  'call', 'continue', 'recorded', 'ending', 'soon', 'dear', 'customer', 'thank', 'number', 'copy', 'copied', 'through',
  'contact', 'administrator',
};

Set<String> _wordsIn(Iterable<String> texts) =>
    <String>{for (final String s in texts) ...RegExp(r'[a-z]+').allMatches(s.toLowerCase()).map((RegExpMatch m) => m.group(0)!)};

void main() {
  late _Auth auth;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    auth = _Auth();
    _appTaps = 0;
  });
  tearDown(() => LocalizationService.instance.changeLanguage('sw'));

  testWidgets('an open business sees the app and no cover', (t) async {
    _tall(t);
    auth.blocked = false;
    await t.pumpWidget(_host(auth));

    expect(find.text('THE APP'), findsOneWidget);
    expect(_key('subscription_cover'), findsNothing);
    await t.tap(find.text('THE APP'));
    expect(_appTaps, 1);
  });

  testWidgets('a held-back business gets one polite full screen with the number to pay through', (t) async {
    _tall(t);
    await t.pumpWidget(_host(auth));
    await t.pump();

    expect(_key('subscription_cover'), findsOneWidget);
    expect(find.text('Lipia ili uendelee'), findsOneWidget);

    final String message = _text(t, 'subscription_cover_message');
    expect(message, startsWith('Ndugu mteja'));
    expect(message, contains('"Asha Rentals"'));
    expect(message, contains('lipia kupitia namba 0617919104'), reason: 'the number is part of the sentence');
    expect(message, endsWith('Asante kwa kuwa nasi.'));

    expect(find.descendant(of: _key('subscription_phone_card'), matching: find.text('0617919104')), findsOneWidget, reason: 'and large on its own');
    expect(_key('subscription_call'), findsOneWidget);
    expect(_key('subscription_copy'), findsOneWidget);
    expect(_text(t, 'subscription_cover_ended'), 'Usajili uliisha tarehe 01 Sep 2026.');
    expect(_key('subscription_check'), findsOneWidget);
    expect(find.text('Historia ya malipo'), findsNothing, reason: 'the cover is about paying, nothing else');

    await t.pumpWidget(const SizedBox());
  });

  testWidgets('nothing underneath can be reached while the cover is up', (t) async {
    _tall(t);
    await t.pumpWidget(_host(auth));
    await t.pump();

    // a tap where the app has a button lands on the cover
    await t.tapAt(t.getCenter(find.text('THE APP', skipOffstage: false)));
    await t.pump();
    expect(_appTaps, 0);

    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the cover goes away by itself when a payment is recorded', (t) async {
    _tall(t);
    await t.pumpWidget(_host(auth));
    await t.pump();
    expect(_key('subscription_cover'), findsOneWidget);

    auth.paid();
    await t.pump();

    expect(_key('subscription_cover'), findsNothing);
    await t.tap(find.text('THE APP'));
    expect(_appTaps, 1, reason: 'the app works again');
  });

  testWidgets('"I have paid" asks the server and says so when nothing was recorded yet', (t) async {
    _tall(t);
    await t.pumpWidget(_host(auth));
    await t.pump();

    await t.tap(_key('subscription_check'));
    await t.pump();
    await t.pump();

    expect(auth.rechecks, 1);
    expect(_key('subscription_still_unpaid'), findsOneWidget);
    expect(_key('subscription_cover'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
  });

  testWidgets('"I have paid" opens the app when the payment is there', (t) async {
    _tall(t);
    auth.paidByNextCheck = true;
    await t.pumpWidget(_host(auth));
    await t.pump();

    await t.tap(_key('subscription_check'));
    await t.pump();
    await t.pump();

    expect(_key('subscription_cover'), findsNothing);
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('while the cover is up the server is asked again and again, so a payment opens the app without a tap', (t) async {
    _tall(t);
    await t.pumpWidget(_host(auth, poll: const Duration(seconds: 5)));
    await t.pump();
    expect(auth.rechecks, 0);

    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 5));
    expect(auth.rechecks, 2);
    expect(_key('subscription_cover'), findsOneWidget);

    auth.paidByNextCheck = true;
    await t.pump(const Duration(seconds: 5));
    await t.pump();
    expect(_key('subscription_cover'), findsNothing);
  });

  testWidgets('the person can still sign out from the cover', (t) async {
    _tall(t);
    await t.pumpWidget(_host(auth));
    await t.pump();

    await t.tap(_key('subscription_sign_out'));
    await t.pump();

    expect(auth.logouts, 1);

    await t.pumpWidget(const SizedBox());
  });

  testWidgets('copy puts the number on the clipboard and says so for a moment', (t) async {
    _tall(t);
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await t.pumpWidget(_host(auth));
    await t.pump();
    expect(find.text('Nakili namba'), findsOneWidget);

    await t.tap(_key('subscription_copy'));
    await t.pump();

    expect(copied, '0617919104');
    expect(find.text('Imenakiliwa'), findsOneWidget);

    await t.pump(const Duration(seconds: 3));
    expect(find.text('Nakili namba'), findsOneWidget, reason: 'back to normal');

    await t.pumpWidget(const SizedBox());
  });

  testWidgets('staff are asked to tell the owner; the owner is not', (t) async {
    _tall(t);
    await t.pumpWidget(_host(auth));
    await t.pump();
    expect(_key('subscription_cover_staff'), findsNothing);

    await t.pumpWidget(const SizedBox());

    auth.info = const SubscriptionInfo(status: 'expired', plan: 'basic', businessName: 'Asha Rentals', blocked: true, enforced: true, contactPhone: '0617919104');
    await t.pumpWidget(_host(auth));
    await t.pump();

    expect(_key('subscription_cover_staff'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
  });

  testWidgets('when the server has no number yet the message says to contact the administrator and no number is invented', (t) async {
    _tall(t);
    auth.info = const SubscriptionInfo(status: 'expired', plan: 'basic', businessName: 'Asha Rentals', isOwner: true, blocked: true, enforced: true);
    await t.pumpWidget(_host(auth));
    await t.pump();

    expect(_text(t, 'subscription_cover_message'), contains('wasiliana na msimamizi wako'));
    expect(_key('subscription_phone_card'), findsNothing);
    expect(_key('subscription_call'), findsNothing);

    await t.pumpWidget(const SizedBox());
  });

  testWidgets('before the server has answered, the cover still appears with a plain, polite message', (t) async {
    _tall(t);
    auth.info = null;
    await t.pumpWidget(_host(auth));
    await t.pump();

    expect(_key('subscription_cover'), findsOneWidget);
    expect(find.text('Lipia ili uendelee'), findsOneWidget);
    expect(_text(t, 'subscription_cover_message'), startsWith('Ndugu mteja, huduma zako zimesimama'));
    expect(_key('subscription_cover_staff'), findsNothing, reason: 'nobody is told to fetch the owner before we know who they are');

    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the cover follows the app language', (t) async {
    _tall(t);
    await LocalizationService.instance.changeLanguage('en');
    await t.pumpWidget(_host(auth));
    await t.pump();

    expect(find.text('Pay to continue'), findsOneWidget);
    final String message = _text(t, 'subscription_cover_message');
    expect(message, startsWith('Dear customer'));
    expect(message, contains('please pay through 0617919104'));
    expect(message, endsWith('Thank you for being with us.'));
    expect(find.text('I have paid - check again'), findsOneWidget);
    expect(find.text('Call now'), findsOneWidget);
    expect(find.text('Copy number'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(_text(t, 'subscription_cover_ended'), 'The subscription ended on 01 Sep 2026.');
    expect(find.text('Lipia ili uendelee'), findsNothing);

    await t.pumpWidget(const SizedBox());
  });

  for (final String language in <String>['sw', 'en']) {
    testWidgets('no word of the other language on the cover ($language)', (t) async {
      _tall(t);
      await LocalizationService.instance.changeLanguage(language);
      final Set<String> foreign = language == 'en' ? _swahiliWords : _englishWords;

      // with and without a number, an owner and staff, and after "I have paid" found nothing
      final List<SubscriptionInfo?> states = <SubscriptionInfo?>[
        auth.info,
        const SubscriptionInfo(status: 'expired', plan: 'basic', businessName: 'Asha Rentals', isOwner: true, blocked: true),
        const SubscriptionInfo(status: 'expired', plan: 'basic', businessName: 'Asha Rentals', blocked: true, contactPhone: '0617919104'),
        null,
      ];
      for (final SubscriptionInfo? state in states) {
        auth.info = state;
        await t.pumpWidget(_host(auth));
        await t.pump();
        await t.tap(_key('subscription_check'));
        await t.pump();
        await t.pump();

        final Set<String> leaked = _wordsIn(_allTexts(t).where((String s) => s != 'THE APP')).intersection(foreign);
        expect(leaked, isEmpty, reason: '$language cover (${state?.contactPhone}/${state?.isOwner}) shows $leaked');

        await t.pumpWidget(const SizedBox());
      }
    });
  }

  for (final String language in <String>['sw', 'en']) {
    testWidgets('the cover fits a small phone with large text and scrolls instead of overflowing ($language)', (t) async {
      await LocalizationService.instance.changeLanguage(language);
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      auth.info = SubscriptionInfo(
        status: 'expired',
        plan: 'basic',
        businessName: 'Mama Asha Wholesale and Retail Stores Limited',
        isOwner: false,
        validUntil: DateTime(2026, 9, 1),
        blocked: true,
        contactPhone: '0617919104',
      );

      await t.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: ScreenUtilInit(
          designSize: const Size(360, 640),
          minTextAdapt: true,
          builder: (_, __) => MaterialApp(
            home: const Scaffold(body: Text('THE APP')),
            builder: (BuildContext context, Widget? navigator) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: SubscriptionEndedGate(child: navigator!),
            ),
          ),
        ),
      ));
      await t.pump();

      expect(t.takeException(), isNull, reason: 'no overflow');
      // everything is reachable by scrolling
      await t.scrollUntilVisible(_key('subscription_sign_out'), 200, scrollable: find.descendant(of: _key('subscription_cover'), matching: find.byType(Scrollable)).first);
      expect(_key('subscription_sign_out'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
    });
  }
}
