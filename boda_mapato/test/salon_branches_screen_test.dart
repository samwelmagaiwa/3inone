import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/branches_screen.dart';
import 'package:boda_mapato/widgets/place_picker.dart';
import 'support/fake_places.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Branches: choose one and every request carries it; "all" clears it; a switched-off branch cannot be chosen; the
/// owner adds and switches off.
class _FakeSalon extends SalonApi {
  List<SalonBranchInfo> rows = const <SalonBranchInfo>[
    SalonBranchInfo(id: 1, name: 'Kariakoo', address: 'Mtaa wa Kongo'),
    SalonBranchInfo(id: 2, name: 'Mikocheni', active: false),
  ];
  final List<Map<String, dynamic>> saved = <Map<String, dynamic>>[];

  @override
  Future<List<SalonBranchInfo>> branches() async => rows;

  @override
  Future<void> saveBranch({int? id, required String name, String? address, String? phone, bool? active, String? region, String? district, String? ward, String? street}) async {
    saved.add(<String, dynamic>{'id': id, 'name': name, 'address': address, 'active': active, 'region': region, 'district': district, 'ward': ward, 'street': street, 'phone': phone});
  }
}

Future<void> _pump(WidgetTester t, SalonApi api, {bool manage = true, PlaceSource? places}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  addTearDown(() => ApiService.activeBranch = null);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance, child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => MaterialApp(home: BranchesScreen(api: api, manage: manage, placeSource: places ?? const NoPlaces())))),
  );
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('choosing a branch sets it for every request, all branches clears it', (WidgetTester t) async {
    await _pump(t, _FakeSalon());
    expect(find.text('Kariakoo'), findsOneWidget);
    expect(ApiService.activeBranch, isNull);

    await t.tap(find.byKey(const Key('branch_1')));
    await t.pump();
    expect(ApiService.activeBranch, 1);

    await t.tap(find.byKey(const Key('branch_all')));
    await t.pump();
    expect(ApiService.activeBranch, isNull);
  });

  testWidgets('the chosen branch name is remembered for the home header and forgotten on all', (WidgetTester t) async {
    await _pump(t, _FakeSalon());
    await t.tap(find.byKey(const Key('branch_1')));
    await t.pump();
    expect(ApiService.activeBranchName, 'Kariakoo');
    await t.tap(find.byKey(const Key('branch_all')));
    await t.pump();
    expect(ApiService.activeBranchName, isNull);
  });

  testWidgets('a switched-off branch cannot be chosen', (WidgetTester t) async {
    await _pump(t, _FakeSalon());
    await t.tap(find.byKey(const Key('branch_2')));
    await t.pump();
    expect(ApiService.activeBranch, isNull);
    expect(find.textContaining('Switched off'), findsOneWidget);
  });

  testWidgets('a chosen branch that was switched off since is dropped on load', (WidgetTester t) async {
    ApiService.activeBranch = 2;
    await _pump(t, _FakeSalon());
    expect(ApiService.activeBranch, isNull);
  });

  testWidgets('the owner adds a branch with its whole place, typed here because the lists are empty', (WidgetTester t) async {
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final _FakeSalon api = _FakeSalon();
    await _pump(t, api);
    await t.tap(find.byKey(const Key('branch_add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('branch_name')), 'Mbezi');
    for (final (int i, String v) in <(int, String)>[(0, 'Dar es Salaam'), (1, 'Kinondoni'), (2, 'Mbezi'), (3, 'Mbezi Beach')]) {
      expect(find.byKey(ValueKey<String>('place_text_$i')), findsOneWidget, reason: 'no list for any level, so every part is a box to type in');
      await t.enterText(find.byKey(ValueKey<String>('place_text_$i')), v);
      await t.pumpAndSettle();
    }
    await t.tap(find.byKey(const Key('branch_save')));
    await t.pumpAndSettle();

    expect(api.saved.single['name'], 'Mbezi');
    expect(api.saved.single['id'], isNull);
    expect([api.saved.single['region'], api.saved.single['district'], api.saved.single['ward'], api.saved.single['street']], ['Dar es Salaam', 'Kinondoni', 'Mbezi', 'Mbezi Beach']);
  });

  testWidgets('a branch cannot be saved without its place: the form says so and sends nothing', (WidgetTester t) async {
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final _FakeSalon api = _FakeSalon();
    await _pump(t, api);
    await t.tap(find.byKey(const Key('branch_add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('branch_name')), 'Mbezi');
    await t.tap(find.byKey(const Key('branch_save')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('branch_place_error')), findsOneWidget);
    expect(api.saved, isEmpty);
    expect(find.byKey(const Key('branch_name')), findsOneWidget, reason: 'the form stays open');
  });

  testWidgets('a branch with a place shows it on its line', (WidgetTester t) async {
    final _FakeSalon api = _FakeSalon()..rows = const <SalonBranchInfo>[SalonBranchInfo(id: 1, name: 'Kariakoo', address: 'Karibu na soko', region: 'Dar es Salaam', district: 'Ilala', ward: 'Kariakoo', street: 'Msimbazi')];
    await _pump(t, api);

    expect(find.text('Msimbazi, Kariakoo, Ilala, Dar es Salaam · Karibu na soko'), findsOneWidget);
  });

  testWidgets('someone who only chooses has no add button', (WidgetTester t) async {
    await _pump(t, _FakeSalon(), manage: false);
    expect(find.byKey(const Key('branch_add')), findsNothing);
    expect(find.byKey(const Key('branch_menu_1')), findsNothing);
  });
}
