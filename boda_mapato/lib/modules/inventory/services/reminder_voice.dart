import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../services/localization_service.dart';
import '../models/inv_reminder.dart';
import 'number_words.dart';
import 'voice_settings.dart';

/// What the phone says for one payment reminder, in the language chosen in the app (the wording is in the translations). The amount and
/// the days are written in words, because a voice reads digits badly ("430000" is not clear to hear):
///
///  - Kiswahili: "Habari Samwel, mteja Mama Chale anadaiwa kiasi cha shilingi laki nne na elfu thelathini ndani ya siku tatu. Huu ni ukumbusho."
///  - English:   "Hello Samwel, customer Mama Chale owes four hundred thirty thousand shillings, outstanding for three days. This is a reminder."
///
/// The owner's name is left out of the greeting when it is not known. A debt from today says "today".
String reminderSentence({required final String owner, required final String customer, required final num amount, required final int days}) {
  final LocalizationService loc = LocalizationService.instance;
  final bool sw = loc.isSwahili;
  final String greeting = owner.trim().isEmpty ? loc.translate('voice_hello') : '${loc.translate('voice_hello')} ${owner.trim()}';
  final String when = days <= 0
      ? loc.translate('voice_when_today')
      : days == 1
          ? loc.translate('voice_when_day')
          : loc.translate('voice_when_days').replaceAll('{n}', numberInWords(days, sw: sw));

  return loc
      .translate('voice_sentence')
      .replaceAll('{greeting}', greeting)
      .replaceAll('{customer}', customer)
      .replaceAll('{amount}', numberInWords(amount.round(), sw: sw))
      .replaceAll('{when}', when);
}

/// The best voice the phone has for a language, from what it lists (`name`, `locale`): the Google network voices are the clearest, then
/// any other, and a voice marked as a basic local or legacy one is the last choice. [locales] is the order of preference
/// (Tanzania first for Kiswahili). Null when the phone lists no voice for any of them.
Map<String, String>? pickVoice(final List<dynamic> voices, final List<String> locales) {
  String norm(final String s) => s.replaceAll('_', '-').toLowerCase();
  int score(final String name) {
    final String n = name.toLowerCase();
    if (n.contains('network') || n.contains('neural') || n.contains('wavenet')) return 3;
    if (n.contains('legacy') || n.contains('compact') || n.contains('espeak')) return 0;
    if (n.contains('local')) return 1;

    return 2;
  }

  for (final String wanted in locales) {
    Map<String, String>? best;
    int bestScore = -1;
    for (final dynamic v in voices) {
      if (v is! Map) continue;
      final String name = (v['name'] ?? '').toString();
      final String locale = (v['locale'] ?? '').toString();
      if (name.isEmpty || norm(locale) != norm(wanted)) continue;
      if (score(name) > bestScore) {
        bestScore = score(name);
        best = <String, String>{'name': name, 'locale': locale};
      }
    }
    if (best != null) return best;
  }

  return null;
}

/// Can this reminder be read aloud? Only an open payment reminder that knows whose debt it is and how much is left (one put away for a
/// while, or done, is not read).
bool canSpeak(final InvReminder r) => r.type == 'payment_due' && r.status == InvReminderStatus.open && (r.customerName ?? '').trim().isNotEmpty && (r.amountLeft ?? 0) > 0;

/// One voice the phone has: its name, its language and whether it is one of the clearer (network) ones.
class VoiceOption {
  const VoiceOption({required this.name, required this.locale, this.network = false});

  final String name;
  final String locale;
  final bool network;
}

/// The speaker of the phone, as far as this app needs it (so a test can stand in for it).
abstract class SpeechPort {
  /// Gets the voice ready for the language, with the voice the owner picked ([voiceName], or the best one when null) at the pace [rate];
  /// false when the phone has no voice for it (Swahili must be installed on some phones).
  Future<bool> prepare({required bool swahili, String? voiceName, double rate = 0.42});

  /// The voices the phone has for the language, so the owner can listen and choose.
  Future<List<VoiceOption>> voices({required bool swahili});

  /// Says [text] and returns when it has been said (or stopped).
  Future<void> speak(String text);

  Future<void> stop();
}

