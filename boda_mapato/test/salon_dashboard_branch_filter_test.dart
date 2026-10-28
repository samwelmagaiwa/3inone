import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/dashboard/inventory_dashboard_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The dashboard's period sheet also chooses a branch (a salon with branches): what is chosen is what every request carries
/// afterwards, the sales are fetched again, and "all branches" puts it back.
class _Auth extends AuthProvider {
  @override
  UserData? get user => UserData(id: '1', name: 'Owner', email: 'o@example.test', role: 'admin', isActive: true, permissions: const <String>['inv_view_products', 'inv_view_reports', 'inv_create_sales']);
}

class _Inv extends InventoryProvider {
  int salesFetches = 0;
  final List<int?> branchAtFetch = <int?>[];

  @override
  Future<void> fetchSales({String? status, DateTime? from, DateTime? to, String? q}) async {
    salesFetches++;
    branchAtFetch.add(ApiService.activeBranch);
  }

  @override
  Future<void> fetchKpis() async {}
}

class _Salon extends SalonApi {
  _Salon(this.rows, {this.fail = false});

  final List<SalonBranchInfo> rows;
  final bool fail;

  @override
  Future<List<SalonBranchInfo>> branches() async {
    if (fail) throw Exception('offline');

    return rows;
  }

  @override
  Future<SalonOverview> overview() async => throw Exception('not needed here');
}

Future<_Inv> _open(WidgetTester t, SalonApi salon, {bool salonMode = true}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  addTearDown(() {
    ApiService.activeBranch = null;
    ApiService.activeBranchName = null;
    ApiService.activeService = null;
  });
  t.view.physicalSize = const Size(411, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Inv inv = _Inv()..setSalonMode(salonMode);
  await t.pumpWidget(
    MultiProvider(
      providers: <SingleChildWidget>[
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider()),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(designSize: const Size(390, 844), minTextAdapt: true, builder: (_, __) => MaterialApp(home: Scaffold(body: InventoryDashboardScreen(salonApi: salon)))),
    ),
  );
  await t.pump(const Duration(seconds: 2));

  return inv;
}

Future<void> _openSheet(WidgetTester t) async {
  await t.tap(find.text('Filter'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  final List<SalonBranchInfo> two = <SalonBranchInfo>[
    const SalonBranchInfo(id: 1, name: 'Kariakoo'),
    const SalonBranchInfo(id: 2, name: 'Mikocheni'),
    const SalonBranchInfo(id: 3, name: 'Old shop', active: false),
  ];

  testWidgets('the sheet lists the active branches and choosing one sets it for every request and reloads', (t) async {
    final _Inv inv = await _open(t, _Salon(two));
    final int before = inv.salesFetches;
    await _openSheet(t);
    expect(find.text('Branch'), findsOneWidget);
    expect(find.byKey(const Key('filter_branch_all')), findsOneWidget);
    expect(find.text('Kariakoo'), findsOneWidget);
    expect(find.text('Mikocheni'), findsOneWidget);
    expect(find.text('Old shop'), findsNothing, reason: 'a branch that is switched off is not offered');

    await t.tap(find.byKey(const Key('filter_branch_2')));
    await t.pump();
    await t.tap(find.text('Apply'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(ApiService.activeBranch, 2);
    expect(ApiService.activeBranchName, 'Mikocheni');
    expect(inv.salesFetches, greaterThan(before), reason: 'the sales are fetched again');
    expect(inv.branchAtFetch.last, 2, reason: 'with the branch already set');
  });

  testWidgets('"All branches" puts it back, and applying the same choice does not reload for nothing', (t) async {
    final _Inv inv = await _open(t, _Salon(two));
    // chosen once the salon is open (opening a service forgets any branch of the one before)
    ApiService.chooseBranch(1, 'Kariakoo', service: 'salon');
    final int before = inv.salesFetches;

    await _openSheet(t);
    await t.tap(find.text('Apply'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(ApiService.activeBranch, 1, reason: 'unchanged');
    expect(inv.salesFetches, before, reason: 'nothing changed, nothing reloaded');

    await _openSheet(t);
    await t.tap(find.byKey(const Key('filter_branch_all')));
    await t.pump();
    await t.tap(find.text('Apply'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(ApiService.activeBranch, isNull);
    expect(ApiService.activeBranchName, isNull);
    expect(inv.salesFetches, greaterThan(before));
  });

  testWidgets('a salon with no branches, a failed list, or a shop has no branch choice', (t) async {
    await _open(t, _Salon(<SalonBranchInfo>[]));
    await _openSheet(t);
    expect(find.byKey(const Key('filter_branch_all')), findsNothing);
    expect(find.byKey(const Key('filter_no_branches')), findsOneWidget, reason: 'told there are none and where to add them');
    expect(find.text('Choose Period'), findsOneWidget, reason: 'the period choice is as it was');
  });

  testWidgets('if the list of branches cannot be had the sheet still opens for the period', (t) async {
    await _open(t, _Salon(two, fail: true));
    await _openSheet(t);
    expect(find.text('Choose Period'), findsOneWidget);
    expect(find.byKey(const Key('filter_branch_all')), findsNothing);
    expect(find.byKey(const Key('filter_no_branches')), findsNothing, reason: 'a failed list does not claim there are none');
  });

  testWidgets('a shop with branches can look at one branch too', (t) async {
    await _open(t, _Salon(two), salonMode: false);
    await _openSheet(t);
    expect(find.text('Choose Period'), findsOneWidget);
    expect(find.byKey(const Key('filter_branch_all')), findsOneWidget);
  });

  testWidgets('a shop with no branches is not asked to choose one', (t) async {
    await _open(t, _Salon(const <SalonBranchInfo>[]), salonMode: false);
    await _openSheet(t);
    expect(find.text('Choose Period'), findsOneWidget);
    expect(find.byKey(const Key('filter_branch_all')), findsNothing);
    expect(find.byKey(const Key('filter_no_branches')), findsOneWidget);
  });
}
