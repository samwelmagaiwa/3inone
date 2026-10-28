import 'package:boda_mapato/modules/inventory/models/salon_models.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:boda_mapato/widgets/branch_filter_button.dart';
import 'package:boda_mapato/widgets/branch_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Branches for every service: the choice is remembered together with the service it was made in, never follows the person
/// into another service, and Transport / Rental get the same button and the same list as the shop and the salon.
class _Branches extends SalonApi {
  _Branches(this.rows);

  List<SalonBranchInfo> rows;

  @override
  Future<List<SalonBranchInfo>> branches() async => rows;
}

Future<void> _pump(WidgetTester t, Widget child) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  addTearDown(() {
    ApiService.clearBranch();
    ApiService.activeService = null;
  });
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance, child: MaterialApp(home: Scaffold(body: child))),
  );
  await t.pump();
  await t.pump();
}

void main() {
  const List<SalonBranchInfo> two = <SalonBranchInfo>[
    SalonBranchInfo(id: 1, name: 'Dodoma yard'),
    SalonBranchInfo(id: 2, name: 'Arusha yard'),
    SalonBranchInfo(id: 3, name: 'Closed yard', active: false),
  ];

  group('what the app remembers', () {
    test('a chosen branch comes with its service, and "all" forgets both', () {
      ApiService.chooseBranch(2, 'Arusha yard', service: 'transport');
      expect(ApiService.activeBranch, 2);
      expect(ApiService.activeBranchName, 'Arusha yard');
      expect(ApiService.activeBranchService, 'transport');

      ApiService.chooseBranch(null, 'ignored', service: 'transport');
      expect(ApiService.activeBranch, isNull);
      expect(ApiService.activeBranchName, isNull);
      expect(ApiService.activeBranchService, isNull);
    });

    test('opening the salon or going back to the shop forgets a branch of the other', () {
      final InventoryProvider inv = InventoryProvider();
      inv.setSalonMode(false);
      ApiService.chooseBranch(5, 'Shop branch', service: 'inventory');

      inv.setSalonMode(true);
      expect(ApiService.activeBranch, isNull, reason: 'a shop branch is not a salon branch');

      ApiService.chooseBranch(7, 'Salon branch', service: 'salon');
      inv.setSalonMode(false);
      expect(ApiService.activeBranch, isNull);
      ApiService.activeService = null;
    });
  });

  group('the Branch button on a dashboard', () {
    testWidgets('says "All branches" until one is chosen, then its name', (WidgetTester t) async {
      int changed = 0;
      await _pump(t, BranchFilterButton(service: 'transport', api: _Branches(two), onChanged: () => changed++));
      expect(find.text('Branch: All branches'), findsOneWidget);

      await t.tap(find.byKey(const Key('branch_filter_button')));
      await t.pumpAndSettle();
      expect(find.text('Dodoma yard'), findsOneWidget);
      expect(find.text('Arusha yard'), findsOneWidget);

      await t.tap(find.byKey(const Key('branch_2')));
      await t.pump();
      expect(ApiService.activeBranchService, 'transport', reason: 'chosen in the transport business');
      await t.pageBack();
      await t.pumpAndSettle();

      expect(find.text('Branch: Arusha yard'), findsOneWidget);
      expect(changed, 1, reason: 'the page is told to read its figures again');
    });

    testWidgets('coming back with nothing changed does not reload the page', (WidgetTester t) async {
      int changed = 0;
      await _pump(t, BranchFilterButton(service: 'rental', api: _Branches(two), onChanged: () => changed++));
      await t.tap(find.byKey(const Key('branch_filter_button')));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(changed, 0);
    });

    testWidgets('a branch chosen in another service is not shown as this one\'s', (WidgetTester t) async {
      await _pump(t, BranchFilterButton(service: 'rental', api: _Branches(two), onChanged: () {}));
      ApiService.chooseBranch(1, 'Dodoma yard', service: 'transport');
      await t.pump();
      await t.tap(find.byKey(const Key('branch_filter_button')));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Branch: All branches'), findsOneWidget);
    });

    testWidgets('speaks Swahili when asked', (WidgetTester t) async {
      await _pump(t, BranchFilterButton(service: 'rental', api: _Branches(two), onChanged: () {}));
      await LocalizationService.instance.changeLanguage('sw');
      await t.pumpWidget(
        ChangeNotifierProvider<LocalizationService>.value(
          value: LocalizationService.instance,
          child: MaterialApp(home: Scaffold(body: BranchFilterButton(service: 'rental', api: _Branches(two), onChanged: () {}))),
        ),
      );
      await t.pump();
      expect(find.text('Tawi: Matawi yote'), findsOneWidget);
    });
  });

  group('the Branch field on a form', () {
    testWidgets('is not there for a business with no branch', (WidgetTester t) async {
      await _pump(t, BranchPickerField(service: 'transport', api: _Branches(const <SalonBranchInfo>[]), onChanged: (_) {}));
      expect(find.byKey(const Key('branch_picker')), findsNothing);
    });

    testWidgets('offers the active branches and "No branch", and reports the choice', (WidgetTester t) async {
      final List<int?> got = <int?>[];
      await _pump(t, BranchPickerField(service: 'transport', api: _Branches(two), onChanged: got.add));
      expect(find.byKey(const Key('branch_picker')), findsOneWidget);

      await t.tap(find.byKey(const Key('branch_picker')));
      await t.pumpAndSettle();
      expect(find.text('Closed yard'), findsNothing, reason: 'a switched-off branch is not offered');
      expect(find.text('No branch'), findsWidgets);
      await t.tap(find.text('Arusha yard').last);
      await t.pumpAndSettle();
      expect(got.last, 2);
    });

    testWidgets('a new record starts on the branch being looked at, an old one on its own', (WidgetTester t) async {
      ApiService.chooseBranch(1, 'Dodoma yard', service: 'transport');
      final List<int?> fresh = <int?>[];
      await _pump(t, BranchPickerField(service: 'transport', api: _Branches(two), onChanged: fresh.add));
      expect(fresh.last, 1);

      final List<int?> old = <int?>[];
      await _pump(t, BranchPickerField(key: UniqueKey(), service: 'transport', initialId: 2, api: _Branches(two), onChanged: old.add));
      expect(old.last, 2);
    });

    testWidgets('the branch looked at in another service is not the starting one', (WidgetTester t) async {
      ApiService.chooseBranch(1, 'Dodoma yard', service: 'rental');
      final List<int?> got = <int?>[];
      await _pump(t, BranchPickerField(service: 'transport', api: _Branches(two), onChanged: got.add));
      expect(got.last, isNull);
    });

    testWidgets('an old record whose branch is switched off keeps showing it', (WidgetTester t) async {
      await _pump(t, BranchPickerField(service: 'transport', initialId: 3, api: _Branches(two), onChanged: (_) {}));
      expect(find.text('Closed yard'), findsOneWidget);
    });
  });
}