/// The real speaker: the phone's own text-to-speech engine, Google's when it is there, with the clearest voice it has for the language
/// (Tanzania's Kiswahili first), at a calm pace so every word is heard.
class DeviceSpeech implements SpeechPort {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<bool> prepare({required final bool swahili, final String? voiceName, final double rate = 0.42}) async {
    try {
      await _tts.awaitSpeakCompletion(true);
      // Google's engine has the Kiswahili (and the clearest English) voices; use it when the phone has it.
      try {
        final dynamic engines = await _tts.getEngines;
        if (engines is List && engines.contains('com.google.android.tts')) await _tts.setEngine('com.google.android.tts');
      } on Exception {
        // the phone's own engine is used
      }
      final List<String> tries = swahili ? <String>['sw-TZ', 'sw-KE', 'sw'] : <String>['en-US', 'en-GB', 'en'];
      for (final String lang in tries) {
        final dynamic ok = await _tts.isLanguageAvailable(lang);
        if (ok == true || ok == 1) {
          await _tts.setLanguage(lang);
          try {
            final List<dynamic> listed = await _tts.getVoices as List<dynamic>;
            // the voice the owner picked, when the phone still has it; else the clearest one for the language
            Map<String, String>? voice;
            if (voiceName != null) {
              for (final dynamic v in listed) {
                if (v is Map && v['name']?.toString() == voiceName) voice = <String, String>{'name': voiceName, 'locale': (v['locale'] ?? '').toString()};
              }
            }
            voice ??= pickVoice(listed, tries);
            if (voice != null) await _tts.setVoice(voice);
          } on Exception {
            // the language's default voice is used
          }
          await _tts.setSpeechRate(rate);
          await _tts.setPitch(1.0);
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
  Future<List<VoiceOption>> voices({required final bool swahili}) async {
    try {
      final List<dynamic> listed = await _tts.getVoices as List<dynamic>;
      final String prefix = swahili ? 'sw' : 'en';
      final List<VoiceOption> out = <VoiceOption>[
        for (final dynamic v in listed)
          if (v is Map && (v['locale'] ?? '').toString().toLowerCase().replaceAll('_', '-').startsWith(prefix) && (v['name'] ?? '').toString().isNotEmpty)
            VoiceOption(name: v['name'].toString(), locale: v['locale'].toString(), network: v['name'].toString().toLowerCase().contains('network')),
      ];
      out.sort((VoiceOption a, VoiceOption b) {
        // Tanzania before the rest for Kiswahili, then the clearer (network) voices
        int rank(final VoiceOption o) => (swahili && o.locale.toLowerCase().replaceAll('_', '-') == 'sw-tz' ? 0 : 2) + (o.network ? 0 : 1);

        return rank(a).compareTo(rank(b));
      });

      return out;
    } on Exception {
      return const <VoiceOption>[];
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

  /// The one reader the whole app shares, so the screen can show "Stop" for a reading that began when the app was opened.
  static final ReminderVoice shared = ReminderVoice();

  final SpeechPort _speech;
  bool _speaking = false;
  bool _stop = false;

  bool get speaking => _speaking;

  /// Reads every reminder in [reminders] that can be read, in the order given. [keepGoing] is asked before each one: when it says no (the
  /// owner switched the reading off) the reading stops there.
  Future<VoiceResult> read(final List<InvReminder> reminders, {required final String owner, required final bool sw, final Future<bool> Function()? keepGoing}) async {
    final List<InvReminder> readable = reminders.where(canSpeak).toList();
    if (readable.isEmpty) return VoiceResult.nothingToRead;
    if (!await _speech.prepare(swahili: sw, voiceName: await VoiceSettings.voiceName(swahili: sw), rate: await VoiceSettings.rate())) return VoiceResult.noVoice;

    _stop = false;
    _speaking = true;
    notifyListeners();
    try {
      for (final InvReminder r in readable) {
        if (_stop || (keepGoing != null && !await keepGoing())) {
          _stop = true;

          return VoiceResult.stopped;
        }
        await _speech.speak(reminderSentence(owner: owner, customer: r.customerName!.trim(), amount: r.amountLeft!, days: r.days ?? 0));
      }
    } finally {
      _speaking = false;
      notifyListeners();
    }

    return _stop ? VoiceResult.stopped : VoiceResult.done;
  }

  /// The voices the phone has for the language (for the owner to listen to and choose from).
  Future<List<VoiceOption>> voices({required final bool sw}) => _speech.voices(swahili: sw);

  /// Says [text] with the given voice and pace, so the owner can hear a choice before keeping it. False when the phone has no voice.
  Future<bool> preview(final String text, {required final bool sw, final String? voiceName, required final double rate}) async {
    await _speech.stop();
    if (!await _speech.prepare(swahili: sw, voiceName: voiceName, rate: rate)) return false;
    await _speech.speak(text);

    return true;
  }

  Future<void> stop() async {
    _stop = true;
    await _speech.stop();
  }
}
