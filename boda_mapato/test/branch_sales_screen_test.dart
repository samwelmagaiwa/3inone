import 'package:boda_mapato/modules/inventory/screens/salon/branch_sales_screen.dart';
import 'package:boda_mapato/widgets/place_picker.dart';
import 'support/fake_places.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/salon_input.dart';
import 'package:boda_mapato/modules/inventory/services/branch_team_api.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sales by branch and person, and placing people in branches.
class _FakeTeam extends BranchTeamApi {
  _FakeTeam({this.canPlace = true, this.profit = true}) : branchRows = <Map<String, dynamic>>[<String, dynamic>{'id': 1, 'name': 'Kariakoo', 'active': true}];

  final bool canPlace;
  final bool profit;
  final List<(String, int?)> placed = <(String, int?)>[];
  final List<Map<String, String>> added = <Map<String, String>>[];
  Object? failAdd;
  List<Map<String, dynamic>> branchRows;
  int branchReads = 0;
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
  Future<List<Map<String, dynamic>>> branches() async {
    branchReads++;

    return branchRows;
  }

  @override
  Future<void> addBranch({required String name, required String region, required String district, required String ward, required String street, String address = '', String phone = ''}) async {
    if (failAdd != null) throw failAdd!;
    added.add(<String, String>{'name': name, 'region': region, 'district': district, 'ward': ward, 'street': street, 'address': address, 'phone': phone});
    branchRows = <Map<String, dynamic>>[...branchRows, <String, dynamic>{'id': 9, 'name': name, 'active': true}];
  }

  @override
  Future<void> assign(final String staffId, final int? branchId) async => placed.add((staffId, branchId));
}

