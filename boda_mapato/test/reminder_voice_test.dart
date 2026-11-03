import 'package:boda_mapato/modules/inventory/models/inv_reminder.dart';
import 'package:boda_mapato/modules/inventory/services/reminder_voice.dart';
import 'package:flutter_test/flutter_test.dart';

/// The spoken reminder: "Hello <owner>, customer <name> owes <amount> shillings ... for <days> days", in Kiswahili or English, read one
/// after the other and stoppable. The phone's voice is stood in for by a fake.
class _Speech implements SpeechPort {
  _Speech({this.hasVoice = true});

  final bool hasVoice;
  final List<String> said = <String>[];
  final List<bool> languages = <bool>[];
  bool stopped = false;
  void Function()? onSay;

  @override
  Future<bool> prepare({required bool swahili}) async {
    languages.add(swahili);

    return hasVoice;
  }

  @override
  Future<void> speak(String text) async {
    said.add(text);
    onSay?.call();
  }

  @override
  Future<void> stop() async => stopped = true;
}

InvReminder _r(int id, {String type = 'payment_due', String? name = 'Mama Chale', double? left = 430000, int? days = 3, InvReminderStatus status = InvReminderStatus.open}) => InvReminder(
      id: id, type: type, title: 'Payment Due', description: '', dueAt: DateTime(2026, 11, 3), status: status, customerName: name, amountLeft: left, days: days,
    );

void main() {
  group('the sentence', () {
    test('in Kiswahili', () {
      expect(reminderSentence(owner: 'Samwel', customer: 'Mama Chale', amount: 430000, days: 3, sw: true), 'Habari Samwel, mteja Mama Chale anadaiwa kiasi cha shilingi 430000 ndani ya siku 3. Huu ni ukumbusho.');
    });

    test('in English', () {
      expect(reminderSentence(owner: 'Samwel', customer: 'Mama Chale', amount: 430000, days: 3, sw: false), 'Hello Samwel, customer Mama Chale owes 430000 shillings, outstanding for 3 days. This is a reminder.');
    });

    test('a debt from today says today, and one day is "1 day"', () {
      expect(reminderSentence(owner: 'S', customer: 'A', amount: 1000, days: 0, sw: true), contains('ndani ya siku ya leo'));
      expect(reminderSentence(owner: 'S', customer: 'A', amount: 1000, days: 0, sw: false), contains('since today'));
      expect(reminderSentence(owner: 'S', customer: 'A', amount: 1000, days: 1, sw: false), contains('outstanding for 1 day.'));
    });

    test('without the owner\'s name the greeting is just a greeting', () {
      expect(reminderSentence(owner: '  ', customer: 'A', amount: 1000, days: 2, sw: true), startsWith('Habari, mteja A'));
      expect(reminderSentence(owner: '', customer: 'A', amount: 1000, days: 2, sw: false), startsWith('Hello, customer A'));
    });

    test('a decimal amount is read as a whole number of shillings', () {
      expect(reminderSentence(owner: 'S', customer: 'A', amount: 1234.6, days: 2, sw: false), contains('1235 shillings'));
    });
  });

  group('what can be read', () {
    test('a payment reminder with a customer and an amount', () => expect(canSpeak(_r(1)), isTrue));
    test('not a low-stock one', () => expect(canSpeak(_r(1, type: 'low_stock')), isFalse));
    test('not one without a customer name or with nothing left', () {
      expect(canSpeak(_r(1, name: null)), isFalse);
      expect(canSpeak(_r(1, name: '  ')), isFalse);
      expect(canSpeak(_r(1, left: 0)), isFalse);
      expect(canSpeak(_r(1, left: null)), isFalse);
    });
    test('not one that is done or put away for a while', () {
      expect(canSpeak(_r(1, status: InvReminderStatus.done)), isFalse);
      expect(canSpeak(_r(1, status: InvReminderStatus.snoozed)), isFalse);
    });
  });

  group('reading aloud', () {
    test('reads each reminder that can be read, in order, in the chosen language', () async {
      final _Speech speech = _Speech();
      final ReminderVoice voice = ReminderVoice(speech: speech);

      final VoiceResult r = await voice.read(<InvReminder>[_r(1, name: 'Asha', left: 1000), _r(2, type: 'low_stock'), _r(3, name: 'Juma', left: 2000, days: 0)], owner: 'Samwel', sw: true);

      expect(r, VoiceResult.done);
      expect(speech.languages, <bool>[true], reason: 'the voice was prepared for Kiswahili');
      expect(speech.said, hasLength(2), reason: 'the low-stock reminder was not read');
      expect(speech.said[0], contains('Asha'));
      expect(speech.said[1], contains('Juma'));
      expect(voice.speaking, isFalse);
    });

    test('nothing to read says so and does not touch the voice', () async {
      final _Speech speech = _Speech();

      final VoiceResult r = await ReminderVoice(speech: speech).read(<InvReminder>[_r(1, type: 'low_stock')], owner: 'S', sw: false);

      expect(r, VoiceResult.nothingToRead);
      expect(speech.languages, isEmpty);
    });

    test('a phone without the voice for the language says so, and reads nothing in another language', () async {
      final _Speech speech = _Speech(hasVoice: false);

      final VoiceResult r = await ReminderVoice(speech: speech).read(<InvReminder>[_r(1)], owner: 'S', sw: true);

      expect(r, VoiceResult.noVoice);
      expect(speech.said, isEmpty);
    });

    test('it can be stopped between two reminders', () async {
      final _Speech speech = _Speech();
      final ReminderVoice voice = ReminderVoice(speech: speech);
      speech.onSay = () => voice.stop();

      final VoiceResult r = await voice.read(<InvReminder>[_r(1), _r(2), _r(3)], owner: 'S', sw: false);

      expect(r, VoiceResult.stopped);
      expect(speech.said, hasLength(1), reason: 'the rest were not read');
      expect(speech.stopped, isTrue);
      expect(voice.speaking, isFalse);
    });

    test('a new reading after a stop starts clean', () async {
      final _Speech speech = _Speech();
      final ReminderVoice voice = ReminderVoice(speech: speech);
      await voice.stop();

      final VoiceResult r = await voice.read(<InvReminder>[_r(1)], owner: 'S', sw: false);

      expect(r, VoiceResult.done);
      expect(speech.said, hasLength(1));
    });
  });
}
