/// Times the server writes ("2026-10-27 06:30:00", or "2026-10-27T06:30:00.000000Z") are UTC; Tanzania is UTC+3 all year (no daylight
/// saving). Read one as the wall-clock time in Tanzania, so a receipt shows when the sale really happened, whatever the phone's own
/// time zone is set to. A time that already says its zone (a "Z" or "+03:00") is respected.
///
/// Returns null for nothing or for text that is not a time.
DateTime? parseServerTime(final dynamic value) {
  if (value == null) return null;
  final String text = '$value'.trim();
  if (text.isEmpty) return null;

  final bool hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(text);
  final DateTime? parsed = DateTime.tryParse(hasZone ? text : '${text.replaceFirst(' ', 'T')}Z');
  if (parsed == null) return null;

  final DateTime eat = parsed.toUtc().add(const Duration(hours: 3));

  // A plain DateTime holding the Tanzania clock, so formatting it shows exactly that.
  return DateTime(eat.year, eat.month, eat.day, eat.hour, eat.minute, eat.second, eat.millisecond);
}
