import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The English and the Swahili translations must describe the same keys, or a screen shows a raw key name
/// (or silently falls back to the other language) when the language is switched.
void main() {
  final String source = File('lib/services/localization_service.dart').readAsStringSync();
  final int swStart = source.indexOf("    'sw': {");
  final int enStart = source.indexOf("    'en': {");
  final int end = source.indexOf('\n  };', swStart);

  // A key is the quoted word that starts a line six spaces in; its value may continue over several lines.
  final RegExp keyLine = RegExp(r"^ {6}'([A-Za-z0-9_]+)':\s*(.*)$", multiLine: true);

  Map<String, List<String>> readKeys(String part) {
    final Map<String, List<String>> keys = <String, List<String>>{};
    for (final RegExpMatch m in keyLine.allMatches(part)) {
      keys.putIfAbsent(m.group(1)!, () => <String>[]).add(m.group(2)!);
    }
    return keys;
  }

  final Map<String, List<String>> en = readKeys(source.substring(enStart, swStart));
  final Map<String, List<String>> sw = readKeys(source.substring(swStart, end));

  test('the two languages were found', () {
    expect(enStart, greaterThan(0));
    expect(swStart, greaterThan(enStart));
    expect(en.length, greaterThan(500));
    expect(sw.length, greaterThan(500));
  });

  test('no key is written twice in the same language', () {
    final List<String> twice = <String>[
      for (final MapEntry<String, List<String>> e in en.entries)
        if (e.value.length > 1) 'en:${e.key}',
      for (final MapEntry<String, List<String>> e in sw.entries)
        if (e.value.length > 1) 'sw:${e.key}',
    ];
    expect(twice, isEmpty, reason: 'duplicate keys: ${twice.join(', ')}');
  });

  test('English and Swahili have exactly the same keys', () {
    final List<String> onlyEn = en.keys.where((String k) => !sw.containsKey(k)).toList()..sort();
    final List<String> onlySw = sw.keys.where((String k) => !en.containsKey(k)).toList()..sort();
    expect(onlyEn, isEmpty, reason: 'missing in Swahili: ${onlyEn.join(', ')}');
    expect(onlySw, isEmpty, reason: 'missing in English: ${onlySw.join(', ')}');
  });

  test('every key the code asks for has a translation in both languages', () {
    // translate('key'), translateWith('key', ...), translateForKind('key', ...)
    final RegExp call = RegExp(r"""(?:translate|translateWith|translateForKind)\(\s*['"]([A-Za-z0-9_]+)['"]""");
    final List<String> missing = <String>[];
    for (final FileSystemEntity f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart') || f.path.endsWith('localization_service.dart')) {
        continue;
      }
      final String code = f.readAsStringSync().replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
      for (final RegExpMatch m in call.allMatches(code)) {
        final String key = m.group(1)!;
        if (!en.containsKey(key) || !sw.containsKey(key)) {
          final int line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
          missing.add('$key  (${f.path.replaceAll('\\', '/')}:$line)');
        }
      }
    }
    expect(missing, isEmpty, reason: 'keys with no translation (the screen would show the key name):\n${missing.join('\n')}');
  });

  test('no translation is empty', () {
    final List<String> empty = <String>[
      for (final MapEntry<String, List<String>> e in en.entries)
        if (e.value.first.trim().startsWith("''") || e.value.first.trim().startsWith('""')) 'en:${e.key}',
      for (final MapEntry<String, List<String>> e in sw.entries)
        if (e.value.first.trim().startsWith("''") || e.value.first.trim().startsWith('""')) 'sw:${e.key}',
    ];
    expect(empty, isEmpty, reason: 'empty texts: ${empty.join(', ')}');
  });
}
