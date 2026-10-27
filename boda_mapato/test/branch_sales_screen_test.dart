import 'package:boda_mapato/modules/inventory/screens/salon/branch_sales_screen.dart';
import 'package:boda_mapato/modules/inventory/services/branch_team_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sales by branch and person, and placing people in branches.
class _FakeTeam extends BranchTeamApi {
  _FakeTeam({this.canPlace = true, this.profit = true});

  final bool canPlace;
  final bool profit;
  final List<(String, int?)> placed = <(String, int?)>[];
  final List<(DateTime, DateTime)> asked = <(DateTime, DateTime)>[];

  Map<String, dynamic> _cell(num sales) => <String, dynamic>{'sales_count': 2, 'sales': sales, 'paid': sales, 'profit': profit ? sales / 2 : null};

  @override
  Future<Map<String, dynamic>> sales(final DateTime from, final DateTime to) async {
    asked.add((from, to));

    return <String, dynamic>{
      'total': <String, dynamic>{'sales_count': 2, 'sales': 3000000, 'paid': 3000000},
      'by_branch': <Map<String, dynamic>>[
        <String, dynamic>{'branch_id': 1, 'name': 'Kariakoo', ..._cell(3000000), 'staff': <Map<String, dynamic>>[<String, dynamic>{'staff_id': 'u1', 'name': 'Asha', ..._cell(3000000)}]},
      ],
      'by_staff': <Map<String, dynamic>>[
        <String, dynamic>{'staff_id': 'u1', 'name': 'Asha', ..._cell(3000000), 'branches': <Map<String, dynamic>>[<String, dynamic>{'branch_id': 1, 'name': 'Kariakoo', ..._cell(3000000)}]},
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> team() async {
    if (!canPlace) throw Exception('403');

    return <Map<String, dynamic>>[<String, dynamic>{'staff_id': 'u1', 'name': 'Asha', 'branch_id': null}];
  }

  @override
  Future<List<Map<String, dynamic>>> branches() async => <Map<String, dynamic>>[<String, dynamic>{'id': 1, 'name': 'Kariakoo', 'active': true}];

  @override
  Future<void> assign(final String staffId, final int? branchId) async => placed.add((staffId, branchId));
}

Future<void> _open(WidgetTester t, _FakeTeam api) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: MaterialApp(home: BranchSalesScreen(api: api, today: DateTime(2026, 11, 25))),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('shows the total, each branch with its people and each person with their branches, with profit', (WidgetTester t) async {
    final _FakeTeam api = _FakeTeam();
    await _open(t, api);

    expect(find.text('TSh 3,000,000'), findsWidgets);
    expect(find.byKey(const Key('branch_1')), findsOneWidget);
    expect(find.byKey(const Key('staff_u1')), findsOneWidget);
    expect(find.textContaining('profit TSh 1,500,000'), findsWidgets);
    expect(api.asked.single.$1, DateTime(2026, 11, 1), reason: 'starts on this month');
  });

  testWidgets('leaves the profit out when the server does not send it, and asks again for another period', (WidgetTester t) async {
    final _FakeTeam api = _FakeTeam(profit: false);
    await _open(t, api);

    expect(find.textContaining('profit'), findsNothing);
    await t.tap(find.byKey(const Key('period_week')));
    await t.pumpAndSettle();
    expect(api.asked.length, 2);
    expect(api.asked.last.$1, DateTime(2026, 11, 23), reason: 'the Monday of that week');
  });

  testWidgets('the owner places a person in a branch from the People tab', (WidgetTester t) async {
    final _FakeTeam api = _FakeTeam();
    await _open(t, api);

    await t.tap(find.text('People'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('place_u1')));
    await t.pumpAndSettle();
    await t.tap(find.text('Kariakoo').last);
    await t.pumpAndSettle();

    expect(api.placed, <(String, int?)>[('u1', 1)]);
  });

  testWidgets('someone the server does not let place people sees only the sales', (WidgetTester t) async {
    await _open(t, _FakeTeam(canPlace: false));

    expect(find.text('People'), findsNothing);
    expect(find.byKey(const Key('branch_1')), findsOneWidget);
  });
}
