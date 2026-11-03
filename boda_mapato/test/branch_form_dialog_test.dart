import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/branch_form_dialog.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_places.dart';

/// The branch popup: the name, the whole place (chosen from the locations or typed), the address and a phone. A new branch needs all four
/// parts of the place; a branch being changed keeps its place unless a new one is chosen.
Future<void> _show(WidgetTester t, {SalonBranchInfo? branch, bool sw = false, required List<BranchForm?> out}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (BuildContext c) => Scaffold(
              body: ElevatedButton(
                key: const Key('open'),
                onPressed: () async => out.add(await showDialog<BranchForm>(context: c, builder: (_) => BranchFormDialog(branch: branch, placeSource: const NoPlaces()))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byKey(const Key('open')));
  await t.pumpAndSettle();
}

Future<void> _place(WidgetTester t, {List<String> parts = const <String>['Mwanza', 'Nyamagana', 'Pasiansi', 'Isamilo']}) async {
  for (int i = 0; i < parts.length; i++) {
    await t.enterText(find.byKey(ValueKey<String>('place_text_$i')), parts[i]);
    await t.pumpAndSettle();
  }
}

void main() {
  const SalonBranchInfo existing = SalonBranchInfo(id: 4, name: 'Kariakoo', address: 'Karibu na soko', phone: '0711000111', region: 'Dar es Salaam', district: 'Ilala', ward: 'Kariakoo', street: 'Msimbazi');

  testWidgets('a new branch is returned with its whole place, address and phone', (t) async {
    final List<BranchForm?> out = <BranchForm?>[];
    await _show(t, out: out);

    await t.enterText(find.byKey(const Key('branch_name')), '  Pasiansi  ');
    await _place(t);
    await t.enterText(find.byKey(const Key('branch_address')), 'Jengo la bluu');
    await t.enterText(find.byKey(const Key('branch_phone')), '0755000333');
    await t.tap(find.byKey(const Key('branch_save')));
    await t.pumpAndSettle();

    final BranchForm f = out.single!;
    expect([f.name, f.region, f.district, f.ward, f.street, f.address, f.phone], ['Pasiansi', 'Mwanza', 'Nyamagana', 'Pasiansi', 'Isamilo', 'Jengo la bluu', '0755000333']);
  });

  testWidgets('a short name or a missing part of the place is refused with its message', (t) async {
    final List<BranchForm?> out = <BranchForm?>[];
    await _show(t, out: out);

    await t.enterText(find.byKey(const Key('branch_name')), 'A');
    await _place(t, parts: const <String>['Mwanza', 'Nyamagana', 'Pasiansi']);
    await t.tap(find.byKey(const Key('branch_save')));
    await t.pumpAndSettle();

    expect(find.text('Write the branch name.'), findsOneWidget);
    expect(find.text('Choose or type the region, district, ward and street or village: all four.'), findsOneWidget);
    expect(out, isEmpty, reason: 'the popup stays open');
  });

  testWidgets('in Swahili the messages are Swahili', (t) async {
    await _show(t, sw: true, out: <BranchForm?>[]);

    await t.tap(find.byKey(const Key('branch_save')));
    await t.pumpAndSettle();

    expect(find.text('Andika jina la tawi.'), findsOneWidget);
    expect(find.text('Chagua au andika mkoa, wilaya, kata na mtaa/kijiji vyote.'), findsOneWidget);
    expect(find.text('Tawi jipya'), findsOneWidget);
  });

  testWidgets('changing a branch shows its present place and keeps it when no new one is chosen', (t) async {
    final List<BranchForm?> out = <BranchForm?>[];
    await _show(t, branch: existing, out: out);

    expect(t.widget<Text>(find.byKey(const Key('branch_current_place'))).data, 'Now: Msimbazi, Kariakoo, Ilala, Dar es Salaam. Choose a new place to change it.');
    expect(t.widget<TextField>(find.byKey(const Key('branch_name'))).controller!.text, 'Kariakoo');
    expect(t.widget<TextField>(find.byKey(const Key('branch_address'))).controller!.text, 'Karibu na soko');

    await t.enterText(find.byKey(const Key('branch_name')), 'Kariakoo Mpya');
    await t.tap(find.byKey(const Key('branch_save')));
    await t.pumpAndSettle();

    final BranchForm f = out.single!;
    expect(f.name, 'Kariakoo Mpya');
    expect([f.region, f.district, f.ward, f.street], [null, null, null, null], reason: 'an untouched place is not sent, so the server keeps it');
  });

  testWidgets('starting a new place for an existing branch needs all four parts, and then replaces it', (t) async {
    final List<BranchForm?> out = <BranchForm?>[];
    await _show(t, branch: existing, out: out);

    await _place(t, parts: const <String>['Arusha']);
    await t.tap(find.byKey(const Key('branch_save')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('branch_place_error')), findsOneWidget);
    expect(out, isEmpty);

    await _place(t, parts: const <String>['Arusha', 'Arusha Mjini', 'Sekei', 'Sekei Kati']);
    await t.tap(find.byKey(const Key('branch_save')));
    await t.pumpAndSettle();

    final BranchForm f = out.single!;
    expect([f.region, f.district, f.ward, f.street], ['Arusha', 'Arusha Mjini', 'Sekei', 'Sekei Kati']);
  });

  testWidgets('Cancel returns nothing', (t) async {
    final List<BranchForm?> out = <BranchForm?>[];
    await _show(t, out: out);

    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(out, <BranchForm?>[null]);
  });
}
