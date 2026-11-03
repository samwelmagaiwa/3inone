import 'package:boda_mapato/modules/inventory/screens/reminders/voice_picker_sheet.dart';
import 'package:boda_mapato/modules/inventory/services/reminder_voice.dart';
import 'package:boda_mapato/modules/inventory/services/voice_settings.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Choosing the voice that reads the debts, and how fast: every voice the phone has for the language is listed and can be heard first,
/// what is kept is used for every reading, and "automatic" goes back to the clearest one.
class _Speech implements SpeechPort {
  _Speech({this.options = const <VoiceOption>[]});

  final List<VoiceOption> options;
  final List<String> said = <String>[];
  final List<String?> usedVoices = <String?>[];
  final List<double> usedRates = <double>[];
  final List<bool> languages = <bool>[];

  @override
  Future<bool> prepare({required bool swahili, String? voiceName, double rate = 0.42}) async {
    languages.add(swahili);
    usedVoices.add(voiceName);
    usedRates.add(rate);

    return true;
  }

  @override
  Future<List<VoiceOption>> voices({required bool swahili}) async => options;

  @override
  Future<void> speak(String text) async => said.add(text);

  @override
  Future<void> stop() async {}
}

const List<VoiceOption> _swVoices = <VoiceOption>[
  VoiceOption(name: 'sw-tz-x-sfa-network', locale: 'sw-TZ', network: true),
  VoiceOption(name: 'sw-ke-x-sfa-local', locale: 'sw-KE'),
];

Future<_Speech> _open(WidgetTester t, {List<VoiceOption> options = _swVoices, bool sw = true, Map<String, Object> saved = const <String, Object>{}}) async {
  SharedPreferences.setMockInitialValues(saved);
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Speech speech = _Speech(options: options);
  await t.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(home: Scaffold(body: VoicePickerSheet(voice: ReminderVoice(speech: speech)))),
    ),
  );
  await t.pump();
  await t.pump();

  return speech;
}

Finder _k(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('lists the automatic choice and every voice the phone has, Tanzania first', (t) async {
    await _open(t);

    expect(_k('voice_auto'), findsOneWidget);
    expect(_k('voice_sw-tz-x-sfa-network'), findsOneWidget);
    expect(_k('voice_sw-ke-x-sfa-local'), findsOneWidget);
    expect(find.text('Kiswahili (Tanzania) 1'), findsOneWidget);
    expect(find.text('Kiswahili (Kenya) 2'), findsOneWidget);
    expect(find.textContaining('wazi · sw-tz-x-sfa-network'), findsOneWidget, reason: 'the clearer (network) voice is marked');
    expect(t.getTopLeft(_k('voice_auto')).dy, lessThan(t.getTopLeft(_k('voice_sw-tz-x-sfa-network')).dy));
  });

  testWidgets('automatic is chosen at first, and a voice chosen before is shown as chosen', (t) async {
    await _open(t);
    expect(find.descendant(of: _k('voice_auto'), matching: find.byIcon(Icons.radio_button_checked)), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    await _open(t, saved: <String, Object>{'voice_name_sw': 'sw-ke-x-sfa-local'});
    expect(find.descendant(of: _k('voice_sw-ke-x-sfa-local'), matching: find.byIcon(Icons.radio_button_checked)), findsOneWidget);
    expect(find.descendant(of: _k('voice_auto'), matching: find.byIcon(Icons.radio_button_checked)), findsNothing);
  });

  testWidgets('choosing a voice keeps it and plays the sample with it', (t) async {
    final _Speech speech = await _open(t);

    await t.tap(_k('voice_sw-tz-x-sfa-network'));
    await t.pump();
    await t.pump();

    expect(await VoiceSettings.voiceName(swahili: true), 'sw-tz-x-sfa-network');
    expect(speech.usedVoices.last, 'sw-tz-x-sfa-network');
    expect(speech.said.last, startsWith('Habari, huu ni mfano wa sauti'));
    expect(speech.languages.last, isTrue, reason: 'in Kiswahili');
  });

  testWidgets('the play button hears a voice without keeping it', (t) async {
    final _Speech speech = await _open(t);

    await t.tap(find.descendant(of: _k('voice_sw-ke-x-sfa-local'), matching: find.byIcon(Icons.play_circle_fill_rounded)));
    await t.pump();
    await t.pump();

    expect(speech.usedVoices.last, 'sw-ke-x-sfa-local');
    expect(await VoiceSettings.voiceName(swahili: true), isNull, reason: 'only listened to');
  });

  testWidgets('automatic goes back to the best voice and forgets the choice', (t) async {
    final _Speech speech = await _open(t, saved: <String, Object>{'voice_name_sw': 'sw-ke-x-sfa-local'});

    await t.tap(_k('voice_auto'));
    await t.pump();
    await t.pump();

    expect(await VoiceSettings.voiceName(swahili: true), isNull);
    expect(speech.usedVoices.last, isNull, reason: 'no name: the phone picks the clearest');
  });

  testWidgets('the speed is chosen, kept and heard', (t) async {
    final _Speech speech = await _open(t);

    expect(await VoiceSettings.speed(), 'normal');
    await t.tap(_k('voice_speed_slow'));
    await t.pump();
    await t.pump();

    expect(await VoiceSettings.speed(), 'slow');
    expect(speech.usedRates.last, VoiceSettings.speeds['slow']);
    expect(VoiceSettings.speeds['slow']!, lessThan(VoiceSettings.speeds['normal']!));
    expect(VoiceSettings.speeds['normal']!, lessThan(VoiceSettings.speeds['fast']!));
  });

  testWidgets('a phone with no voice for the language is told how to install one', (t) async {
    await _open(t, options: const <VoiceOption>[]);

    expect(_k('voice_none'), findsOneWidget);
    expect(find.textContaining('Kiswahili (Tanzania)'), findsOneWidget);
    expect(_k('voice_auto'), findsOneWidget, reason: 'automatic is still there');
  });

  testWidgets('in English it speaks about English voices', (t) async {
    await _open(t, sw: false, options: const <VoiceOption>[VoiceOption(name: 'en-us-x-tpf-network', locale: 'en-US', network: true)]);

    expect(find.text('Choose the reading voice'), findsOneWidget);
    expect(find.text('English (US) 1'), findsOneWidget);
    expect(find.text('Slow'), findsOneWidget);
  });

  testWidgets('a voice that is no longer on the phone is not shown as chosen', (t) async {
    await _open(t, saved: <String, Object>{'voice_name_sw': 'sw-gone'});

    expect(find.descendant(of: _k('voice_auto'), matching: find.byIcon(Icons.radio_button_checked)), findsOneWidget);
  });

  test('the speeds go from slow to fast and an unknown one is normal', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await VoiceSettings.setSpeed('turbo');

    expect(await VoiceSettings.speed(), 'normal');
    expect(await VoiceSettings.rate(), 0.42);
  });
}