Future<void> _open(WidgetTester t, _FakeTeam api, {PlaceSource? places}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => MaterialApp(home: BranchSalesScreen(api: api, today: DateTime(2026, 11, 25), placeSource: places ?? const NoPlaces()))),
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

  testWidgets('on its own the page has its title; inside the home there is no second title, only the tabs', (WidgetTester t) async {
    await _open(t, _FakeTeam());
    expect(find.text('Sales by branch and person'), findsOneWidget, reason: 'its own title bar');

    SharedPreferences.setMockInitialValues(<String, Object>{});
    await t.pumpWidget(
      ChangeNotifierProvider<LocalizationService>.value(
        value: LocalizationService.instance,
        child: MaterialApp(home: SalonEmbedded(child: BranchSalesScreen(api: _FakeTeam(), today: DateTime(2026, 11, 25)))),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('Sales by branch and person'), findsNothing, reason: 'the home already shows the title');
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.byKey(const Key('bs_total')), findsOneWidget);
  });

  testWidgets('the sales figures are one card, each part divided from the next by the glowing line', (WidgetTester t) async {
    await _open(t, _FakeTeam());

    // total | "By branch" | Kariakoo with its people | "By person" | Asha with her branches
    for (int i = 1; i <= 4; i++) {
      expect(find.byKey(ValueKey<String>('sales_divider_$i')), findsOneWidget, reason: 'line $i');
    }
    expect(find.byKey(const ValueKey<String>('sales_divider_5')), findsNothing);
  });

  testWidgets('the people are one card too, a line between each person', (WidgetTester t) async {
    await _open(t, _FakeTeam());

    await t.tap(find.text('People'));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('place_u1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('people_divider_1')), findsNothing, reason: 'one person: no line to draw');
  });

  group('adding a branch from the People tab', () {
    Future<void> toPeople(WidgetTester t, _FakeTeam api, {PlaceSource? places}) async {
      t.view.physicalSize = const Size(800, 3000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await _open(t, api, places: places);
      await t.tap(find.text('People'));
      await t.pumpAndSettle();
    }

    Future<void> fillByHand(WidgetTester t, {String name = 'Mbezi'}) async {
      await t.tap(find.byKey(const Key('people_add_branch')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('branch_name')), name);
      for (final (int i, String v) in <(int, String)>[(0, 'Dar es Salaam'), (1, 'Kinondoni'), (2, 'Mbezi'), (3, 'Mbezi Beach')]) {
        await t.enterText(find.byKey(ValueKey<String>('place_text_$i')), v);
        await t.pumpAndSettle();
      }
      await t.enterText(find.byKey(const Key('branch_address')), 'Karibu na kanisa');
      await t.enterText(find.byKey(const Key('branch_phone')), '0711000222');
    }

    testWidgets('there is an Add branch button, and with no branch yet it says to add one first', (WidgetTester t) async {
      final _FakeTeam api = _FakeTeam()..branchRows = <Map<String, dynamic>>[];
      await toPeople(t, api);

      expect(find.byKey(const Key('people_add_branch')), findsOneWidget);
      expect(find.byKey(const Key('bp_nobranches')), findsOneWidget);
    });

    testWidgets('the popup makes the branch with the whole place, then the list is read again and the branch can be chosen for people', (WidgetTester t) async {
      final _FakeTeam api = _FakeTeam()..branchRows = <Map<String, dynamic>>[];
      await toPeople(t, api);
      final int readsBefore = api.branchReads;

      await fillByHand(t);
      await t.tap(find.byKey(const Key('branch_save')));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 6));

      expect(api.added.single, <String, String>{'name': 'Mbezi', 'region': 'Dar es Salaam', 'district': 'Kinondoni', 'ward': 'Mbezi', 'street': 'Mbezi Beach', 'address': 'Karibu na kanisa', 'phone': '0711000222'});
      expect(api.branchReads, greaterThan(readsBefore), reason: 'the new branch is read back');
      expect(find.byKey(const Key('bp_nobranches')), findsNothing, reason: 'there is a branch now');
    });

    testWidgets('chosen from the lists: region, district, ward and street or village', (WidgetTester t) async {
      final _FakeTeam api = _FakeTeam();
      await toPeople(t, api, places: FakePlaces());

      await t.tap(find.byKey(const Key('people_add_branch')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('branch_name')), 'Mikocheni');
      // each level opens its list (from the imported locations) and the choice is kept
      for (final (int i, String v) in <(int, String)>[(0, 'Dar es Salaam'), (1, 'Kinondoni'), (2, 'Mikocheni'), (3, 'Mikocheni A')]) {
        await t.ensureVisible(find.byKey(ValueKey<String>('place_select_$i')));
        await t.tap(find.byKey(ValueKey<String>('place_select_$i')));
        await t.pumpAndSettle();
        await t.tap(find.text(v).last);
        await t.pumpAndSettle();
      }
      await t.tap(find.byKey(const Key('branch_save')));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 6));

      expect([api.added.single['region'], api.added.single['district'], api.added.single['ward'], api.added.single['street']], ['Dar es Salaam', 'Kinondoni', 'Mikocheni', 'Mikocheni A']);
    });

    testWidgets('without the place, or without the name, nothing is sent', (WidgetTester t) async {
      final _FakeTeam api = _FakeTeam();
      await toPeople(t, api);

      await t.tap(find.byKey(const Key('people_add_branch')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('branch_save')));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('branch_place_error')), findsOneWidget);
      expect(api.added, isEmpty);
    });

    testWidgets('Cancel closes the popup and sends nothing', (WidgetTester t) async {
      final _FakeTeam api = _FakeTeam();
      await toPeople(t, api);
      await fillByHand(t);

      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('branch_name')), findsNothing);
      expect(api.added, isEmpty);
    });

    testWidgets('a branch with that name already there shows the server words and keeps the page', (WidgetTester t) async {
      final _FakeTeam api = _FakeTeam()..failAdd = Exception('Tawi hili lipo tayari. / That branch already exists.');
      await toPeople(t, api);
      await fillByHand(t, name: 'Kariakoo');

      await t.tap(find.byKey(const Key('branch_save')));
      await t.pumpAndSettle();

      expect(find.textContaining('already exists'), findsWidgets);
      expect(find.byKey(const Key('people_add_branch')), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
    });
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
