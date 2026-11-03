import 'package:boda_mapato/modules/inventory/services/number_words.dart';
import 'package:boda_mapato/modules/inventory/services/reminder_voice.dart';
import 'package:flutter_test/flutter_test.dart';

/// Amounts and days are said in words (a voice reads digits badly), in the money words Tanzanians use, and the clearest voice the phone
/// lists is the one chosen.
void main() {
  group('Kiswahili', () {
    String sw(int n) => numberInWords(n, sw: true);

    test('small numbers', () {
      expect(sw(0), 'sifuri');
      expect(sw(1), 'moja');
      expect(sw(3), 'tatu');
      expect(sw(10), 'kumi');
      expect(sw(11), 'kumi na moja');
      expect(sw(25), 'ishirini na tano');
      expect(sw(99), 'tisini na tisa');
    });

    test('hundreds', () {
      expect(sw(100), 'mia moja');
      expect(sw(250), 'mia mbili na hamsini');
      expect(sw(999), 'mia tisa na tisini na tisa');
    });

    test('thousands and laki, the way money is said', () {
      expect(sw(1000), 'elfu moja');
      expect(sw(2500), 'elfu mbili na mia tano');
      expect(sw(30000), 'elfu thelathini');
      expect(sw(100000), 'laki moja');
      expect(sw(430000), 'laki nne na elfu thelathini');
      expect(sw(150000), 'laki moja na elfu hamsini');
      expect(sw(999999), 'laki tisa na elfu tisini na tisa na mia tisa na tisini na tisa');
    });

    test('millions and billions', () {
      expect(sw(1000000), 'milioni moja');
      expect(sw(5610000), 'milioni tano na laki sita na elfu kumi');
      expect(sw(14990000), 'milioni kumi na nne na laki tisa na elfu tisini');
      expect(sw(2000000000), 'bilioni mbili');
    });

    test('a negative number says "hasi"', () => expect(sw(-5), 'hasi tano'));
  });

  group('English', () {
    String en(int n) => numberInWords(n, sw: false);

    test('the numbers a debt can be', () {
      expect(en(0), 'zero');
      expect(en(3), 'three');
      expect(en(19), 'nineteen');
      expect(en(40), 'forty');
      expect(en(250), 'two hundred fifty');
      expect(en(1000), 'one thousand');
      expect(en(430000), 'four hundred thirty thousand');
      expect(en(5610000), 'five million six hundred ten thousand');
      expect(en(14990000), 'fourteen million nine hundred ninety thousand');
      expect(en(1000001), 'one million one');
    });
  });

  group('choosing the voice', () {
    final List<dynamic> voices = <dynamic>[
      <String, String>{'name': 'en-us-x-iom-local', 'locale': 'en-US'},
      <String, String>{'name': 'sw-ke-x-sfa-local', 'locale': 'sw-KE'},
      <String, String>{'name': 'sw-tz-x-legacy', 'locale': 'sw-TZ'},
      <String, String>{'name': 'sw-tz-x-sfa-network', 'locale': 'sw_TZ'},
      <String, String>{'name': 'sw-tz-x-sfa-local', 'locale': 'sw-TZ'},
      <String, String>{'name': 'en-us-x-tpf-network', 'locale': 'en-US'},
      <String, String>{'name': 'en-gb-x-gba-network', 'locale': 'en-GB'},
    ];

    test('Tanzania first, and the clearest (network) voice of it', () {
      expect(pickVoice(voices, <String>['sw-TZ', 'sw-KE', 'sw'])!['name'], 'sw-tz-x-sfa-network');
    });

    test('a local voice is chosen over a legacy one when there is no network voice', () {
      expect(pickVoice(voices.where((dynamic v) => !(v as Map)['name']!.toString().contains('network')).toList(), <String>['sw-TZ'])!['name'], 'sw-tz-x-sfa-local');
    });

    test('Kenya is the next choice when Tanzania has none', () {
      final List<dynamic> noTz = voices.where((dynamic v) => !(v as Map)['locale']!.toString().toLowerCase().startsWith('sw-tz') && !v['locale'].toString().toLowerCase().startsWith('sw_tz')).toList();

      expect(pickVoice(noTz, <String>['sw-TZ', 'sw-KE', 'sw'])!['name'], 'sw-ke-x-sfa-local');
    });

    test('English picks the clearest English', () {
      expect(pickVoice(voices, <String>['en-US', 'en-GB', 'en'])!['name'], 'en-us-x-tpf-network');
    });

    test('nothing listed for the language is nothing', () {
      expect(pickVoice(voices, <String>['fr-FR']), isNull);
      expect(pickVoice(<dynamic>[], <String>['sw-TZ']), isNull);
      expect(pickVoice(<dynamic>['not a map', <String, String>{'name': '', 'locale': 'sw-TZ'}], <String>['sw-TZ']), isNull);
    });
  });
}
