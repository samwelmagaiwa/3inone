import 'package:flutter/services.dart';

/// Lets a space stand only BETWEEN words: none at the start and never two in a row. (A typed space after a space, or first in the box, is
/// dropped.) Used by the SMS sender-name fields, where "MAMA ASHA" is a name but " MAMA  ASHA " is not.
class OneSpaceBetweenWords extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(final TextEditingValue oldValue, final TextEditingValue newValue) {
    final String collapsed = newValue.text.replaceAll(RegExp(r' {2,}'), ' ').replaceFirst(RegExp(r'^ +'), '');
    if (collapsed == newValue.text) return newValue;

    final int cursor = newValue.selection.baseOffset.clamp(0, newValue.text.length);
    // keep the cursor where it was among the characters that stay
    final int kept = newValue.text.substring(0, cursor).replaceAll(RegExp(r' {2,}'), ' ').replaceFirst(RegExp(r'^ +'), '').length;

    return TextEditingValue(text: collapsed, selection: TextSelection.collapsed(offset: kept.clamp(0, collapsed.length)));
  }
}
