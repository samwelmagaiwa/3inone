import 'package:boda_mapato/utils/server_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// The server writes times in UTC; receipts must show Tanzania time (UTC+3), not the UTC wall clock and not the phone's own zone.
void main() {
  String shown(final dynamic v) => DateFormat('dd/MM/yyyy HH:mm').format(parseServerTime(v)!);

  test('a plain server time is UTC and is shown three hours later, in Tanzania', () {
    expect(shown('2026-10-27 06:30:00'), '27/10/2026 09:30');
    expect(shown('2026-10-27T06:30:00'), '27/10/2026 09:30');
  });

  test('a time with a Z (Laravel JSON) is the same', () {
    expect(shown('2026-10-27T06:30:00.000000Z'), '27/10/2026 09:30');
  });

  test('late evening in Tanzania is already the next day in UTC terms: the date moves with the hours', () {
    expect(shown('2026-10-27 21:30:00'), '28/10/2026 00:30');
  });

  test('a time that already says its zone is respected', () {
    expect(shown('2026-10-27T09:30:00+03:00'), '27/10/2026 09:30');
    expect(shown('2026-10-27T05:00:00-01:00'), '27/10/2026 09:00');
  });

  test('nothing or text that is not a time gives null, never a wrong time', () {
    expect(parseServerTime(null), isNull);
    expect(parseServerTime(''), isNull);
    expect(parseServerTime('yesterday'), isNull);
  });

  test('the result does not depend on the phone\'s own time zone', () {
    final DateTime t = parseServerTime('2026-10-27 06:30:00')!;
    expect(t.isUtc, isFalse);
    expect(<int>[t.hour, t.minute], <int>[9, 30]);
  });
}
