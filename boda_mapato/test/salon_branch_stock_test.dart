import 'package:boda_mapato/modules/inventory/screens/salon/branch_stock_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSalon extends SalonApi {
  bool noBranches = false;
  Object? failMove;
  final List<Map<String, dynamic>> moves = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> branchStock() async => <String, dynamic>{
        'branches': noBranches ? <dynamic>[] : <Map<String, dynamic>>[<String, dynamic>{'id': 1, 'name': 'Kariakoo'}, <String, dynamic>{'id': 2, 'name': 'Mikocheni'}],
        'products': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 7, 'name': 'Shampoo', 'total': 10, 'unallocated': 4, 'over_allocated': false,
            'branches': <Map<String, dynamic>>[<String, dynamic>{'branch_id': 1, 'name': 'Kariakoo', 'quantity': 4}, <String, dynamic>{'branch_id': 2, 'name': 'Mikocheni', 'quantity': 2}],
          },
          <String, dynamic>{'id': 8, 'name': 'Dye', 'total': 1, 'unallocated': 0, 'over_allocated': true, 'branches': <Map<String, dynamic>>[]},
        ],
      };

  @override
  Future<void> transferBranchStock({required int productId, int? fromBranchId, int? toBranchId, required int quantity}) async {
    if (failMove != null) throw failMove!;
    moves.add(<String, dynamic>{'product': productId, 'from': fromBranchId, 'to': toBranchId, 'qty': quantity});
  }
}

Future<void> _pump(WidgetTester t, _FakeSalon api, {bool canMove = true}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance, child: MaterialApp(home: BranchStockScreen(api: api, canMove: canMove))));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('shows the whole stock, the main store and each branch, and flags more allocated than held', (t) async {
    await _pump(t, _FakeSalon());
    expect(find.text('Shampoo  ·  10'), findsOneWidget);
    expect(find.textContaining('Main store 4 · Kariakoo 4 · Mikocheni 2'), findsOneWidget);
    expect(find.textContaining('recount'), findsOneWidget);
  });

  testWidgets('moves goods from the main store to a branch', (t) async {
    final _FakeSalon api = _FakeSalon();
    await _pump(t, api);
    await t.tap(find.byKey(const Key('bs_move_7')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('bs_qty')), '3');
    await t.tap(find.byKey(const Key('bs_save')));
    await t.pumpAndSettle();
    expect(api.moves.single, <String, dynamic>{'product': 7, 'from': null, 'to': 1, 'qty': 3});
  });

  testWidgets('the same place twice or no quantity is refused before anything is sent', (t) async {
    final _FakeSalon api = _FakeSalon();
    await _pump(t, api);
    await t.tap(find.byKey(const Key('bs_move_7')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('bs_save')));
    await t.pump();
    expect(find.text('Enter a quantity.'), findsOneWidget);

    // From and To both the main store.
    await t.tap(find.byKey(const Key('bs_to')));
    await t.pumpAndSettle();
    await t.tap(find.text('Main store').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('bs_qty')), '1');
    await t.tap(find.byKey(const Key('bs_save')));
    await t.pump();
    expect(find.text('Choose a different place.'), findsOneWidget);
    expect(api.moves, isEmpty);
  });

  testWidgets('a refused move shows the server words', (t) async {
    final _FakeSalon api = _FakeSalon()..failMove = Exception('Hakuna bidhaa za kutosha mahali hapo');
    await _pump(t, api);
    await t.tap(find.byKey(const Key('bs_move_7')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('bs_qty')), '99');
    await t.tap(find.byKey(const Key('bs_save')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Hakuna bidhaa za kutosha'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('someone who may not move goods does not see the move button', (t) async {
    await _pump(t, _FakeSalon(), canMove: false);
    expect(find.byKey(const Key('bs_move_7')), findsNothing);
  });

  testWidgets('with no branches it says to add one and offers no move', (t) async {
    await _pump(t, _FakeSalon()..noBranches = true);
    expect(find.byKey(const Key('bs_no_branches')), findsOneWidget);
    expect(find.byKey(const Key('bs_move_7')), findsNothing);
  });
}
