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

/// Set by the salon home around the page it shows: that page already sits under the home's own title bar, so it must not
/// draw a second one.
class SalonEmbedded extends InheritedWidget {
  const SalonEmbedded({super.key, required super.child});

  static bool of(final BuildContext context) => context.dependOnInheritedWidgetOfExactType<SalonEmbedded>() != null;

  @override
  bool updateShouldNotify(final SalonEmbedded oldWidget) => false;
}

/// The page's own title bar, or none when the home already shows one.
PreferredSizeWidget? salonAppBar(final BuildContext context, final String title, {final List<Widget>? actions}) =>
    SalonEmbedded.of(context) ? null : AppBar(title: Text(title), actions: actions);
