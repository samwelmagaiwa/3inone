import 'package:flutter/material.dart';

import '../../../../constants/theme_constants.dart';

/// The look of a text box in the salon screens (the inventory's own: a soft dark fill, a light border, light text). The
/// plain Material box is white, which made light text unreadable inside the dark dialogs. Fixed sizes (no screen scaling),
/// so it also works inside dialogs and in tests.
InputDecoration salonInput({required final String labelText, final String? counterText, final String? hintText}) {
  OutlineInputBorder border(final Color c, [final double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));

  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    counterText: counterText,
    labelStyle: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
    hintStyle: const TextStyle(color: ThemeConstants.textSecondary, fontSize: 12),
    filled: true,
    fillColor: ThemeConstants.invFill,
    border: border(ThemeConstants.invBorder),
    enabledBorder: border(ThemeConstants.invBorder),
    focusedBorder: border(ThemeConstants.invAccent, 1.4),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

/// The text style typed into a salon text box (light, readable on the dark fill).
const TextStyle salonInputStyle = TextStyle(color: ThemeConstants.textPrimary, fontSize: 14);
