import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Text a person reads must come from the translations, so it follows the language chosen in the app.
/// A Swahili sentence written straight into a Transport screen shows up in Swahili even when the app is
/// in English (and the reverse), which is how a screen ends up half in one language and half in the other.
///
/// This scans the Transport screens and everything they share for Swahili words inside string literals that
/// are not translated. A literal that is really data (a value the server stores, sample data, a file name)
/// goes in [allowed] with the reason.
void main() {
  // Words that only Swahili uses (no English word is spelled like these).
  const Set<String> swahili = <String>{
    'hakuna', 'imeshindikana', 'tafadhali', 'hitilafu', 'malipo', 'dereva', 'madereva', 'chagua', 'ingiza',
    'tarehe', 'kiasi', 'hifadhi', 'ghairi', 'ripoti', 'deni', 'madeni', 'chombo', 'vyombo', 'magari',
    'mteja', 'wateja', 'risiti', 'kikumbusho', 'vikumbusho', 'mikumbusho', 'makubaliano', 'mkataba',
    'imehifadhiwa', 'imefutwa', 'imekamilika', 'imeshalipwa', 'imelipwa', 'haijalipwa', 'inapakia',
    'inahifadhi', 'inatuma', 'jaribu', 'sahihi', 'lazima', 'hiari', 'maelezo', 'ujumbe', 'mawasiliano',
    'jumla', 'mapato', 'matumizi', 'faida', 'kuhusu', 'kupakia', 'kuhifadhi', 'kufuta', 'kuongeza',
    'kurekodi', 'kusajili', 'kuondoa', 'kuweka', 'weka', 'ongeza', 'rekodi', 'hariri', 'futa', 'tuma',
    'funga', 'fungua', 'sawa', 'ndio', 'hapana', 'wiki', 'mwezi', 'siku', 'saa', 'leo', 'jana', 'kesho',
    'leseni', 'simu', 'barua', 'pepe', 'namba', 'nambari', 'aina', 'hali', 'jina', 'kamili', 'muda',
    'kipindi', 'kiwango', 'wastani', 'safari', 'gari', 'bajaji', 'pikipiki', 'utabiri', 'historia',
    'muhtasari', 'taarifa', 'usimamizi', 'simamia', 'kikamilifu', 'mafanikio', 'bado', 'yote', 'wote',
    'kila', 'mara', 'moja', 'zilizopita', 'iliyopita', 'uliopita', 'inayotarajiwa', 'karibu', 'asante',
    'huduma', 'dharura', 'kipaumbele', 'chini', 'juu', 'mpya', 'kipya', 'ahadi', 'wikendi',
    'fedha', 'taslimu', 'benki', 'uhamisho', 'kadi', 'nyingine', 'mengine', 'hakikisha', 'wasiliana',
    'msimamizi', 'akaunti', 'seva', 'mtandao', 'nywila', 'nenosiri',
    'faili', 'miamala', 'amezimwa', 'amewashwa', 'amefutwa', 'imetengenezwa', 'imetumwa', 'yamepewa',
    'hayajapewa', 'ondoa', 'inazosubiri', 'unataka', 'uhakika', 'kitendo', 'kumfuta', 'upakuaji',
    'limehifadhiwa', 'haupatikani', 'mtumiaji', 'mfumo', 'wapangaji', 'wafanyakazi', 'kuingia', 'tafuta',
    'chuja', 'onyesha', 'upya', 'bofya', 'kitufe', 'kichwa', 'ndogo', 'kubwa', 'zote', 'hii', 'huu',
  };

  // Every word the Swahili translations use that no English translation uses (4+ letters). It grows with the
  // translations, so a Swahili sentence that nobody thought to list here is still recognised.
  Set<String> swahiliOnlyWords() {
    final String source = File('lib/services/localization_service.dart').readAsStringSync();
    final int enStart = source.indexOf("    'en': {");
    final int swStart = source.indexOf("    'sw': {");
    final int end = source.indexOf('\n  };', swStart);
    Set<String> wordsOf(String part) {
      final Set<String> words = <String>{};
      // a quoted text that is not a key (a key is followed by a colon)
      for (final RegExpMatch m in RegExp(r"'((?:[^'\\\n]|\\.)*)'(?!\s*:)").allMatches(part)) {
        for (final RegExpMatch w in RegExp(r'[a-z]{4,}').allMatches(m.group(1)!.toLowerCase())) {
          words.add(w.group(0)!);
        }
      }
      return words;
    }

    final Set<String> sw = wordsOf(source.substring(swStart, end));
    final Set<String> en = wordsOf(source.substring(enStart, swStart));
    // words that are also names or terms kept as they are in both languages
    const Set<String> shared = <String>{'boda', 'whatsapp', 'tsh', 'bajaji', 'pikipiki', 'safari', 'admin', 'email', 'dashboard'};
    return sw.difference(en).difference(shared);
  }

  // Where the Transport screens and their shared parts live.
  const List<String> places = <String>[
    'lib/screens/admin',
    'lib/screens/payments',
    'lib/screens/reports',
    'lib/screens/reminders',
    'lib/screens/receipts',
    'lib/screens/driver',
    'lib/screens/transactions',
    'lib/screens/device_selection',
    'lib/screens/dashboard',
    'lib/screens/settings',
    'lib/modules/inventory',
    'lib/constants/theme_constants.dart',
    'lib/screens/rental',
    'lib/screens/maintenance',
    'lib/providers',
    'lib/services/api_service.dart',
    'lib/utils/validation.dart',
    'lib/utils/rental_flow_validator.dart',
    'lib/utils/type_helpers.dart',
    'lib/utils/maintenance_labels.dart',
    'lib/widgets/reminder_tile.dart',
    'lib/widgets/receipt_tile.dart',
    'lib/widgets/transaction_tile.dart',
    'lib/models',
    'lib/utils/date_utils.dart',
    'lib/constants/strings.dart',
  ];

  // Literals that are DATA, not text a person reads, or sample content. Exact text -> why it stays.
  const Map<String, String> allowed = <String, String>{
    'Kwa Mkataba': 'agreement type value compared with what the screen stores; shown through a translation',
    'Dei Waka': 'agreement type value compared with what the screen stores; shown through a translation',
    'Historia_{0}_{1}.pdf': 'file name',
    'John Doe,john@example.com,+255712345678,DL123456,T123ABC,pikipiki,active':
        'sample row of the import template: a CSV line whose last columns are values the server stores',
    'kwa_mkataba': 'value the server stores',
    'dei_waka': 'value the server stores',
    'kila_siku': 'value the server stores',
    'kila_wiki': 'value the server stores',
    'kila_mwezi': 'value the server stores',
    'kiasi_cha_makubaliano': 'field name the server uses',
    'faida_jumla': 'field name the server uses',
    'mwaka_atamaliza': 'field name the server uses',
    'bajaji': 'vehicle type value the server stores',
    'pikipiki': 'vehicle type value the server stores',
    'gari': 'vehicle type value the server stores',
    'Mara': 'a region of Tanzania (a proper name)',
    '• Hifadhi ya kiotomatiki inafanywa kila siku saa 2:00 usiku':
        'one line of a bullet list that is written out in both languages right above the English one',
  };

  // The language is being chosen right there on the line (or just above it): both texts are written out.
  final RegExp chosenByLanguage = RegExp(
    r'isSwahili|isSw\b|\bsw\s*\?|_sw\b|\bswahili\s*\?|isEnglish|translate\(|translateWith\(|translateForKind\(|vehicleTypeLabel\(',
  );

  String withoutComments(String src) {
    String s = src.replaceAllMapped(RegExp(r'/\*[\s\S]*?\*/'), (Match m) => '\n' * '\n'.allMatches(m.group(0)!).length);
    s = s.replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');
    return s;
  }

  List<File> dartFiles() {
    final List<File> files = <File>[];
    for (final String place in places) {
      final FileSystemEntity e = FileSystemEntity.isDirectorySync(place) ? Directory(place) : File(place);
      if (e is Directory) {
        files.addAll(e.listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart')));
      } else if (e is File && e.existsSync()) {
        files.add(e);
      }
    }
    return files;
  }

  final RegExp literal = RegExp(r"""'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)" """.trim());

  test('Transport screens and what they share have no hard-coded Swahili text', () {
    final List<String> found = <String>[];
    final Set<String> vocabulary = swahiliOnlyWords();
    for (final File file in dartFiles()) {
      final String src = withoutComments(file.readAsStringSync());
      final List<String> lines = src.split('\n');
      // A table written for ONE language on purpose ('sw': { ... } of the contract clauses) is not "hard-coded":
      // it is the Swahili version, picked by language. Lines inside such a block are skipped.
      int swBlockDepth = 0;
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        final String bare = line.replaceAll(literal, '""');
        if (swBlockDepth == 0 && RegExp(r"""['"]sw['"]\s*:\s*\{""").hasMatch(line)) {
          swBlockDepth = 1;
          continue;
        }
        if (swBlockDepth > 0) {
          swBlockDepth += '{'.allMatches(bare).length - '}'.allMatches(bare).length;
          continue;
        }
        for (final RegExpMatch m in literal.allMatches(line)) {
          final String text = (m.group(1) ?? m.group(2) ?? '');
          if (allowed.containsKey(text)) {
            continue;
          }
          final Iterable<String> words = RegExp(r"[a-z]+").allMatches(text.toLowerCase()).map((RegExpMatch w) => w.group(0)!);
          final bool hasSwahili = words.any((String w) => swahili.contains(w) || vocabulary.contains(w));
          if (!hasSwahili) {
            continue;
          }
          // import paths, keys and so on contain no spaces and no capitals
          if (!text.contains(' ') && text == text.toLowerCase()) {
            continue;
          }
          // the name of a file that is saved or shared (no spaces, a path or an extension in it)
          if (text.endsWith('.pdf') || text.endsWith('.csv')) {
            continue;
          }
          if (!text.contains(' ') && RegExp(r'[/.\-]').hasMatch(text)) {
            continue;
          }
          final String around = lines.sublist(i >= 3 ? i - 3 : 0, i + 1).join('\n');
          if (chosenByLanguage.hasMatch(around)) {
            continue;
          }
          found.add('${file.path.replaceAll('\\', '/')}:${i + 1}  "$text"');
        }
      }
    }
    expect(found, isEmpty, reason: 'Swahili text written straight into the code (use a translation key):\n${found.join('\n')}');
  });
}
