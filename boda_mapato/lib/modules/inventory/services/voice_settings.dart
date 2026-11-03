import 'package:shared_preferences/shared_preferences.dart';

/// The owner's choices about the phone reading the debts aloud: whether it reads by itself when the app is opened (and the day it last
/// did), which voice, and how fast.
class VoiceSettings {
  static const String _autoKey = 'voice_auto_read';
  static const String _lastKey = 'voice_last_read_day';
  static const String _rateKey = 'voice_rate';

  /// Reads the debts aloud when the app is opened, once a day. On until the owner switches it off.
  static Future<bool> autoRead() async => (await SharedPreferences.getInstance()).getBool(_autoKey) ?? true;

  static Future<void> setAutoRead(final bool on) async => (await SharedPreferences.getInstance()).setBool(_autoKey, on);

  static String _day(final DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Has it not been read yet today?
  static Future<bool> dueToday(final DateTime now) async => (await SharedPreferences.getInstance()).getString(_lastKey) != _day(now);

  static Future<void> markReadToday(final DateTime now) async => (await SharedPreferences.getInstance()).setString(_lastKey, _day(now));

  /// The voice the owner picked for a language (its name as the phone lists it), or null for "the best one the phone has".
  static Future<String?> voiceName({required final bool swahili}) async => (await SharedPreferences.getInstance()).getString(swahili ? 'voice_name_sw' : 'voice_name_en');

  static Future<void> setVoiceName(final String? name, {required final bool swahili}) async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    final String key = swahili ? 'voice_name_sw' : 'voice_name_en';
    if (name == null) {
      await p.remove(key);
    } else {
      await p.setString(key, name);
    }
  }

  /// How fast it speaks: slow, normal or fast (a number the phone's voice takes, 0.42 being a calm pace).
  static const Map<String, double> speeds = <String, double>{'slow': 0.32, 'normal': 0.42, 'fast': 0.55};

  static Future<String> speed() async {
    final String? s = (await SharedPreferences.getInstance()).getString(_rateKey);

    return speeds.containsKey(s) ? s! : 'normal';
  }

  static Future<void> setSpeed(final String speed) async => (await SharedPreferences.getInstance()).setString(_rateKey, speeds.containsKey(speed) ? speed : 'normal');

  static Future<double> rate() async => speeds[await speed()]!;
}
