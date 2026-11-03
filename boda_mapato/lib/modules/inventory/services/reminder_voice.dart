import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../services/localization_service.dart';
import '../models/inv_reminder.dart';

/// What the phone says for one payment reminder, in the language chosen in the app (the wording is in the translations):
///
///  - Kiswahili: "Habari Samwel, mteja Mama Chale anadaiwa kiasi cha shilingi 430000 ndani ya siku 3. Huu ni ukumbusho."
///  - English:   "Hello Samwel, customer Mama Chale owes 430000 shillings, outstanding for 3 days. This is a reminder."
///
/// The owner's name is left out of the greeting when it is not known. A debt from today says "today".
String reminderSentence({required final String owner, required final String customer, required final num amount, required final int days}) {
  final LocalizationService loc = LocalizationService.instance;
  final String greeting = owner.trim().isEmpty ? loc.translate('voice_hello') : '${loc.translate('voice_hello')} ${owner.trim()}';
  final String when = days <= 0
      ? loc.translate('voice_when_today')
      : days == 1
          ? loc.translate('voice_when_day')
          : loc.translate('voice_when_days').replaceAll('{n}', '$days');

  return loc
      .translate('voice_sentence')
      .replaceAll('{greeting}', greeting)
      .replaceAll('{customer}', customer)
      .replaceAll('{amount}', amount.round().toString())
      .replaceAll('{when}', when);
}

/// Can this reminder be read aloud? Only an open payment reminder that knows whose debt it is and how much is left (one put away for a
/// while, or done, is not read).
bool canSpeak(final InvReminder r) => r.type == 'payment_due' && r.status == InvReminderStatus.open && (r.customerName ?? '').trim().isNotEmpty && (r.amountLeft ?? 0) > 0;

/// The speaker of the phone, as far as this app needs it (so a test can stand in for it).
abstract class SpeechPort {
  /// Gets the voice ready for the language; false when the phone has no voice for it (Swahili must be installed on some phones).
  Future<bool> prepare({required bool swahili});

  /// Says [text] and returns when it has been said (or stopped).
  Future<void> speak(String text);

  Future<void> stop();
}

/// The real speaker: the phone's own text-to-speech engine.
class DeviceSpeech implements SpeechPort {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<bool> prepare({required final bool swahili}) async {
    try {
      await _tts.awaitSpeakCompletion(true);
      final List<String> tries = swahili ? <String>['sw-TZ', 'sw-KE', 'sw'] : <String>['en-US', 'en-GB', 'en'];
      for (final String lang in tries) {
        final dynamic ok = await _tts.isLanguageAvailable(lang);
        if (ok == true || ok == 1) {
          await _tts.setLanguage(lang);
          await _tts.setSpeechRate(0.45);
          await _tts.setVolume(1.0);

          return true;
        }
      }

      return false;
    } on Exception {
      return false;
    }
  }

  @override
  Future<void> speak(final String text) async {
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }
}

/// How a reading ended.
enum VoiceResult { done, nothingToRead, noVoice, stopped }

/// Reads reminders aloud, one after the other, and can be stopped. [speaking] tells a screen to show "Stop".
class ReminderVoice extends ChangeNotifier {
  ReminderVoice({SpeechPort? speech}) : _speech = speech ?? DeviceSpeech();

  final SpeechPort _speech;
  bool _speaking = false;
  bool _stop = false;

  bool get speaking => _speaking;

  /// Reads every reminder in [reminders] that can be read, in the order given.
  Future<VoiceResult> read(final List<InvReminder> reminders, {required final String owner, required final bool sw}) async {
    final List<InvReminder> readable = reminders.where(canSpeak).toList();
    if (readable.isEmpty) return VoiceResult.nothingToRead;
    if (!await _speech.prepare(swahili: sw)) return VoiceResult.noVoice;

    _stop = false;
    _speaking = true;
    notifyListeners();
    try {
      for (final InvReminder r in readable) {
        if (_stop) return VoiceResult.stopped;
        await _speech.speak(reminderSentence(owner: owner, customer: r.customerName!.trim(), amount: r.amountLeft!, days: r.days ?? 0));
      }
    } finally {
      _speaking = false;
      notifyListeners();
    }

    return _stop ? VoiceResult.stopped : VoiceResult.done;
  }

  Future<void> stop() async {
    _stop = true;
    await _speech.stop();
  }
}
