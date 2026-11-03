import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/reminders/inventory_reminders_screen.dart';
import 'package:boda_mapato/modules/inventory/services/daily_voice.dart';
import 'package:boda_mapato/modules/inventory/services/reminder_voice.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The reminders are one card of rows divided by the glowing lines, with no gaps between them.
class _Api extends ApiService {
  final List<String> puts = <String>[];

  @override
  Future<Map<String, dynamic>> put(String endpoint, Map<String, dynamic> data, {bool requireAuth = true}) async {
    puts.add(endpoint);

    return <String, dynamic>{'message': 'ok'};
  }

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async => <String, dynamic>{
        'data': <Map<String, dynamic>>[
          for (int i = 1; i <= 3; i++)
            <String, dynamic>{'id': i, 'type': 'payment_due', 'title': 'Payment Due', 'description': 'Outstanding balance for sale S-$i', 'due_at': '2026-11-03 10:00:00', 'status': i == 1 ? 'snoozed' : 'open', if (i == 1) 'snooze_until': '2026-11-04 10:00:00', 'customer_name': 'Mteja $i', 'amount_left': 1000 * i, 'days': i},
        ],
      };
}

class _Speech implements SpeechPort {
  final List<String> said = <String>[];
  bool hasVoice = true;

  @override
  Future<bool> prepare({required bool swahili}) async => hasVoice;

  @override
  Future<void> speak(String text) async => said.add(text);

  @override
  Future<void> stop() async {}
}

