import 'dart:io';

import 'package:boda_mapato/constants/theme_constants.dart';
import 'package:flutter_test/flutter_test.dart';

/// Red TEXT on the dark cards of the salon screens must be the light red (errorText): the plain red (errorRed, Colors.red) is too dim to
/// read there. errorRed stays for badges, icons, buttons and backgrounds.
void main() {
  test('the light red is a lighter colour than the plain one', () {
    double light(final int rgb) => (((rgb >> 16) & 0xFF) * 0.299 + ((rgb >> 8) & 0xFF) * 0.587 + (rgb & 0xFF) * 0.114) / 255;

    expect(light(ThemeConstants.errorText.toARGB32()), greaterThan(light(ThemeConstants.errorRed.toARGB32()) + 0.15));
  });

  test('no salon screen draws text in the plain red', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity f in Directory('lib/modules/inventory/screens/salon').listSync()) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final List<String> lines = f.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String l = lines[i];
        final bool plainRed = (l.contains('ThemeConstants.errorRed') || l.contains('Colors.red')) && !l.contains('backgroundColor');
        final bool isText = l.contains('TextStyle(') || l.contains('captionStyle.copyWith(') || l.contains('bodyStyle.copyWith(');
        // a TextStyle that only reads "color: ... errorRed" for a badge/icon/background is not text
        if (plainRed && isText) offenders.add('${f.path.split(RegExp(r'[\\/]')).last}:${i + 1}');
      }
    }

    expect(offenders, isEmpty, reason: 'use ThemeConstants.errorText for red text: $offenders');
  });
}
