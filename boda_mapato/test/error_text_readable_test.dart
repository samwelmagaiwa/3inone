import 'dart:io';

import 'package:boda_mapato/constants/theme_constants.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/inventory_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// Red TEXT on the dark cards of the salon screens must be the light red (errorText): the plain red (errorRed, Colors.red) is too dim to
/// read there. errorRed stays for badges, icons, buttons and backgrounds.
void main() {
  test('the light red is a lighter colour than the plain one', () {
    double light(final int rgb) => (((rgb >> 16) & 0xFF) * 0.299 + ((rgb >> 8) & 0xFF) * 0.587 + (rgb & 0xFF) * 0.114) / 255;

    expect(light(ThemeConstants.errorText.toARGB32()), greaterThan(light(ThemeConstants.errorRed.toARGB32()) + 0.15));
  });

  test('no inventory or salon screen draws text in the plain red', () {
    final List<String> offenders = <String>[];
    for (final FileSystemEntity f in Directory('lib/modules/inventory/screens').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart') || f.path.contains('barcode_scanner')) continue;
      final List<String> lines = f.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String l = lines[i];
        final bool plainRed = (l.contains('ThemeConstants.errorRed') || l.contains('Colors.red')) && !l.contains('backgroundColor') && !l.contains('borderSide') && !l.contains('Icon(');
        final bool isText = l.contains('TextStyle(') || l.contains('captionStyle.copyWith(') || l.contains('bodyStyle.copyWith(');
        // a TextStyle that only reads "color: ... errorRed" for a badge/icon/background is not text
        if (plainRed && isText) offenders.add('${f.path.split(RegExp(r'[\\/]')).last}:${i + 1}');
        // a colour chosen on a line of its own, right under a TextStyle( or copyWith( (text, not an icon or a background)
        if (plainRed && !isText && !l.contains('Icon') && !l.contains('errorText') && i >= 1) {
          final String above = lines.sublist(i < 3 ? 0 : i - 3, i).join(' ');
          final bool underText = above.contains('TextStyle(') || above.contains('.copyWith(');
          if (underText && !above.contains('Icon(') && !above.contains('BoxDecoration(') && !above.contains('styleFrom(')) {
            offenders.add('${f.path.split(RegExp(r'[\\/]')).last}:${i + 1}');
          }
        }
      }
    }

    expect(offenders, isEmpty, reason: 'use ThemeConstants.errorText for red text: $offenders');
  });

  testWidgets('a figure tile with the plain red as its colour shows its number in the readable red', (WidgetTester t) async {
    await t.pumpWidget(ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => const MaterialApp(home: Scaffold(body: InvStatTile(label: 'Loss', value: 'TSH 5,000', icon: Icons.trending_down, accent: ThemeConstants.errorRed)))));

    final Text number = t.widget<Text>(find.text('TSH 5,000'));
    expect(number.style?.color, ThemeConstants.errorText);
  });

  testWidgets('other colours of a figure tile are left as they are', (WidgetTester t) async {
    await t.pumpWidget(ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => const MaterialApp(home: Scaffold(body: InvStatTile(label: 'Profit', value: 'TSH 9,000', icon: Icons.trending_up, accent: ThemeConstants.successGreen)))));

    expect(t.widget<Text>(find.text('TSH 9,000')).style?.color, ThemeConstants.successGreen);
  });
}
