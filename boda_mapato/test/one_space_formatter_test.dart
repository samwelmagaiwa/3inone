import 'package:boda_mapato/utils/one_space_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _v(String t, [int? cursor]) => TextEditingValue(text: t, selection: TextSelection.collapsed(offset: cursor ?? t.length));

void main() {
  final OneSpaceBetweenWords f = OneSpaceBetweenWords();

  test('a space between two words is kept', () {
    expect(f.formatEditUpdate(_v('MAMA'), _v('MAMA ')).text, 'MAMA ');
    expect(f.formatEditUpdate(_v('MAMA '), _v('MAMA A')).text, 'MAMA A');
    expect(f.formatEditUpdate(_v('MAMA A'), _v('MAMA ASHA')).text, 'MAMA ASHA');
  });

  test('never two spaces in a row, and none first', () {
    expect(f.formatEditUpdate(_v('MAMA '), _v('MAMA  ')).text, 'MAMA ');
    expect(f.formatEditUpdate(_v(''), _v(' ')).text, '');
    expect(f.formatEditUpdate(_v(''), _v('   MAMA')).text, 'MAMA');
  });

  test('the cursor stays among the letters when a space is dropped', () {
    final TextEditingValue out = f.formatEditUpdate(_v('MAMA ASHA', 5), _v('MAMA  ASHA', 6));
    expect(out.text, 'MAMA ASHA');
    expect(out.selection.baseOffset, 5);
  });
}
