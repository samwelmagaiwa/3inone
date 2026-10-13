// Smoke tests: the whole app starts, signed out, and shows the way in.

import "package:boda_mapato/main.dart";
import "package:boda_mapato/services/localization_service.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Starts the app the way a fresh install does: nothing stored, nobody signed in, on a
/// phone-sized screen (the layout is designed for one).
Future<void> _boot(final WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const BodaMapatoApp());

  // pump(), not pumpAndSettle(): the landing screen's background animates for ever,
  // so the tree never settles.
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets("a fresh install opens on the landing screen, with a way to sign in or register",
      (final WidgetTester tester) async {
    await _boot(tester);

    expect(find.byType(MaterialApp), findsOneWidget);
    // Swahili is the default language.
    expect(find.text("Ingia"), findsOneWidget);
    expect(find.text("Jisajili"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("the buttons over the landing slides are plain text, not Flutter's yellow 'no Material' underline",
      (final WidgetTester tester) async {
    await _boot(tester);

    // What the text really draws with: the nearest DefaultTextStyle plus the widget's own style. With no
    // Material above them (the overlay sits on a bare Stack) MaterialApp's fallback style applies, which
    // is a yellow double underline in a monospace font.
    for (final String label in <String>["Ingia", "Jisajili", "SW"]) {
      final Finder f = find.text(label);
      expect(f, findsOneWidget, reason: label);
      final Text text = tester.widget<Text>(f);
      final TextStyle effective = DefaultTextStyle.of(tester.element(f)).style.merge(text.style);
      expect(
        effective.decoration == null || effective.decoration == TextDecoration.none,
        isTrue,
        reason: "\"$label\" is underlined: ${effective.decoration} (${effective.decorationColor})",
      );
    }
  });

  testWidgets("the app carries its own name as the title",
      (final WidgetTester tester) async {
    await _boot(tester);

    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    expect(app.title, equals(LocalizationService.instance.translate("app_name")));
    expect(app.title, isNotEmpty);
  });
}
