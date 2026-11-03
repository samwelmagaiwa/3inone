import 'package:boda_mapato/modules/inventory/models/inv_reminder.dart';
import 'package:boda_mapato/modules/inventory/services/daily_voice.dart';
import 'package:boda_mapato/modules/inventory/services/reminder_voice.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The phone reads the debts aloud by itself when the app is opened: once a day, until the owner switches it off, and only when there is
/// something to read.
class _Speech implements SpeechPort {
  bool hasVoice = true;
  final List<String> said = <String>[];

  @override
  Future<bool> prepare({required bool swahili, String? voiceName, double rate = 0.42}) async => hasVoice;

  @override
  Future<List<VoiceOption>> voices({required bool swahili}) async => const <VoiceOption>[];

  @override
  Future<void> speak(String text) async => said.add(text);

  @override
  Future<void> stop() async {}
}

InvReminder _debt(int id, String name) => InvReminder(id: id, type: 'payment_due', title: 'Payment Due', description: '', dueAt: DateTime(2026, 11, 3), customerName: name, amountLeft: 1000.0 * id, days: id);

final DateTime _monday = DateTime(2026, 11, 2, 9);
final DateTime _tuesday = DateTime(2026, 11, 3, 9);

Future<void> _fresh({Map<String, Object> saved = const <String, Object>{}}) async {
  SharedPreferences.setMockInitialValues(saved);
  await LocalizationService.instance.changeLanguage('en');
}

void main() {
  group('the choice', () {
    test('reading by itself is on until it is switched off', () async {
      await _fresh();
      expect(await VoiceSettings.autoRead(), isTrue);

      await VoiceSettings.setAutoRead(false);
      expect(await VoiceSettings.autoRead(), isFalse);

      await VoiceSettings.setAutoRead(true);
      expect(await VoiceSettings.autoRead(), isTrue);
    });

    test('it is due until it has been read today, and due again tomorrow', () async {
      await _fresh();
      expect(await VoiceSettings.dueToday(_monday), isTrue);

      await VoiceSettings.markReadToday(_monday);
      expect(await VoiceSettings.dueToday(_monday.add(const Duration(hours: 5))), isFalse, reason: 'later the same day');
      expect(await VoiceSettings.dueToday(_tuesday), isTrue, reason: 'the next day');
    });
  });

  group('when the app is opened', () {
    test('reads the debts aloud and remembers that today is done', () async {
      await _fresh();
      final _Speech speech = _Speech();

      final VoiceResult? r = await DailyDebtVoice.maybeRead(load: () async => <InvReminder>[_debt(1, 'Asha'), _debt(2, 'Juma')], owner: 'Samwel', sw: false, voice: ReminderVoice(speech: speech), now: _monday);

      expect(r, VoiceResult.done);
      expect(speech.said, hasLength(2));
      expect(speech.said.first, startsWith('Hello Samwel, customer Asha'));
      expect(await VoiceSettings.dueToday(_monday), isFalse);
    });

    test('a second opening the same day says nothing and does not even ask the server', () async {
      await _fresh();
      final _Speech speech = _Speech();
      int loads = 0;
      Future<List<InvReminder>> load() async {
        loads++;

        return <InvReminder>[_debt(1, 'Asha')];
      }

      await DailyDebtVoice.maybeRead(load: load, owner: 'S', sw: false, voice: ReminderVoice(speech: speech), now: _monday);
      final VoiceResult? again = await DailyDebtVoice.maybeRead(load: load, owner: 'S', sw: false, voice: ReminderVoice(speech: speech), now: _monday.add(const Duration(hours: 3)));

      expect(again, isNull);
      expect(speech.said, hasLength(1));
      expect(loads, 1);
    });

    test('the next day it reads again', () async {
      await _fresh();
      final _Speech speech = _Speech();

      await DailyDebtVoice.maybeRead(load: () async => <InvReminder>[_debt(1, 'Asha')], owner: 'S', sw: false, voice: ReminderVoice(speech: speech), now: _monday);
      await DailyDebtVoice.maybeRead(load: () async => <InvReminder>[_debt(1, 'Asha')], owner: 'S', sw: false, voice: ReminderVoice(speech: speech), now: _tuesday);

      expect(speech.said, hasLength(2));
    });

    test('switched off, it never reads and never asks the server', () async {
      await _fresh(saved: <String, Object>{'voice_auto_read': false});
      final _Speech speech = _Speech();
      int loads = 0;

      final VoiceResult? r = await DailyDebtVoice.maybeRead(
        load: () async {
          loads++;

          return <InvReminder>[_debt(1, 'Asha')];
        },
        owner: 'S',
        sw: false,
        voice: ReminderVoice(speech: speech),
        now: _monday,
      );

      expect(r, isNull);
      expect(speech.said, isEmpty);
      expect(loads, 0);
    });

    test('a day with no debt reminder is not used up: it tries again at the next opening', () async {
      await _fresh();
      final _Speech speech = _Speech();

      final VoiceResult? none = await DailyDebtVoice.maybeRead(load: () async => <InvReminder>[], owner: 'S', sw: false, voice: ReminderVoice(speech: speech), now: _monday);
      expect(none, VoiceResult.nothingToRead);
      expect(await VoiceSettings.dueToday(_monday), isTrue);

      final VoiceResult? later = await DailyDebtVoice.maybeRead(load: () async => <InvReminder>[_debt(1, 'Asha')], owner: 'S', sw: false, voice: ReminderVoice(speech: speech), now: _monday.add(const Duration(hours: 4)));
      expect(later, VoiceResult.done);
    });

    test('a phone without the voice does not use the day up either', () async {
      await _fresh();
      final _Speech speech = _Speech()..hasVoice = false;

      final VoiceResult? r = await DailyDebtVoice.maybeRead(load: () async => <InvReminder>[_debt(1, 'Asha')], owner: 'S', sw: true, voice: ReminderVoice(speech: speech), now: _monday);

      expect(r, VoiceResult.noVoice);
      expect(await VoiceSettings.dueToday(_monday), isTrue);
    });

    test('in Kiswahili it speaks Kiswahili', () async {
      await _fresh();
      await LocalizationService.instance.changeLanguage('sw');
      addTearDown(() => LocalizationService.instance.changeLanguage('en'));
      final _Speech speech = _Speech();

      await DailyDebtVoice.maybeRead(load: () async => <InvReminder>[_debt(1, 'Asha')], owner: 'Samwel', sw: true, voice: ReminderVoice(speech: speech), now: _monday);

      expect(speech.said.single, startsWith('Habari Samwel, mteja Asha anadaiwa'));
    });
  });
}
