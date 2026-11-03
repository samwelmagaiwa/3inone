import 'package:shared_preferences/shared_preferences.dart';

import '../models/inv_reminder.dart';
import 'reminder_voice.dart';

/// The owner's choice about the phone reading the debts aloud by itself, and the day it last did.
class VoiceSettings {
  static const String _autoKey = 'voice_auto_read';
  static const String _lastKey = 'voice_last_read_day';

  /// Reads the debts aloud when the app is opened, once a day. On until the owner switches it off.
  static Future<bool> autoRead() async => (await SharedPreferences.getInstance()).getBool(_autoKey) ?? true;

  static Future<void> setAutoRead(final bool on) async => (await SharedPreferences.getInstance()).setBool(_autoKey, on);

  static String _day(final DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Has it not been read yet today?
  static Future<bool> dueToday(final DateTime now) async => (await SharedPreferences.getInstance()).getString(_lastKey) != _day(now);

  static Future<void> markReadToday(final DateTime now) async => (await SharedPreferences.getInstance()).setString(_lastKey, _day(now));
}

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
    final VoiceResult result = await (voice ?? ReminderVoice.shared).read(reminders, owner: owner, sw: sw);
    // Said (or stopped by the owner): that is today's reading. No voice or nothing to read: try again next time the app opens.
    if (result == VoiceResult.done || result == VoiceResult.stopped) await VoiceSettings.markReadToday(today);

    return result;
  }
}