void main() {
  testWidgets('three reminders have two glowing lines between them and each keeps its two buttons', (t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService.instance.changeLanguage('en');
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
          ChangeNotifierProvider<InventoryProvider>(create: (_) => InventoryProvider(api: _Api())),
        ],
        child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => const MaterialApp(home: Scaffold(body: InventoryRemindersScreen()))),
      ),
    );
    await t.pump();
    await t.pump();
    await t.pump();

    expect(find.byKey(const ValueKey<String>('reminder_1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reminder_3')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reminder_divider_1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reminder_divider_2')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reminder_divider_3')), findsNothing);
    expect(find.text('Mark Done'), findsNWidgets(3));
    expect(find.text('Snooze a day'), findsNWidgets(3));
  });

  testWidgets('a reminder put away says when it comes back, and sits below the ones that are still open', (t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService.instance.changeLanguage('en');
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
          ChangeNotifierProvider<InventoryProvider>(create: (_) => InventoryProvider(api: _Api())),
        ],
        child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => const MaterialApp(home: Scaffold(body: InventoryRemindersScreen()))),
      ),
    );
    await t.pump();
    await t.pump();
    await t.pump();

    expect(find.byKey(const ValueKey<String>('reminder_back_1')), findsOneWidget);
    expect(find.text('Comes back on 04/11 10:00'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reminder_back_2')), findsNothing, reason: 'an open one has nothing to come back to');
    expect(t.getTopLeft(find.byKey(const ValueKey<String>('reminder_2'))).dy, lessThan(t.getTopLeft(find.byKey(const ValueKey<String>('reminder_1'))).dy), reason: 'open first, snoozed after');
  });

  Future<_Api> open(WidgetTester t, {bool sw = false, SpeechPort? speech}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
    addTearDown(() => LocalizationService.instance.changeLanguage('en'));
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final _Api api = _Api();
    await t.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
          ChangeNotifierProvider<InventoryProvider>(create: (_) => InventoryProvider(api: api)),
        ],
        child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => MaterialApp(home: Scaffold(body: InventoryRemindersScreen(speech: speech)))),
      ),
    );
    await t.pump();
    await t.pump();
    await t.pump();

    return api;
  }

  testWidgets('Mark Done asks yes or no first; No closes the question and nothing is sent', (t) async {
    final _Api api = await open(t);

    await t.tap(find.text('Mark Done').first);
    await t.pumpAndSettle();
    expect(find.text('Mark this reminder as done?'), findsOneWidget);
    expect(find.text('It will be closed and will not come back.'), findsOneWidget);
    expect(api.puts, isEmpty, reason: 'nothing happens until the answer is Yes');

    await t.tap(find.byKey(const ValueKey<String>('mark_done_no')));
    await t.pumpAndSettle();

    expect(find.text('Mark this reminder as done?'), findsNothing);
    expect(api.puts, isEmpty);
  });

  testWidgets('Yes marks that reminder done', (t) async {
    final _Api api = await open(t);

    await t.tap(find.text('Mark Done').first);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('mark_done_yes')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    await t.pump(const Duration(seconds: 6));

    expect(api.puts.single, endsWith('/done'));
  });

  testWidgets('in Swahili the question and the answers are Swahili', (t) async {
    await open(t, sw: true);

    await t.tap(find.text('Weka Kamilika').first);
    await t.pumpAndSettle();

    expect(find.text('Kikumbusho hiki kimekamilika?'), findsOneWidget);
    expect(find.text('Ndio'), findsOneWidget);
    expect(find.text('Hapana'), findsOneWidget);
  });

  testWidgets('Snooze a day does not ask: it can be undone by the day passing', (t) async {
    final _Api api = await open(t);

    await t.tap(find.text('Snooze a day').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    await t.pump(const Duration(seconds: 6));

    expect(find.text('Mark this reminder as done?'), findsNothing);
    expect(api.puts.single, endsWith('/snooze'));
  });

  group('reading by itself when the app opens', () {
    testWidgets('the switch is on at first and switching it off is remembered', (t) async {
      await open(t, speech: _Speech());
      await t.pump();

      expect(t.widget<Switch>(find.byKey(const ValueKey<String>('voice_auto_switch'))).value, isTrue);

      await t.tap(find.byKey(const ValueKey<String>('voice_auto_switch')));
      await t.pump();

      expect(t.widget<Switch>(find.byKey(const ValueKey<String>('voice_auto_switch'))).value, isFalse);
      expect(await VoiceSettings.autoRead(), isFalse, reason: 'kept for the next time the app is opened');
    });

    testWidgets('a choice made before is shown when the page opens', (t) async {
      SharedPreferences.setMockInitialValues(<String, Object>{'voice_auto_read': false});
      await LocalizationService.instance.changeLanguage('en');
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
            ChangeNotifierProvider<InventoryProvider>(create: (_) => InventoryProvider(api: _Api())),
          ],
          child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => MaterialApp(home: Scaffold(body: InventoryRemindersScreen(speech: _Speech())))),
        ),
      );
      await t.pump();
      await t.pump();
      await t.pump();

      expect(t.widget<Switch>(find.byKey(const ValueKey<String>('voice_auto_switch'))).value, isFalse);
    });

    testWidgets('the sentence says what it does, in Kiswahili too', (t) async {
      await open(t, sw: true, speech: _Speech());

      expect(find.text('Soma madeni kwa sauti ninapofungua app (mara moja kwa siku)'), findsOneWidget);
    });
  });

  group('reading the debts aloud', () {
    testWidgets('"Read aloud" reads every debt reminder, named, in English', (t) async {
      final _Speech speech = _Speech();
      await open(t, speech: speech);

      await t.tap(find.byKey(const ValueKey<String>('read_all_aloud')));
      await t.pump();
      await t.pump();

      expect(speech.said, hasLength(2), reason: 'the snoozed one (#1) is put away for a day, so it is not read');
      expect(speech.said.first, 'Hello, customer Mteja 2 owes 2000 shillings, outstanding for 2 days. This is a reminder.', reason: 'no owner name in this test, so a plain greeting');
      expect(speech.said.last, contains('Mteja 3'));
    });

    testWidgets('in Swahili it speaks Swahili', (t) async {
      final _Speech speech = _Speech();
      await open(t, sw: true, speech: speech);

      await t.tap(find.byKey(const ValueKey<String>('read_all_aloud')));
      await t.pump();
      await t.pump();

      expect(speech.said.first, 'Habari, mteja Mteja 2 anadaiwa kiasi cha shilingi 2000 ndani ya siku 2. Huu ni ukumbusho.');
      expect(find.text('Soma kwa sauti'), findsOneWidget);
    });

    testWidgets('a reminder put away has no speaker', (t) async {
      await open(t, speech: _Speech());

      expect(find.byKey(const ValueKey<String>('voice_1')), findsNothing);
      expect(find.byKey(const ValueKey<String>('voice_2')), findsOneWidget);
    });

    testWidgets('the speaker on one reminder reads only that one', (t) async {
      final _Speech speech = _Speech();
      await open(t, speech: speech);

      await t.tap(find.byKey(const ValueKey<String>('voice_2')));
      await t.pump();
      await t.pump();

      expect(speech.said, hasLength(1));
      expect(speech.said.single, contains('Mteja 2'));
    });

    testWidgets('the name of the owner opens the greeting', (t) async {
      final _Speech speech = _Speech();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await LocalizationService.instance.changeLanguage('en');
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final AuthProvider auth = _Auth();
      await t.pumpWidget(
        MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<InventoryProvider>(create: (_) => InventoryProvider(api: _Api())),
          ],
          child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => MaterialApp(home: Scaffold(body: InventoryRemindersScreen(speech: speech)))),
        ),
      );
      await t.pump();
      await t.pump();
      await t.pump();

      await t.tap(find.byKey(const ValueKey<String>('voice_3')));
      await t.pump();
      await t.pump();

      expect(speech.said.single, startsWith('Hello Samwel, customer Mteja 3'));
    });

    testWidgets('a phone without the voice is told how to get it', (t) async {
      final _Speech speech = _Speech()..hasVoice = false;
      await open(t, speech: speech);

      await t.tap(find.byKey(const ValueKey<String>('read_all_aloud')));
      await t.pump();
      await t.pump();

      expect(find.text('This phone has no voice for this language. Install it in Settings > Text-to-speech.'), findsOneWidget);
      expect(speech.said, isEmpty);
      await t.pump(const Duration(seconds: 6));
    });
  });
}

class _Auth extends AuthProvider {
  @override
  String get userDisplayName => 'Samwel';
}
