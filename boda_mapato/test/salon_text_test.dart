import 'package:boda_mapato/modules/inventory/screens/salon/salon_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sentences the salon screens build from numbers must read correctly in both languages: "wiki moja" for one
/// week and "wiki 4" for four, "Wiki moja iliyopita" and "Wiki 4 zilizopita", "one week ago" and "4 weeks ago".
void main() {
  group('weeks, said the way each language says them', () {
    test('Swahili: one is "wiki moja", more is "wiki N"', () {
      expect(weeksLabel(sw: true, weeks: 1), 'wiki moja');
      expect(weeksLabel(sw: true, weeks: 2), 'wiki 2');
      expect(weeksLabel(sw: true, weeks: 4), 'wiki 4');
      expect(weeksLabel(sw: true, weeks: 12), 'wiki 12');
    });

    test('English: "one week", "4 weeks"', () {
      expect(weeksLabel(sw: false, weeks: 1), 'one week');
      expect(weeksLabel(sw: false, weeks: 4), '4 weeks');
    });

    test('Swahili "ago" agrees with the number: iliyopita for one, zilizopita for more', () {
      expect(weeksAgo(sw: true, weeks: 0), 'Wiki hii');
      expect(weeksAgo(sw: true, weeks: 1), 'Wiki moja iliyopita');
      expect(weeksAgo(sw: true, weeks: 4), 'Wiki 4 zilizopita');
      expect(weeksAgo(sw: true, weeks: 6), 'Wiki 6 zilizopita');
    });

    test('English "ago"', () {
      expect(weeksAgo(sw: false, weeks: 0), 'This week');
      expect(weeksAgo(sw: false, weeks: 1), 'One week ago');
      expect(weeksAgo(sw: false, weeks: 4), '4 weeks ago');
    });
  });

  group('dates and money', () {
    test('a day is written dd/MM/yyyy, with the zeros', () {
      expect(dayLabel(DateTime(2026, 11, 5)), '05/11/2026');
      expect(dayLabel(DateTime(2026, 1, 31)), '31/01/2026');
    });

    test('money has thousands separators and no decimals', () {
      expect(tsh(0), 'TSH 0');
      expect(tsh(999), 'TSH 999');
      expect(tsh(1000), 'TSH 1,000');
      expect(tsh(45000.4), 'TSH 45,000');
      expect(tsh(1234567), 'TSH 1,234,567');
      expect(tsh(-2500), 'TSH -2,500');
    });
  });
}
