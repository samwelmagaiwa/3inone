import 'package:boda_mapato/constants/theme_constants.dart';
import 'package:boda_mapato/modules/groups/screens/widgets/groups_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(final Color a, final Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  test('every pill colour reads on the dark card (contrast at least 4.5:1), the red above all', () {
    const Color card = Color(0xFF2A5566);
    for (final Color c in <Color>[ThemeConstants.errorRed, ThemeConstants.warningAmber, ThemeConstants.successGreen, ThemeConstants.primaryOrange, ThemeConstants.invAccent]) {
      final Color fill = Color.alphaBlend(c.withValues(alpha: 0.24), card);
      expect(_contrast(GroupPill.readable(c), fill), greaterThanOrEqualTo(4.5), reason: 'colour ${c.toARGB32().toRadixString(16)}');
    }
  });
}
