import '../models/inv_reminder.dart';
import 'reminder_voice.dart';
import 'voice_settings.dart';

export 'voice_settings.dart';

/// Reads the debt reminders aloud when the app is opened: once a day, only when the owner has not switched it off, and only when there is
/// something to read (a day with no debt reminder is not "used up").
class DailyDebtVoice {
  /// Returns how it went, or null when it did not try (switched off, or already read today).
  static Future<VoiceResult?> maybeRead({
    required final Future<List<InvReminder>> Function() load,
    required final String owner,
    required final bool sw,
    final ReminderVoice? voice,
    final DateTime? now,
  }) async {
    final DateTime today = now ?? DateTime.now();
    if (!await VoiceSettings.autoRead() || !await VoiceSettings.dueToday(today)) return null;

    final List<InvReminder> reminders = await load();
    // The owner may switch the reading off while it is going on: that stops it before the next reminder.
    final VoiceResult result = await (voice ?? ReminderVoice.shared).read(reminders, owner: owner, sw: sw, keepGoing: VoiceSettings.autoRead);
    // Said (or stopped by the owner): that is today's reading. No voice or nothing to read: try again next time the app opens.
    if (result == VoiceResult.done || result == VoiceResult.stopped) await VoiceSettings.markReadToday(today);

    return result;
  }
}
