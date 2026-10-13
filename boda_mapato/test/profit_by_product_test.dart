import 'package:boda_mapato/constants/theme_constants.dart';
import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/dashboard/inventory_dashboard_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/reports/profit_by_product_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/profit_by_product_table.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

// The app's default language is Swahili, so these are the Swahili labels.
const String _title = 'Faida kwa Bidhaa';
const String _subtitle = 'Zimepangwa kwa mauzo';

/// [count] products named "Item 01".. whose stock falls with the number, so the profit
/// table (most units first) lists them in number order.
List<InvProduct> _products(final int count) => <InvProduct>[
      for (int i = 1; i <= count; i++)
        InvProduct(
          id: i,
          name: 'Item ${i.toString().padLeft(2, '0')}',
          sku: 'SKU-$i',
          category: 'Drinks',
          costPrice: 1000,
          sellingPrice: 1500,
          unit: 'carton',
          quantity: 1000 - i * 10,
          minStock: 5,
          status: 'active',
          barcode: '',
          createdBy: 1,
        ),
    ];

String _name(final int i) => 'Item ${i.toString().padLeft(2, '0')}';

Widget _scaled(final Widget child) => ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      builder: (_, __) => child,
    );

/// Someone who may see the products and the reports (where the profit table is) and
/// nothing more -- not an admin, so the dashboard's officer filter does not appear.
class _FakeAuth extends AuthProvider {
  @override
  UserData? get user => UserData(
        id: '1',
        name: 'Report Viewer',
        email: 'viewer@example.test',
        role: 'viewer',
        isActive: true,
        permissions: <String>['inv_view_products', 'inv_view_reports'],
      );
}

class _FakeInventory extends InventoryProvider {
  _FakeInventory(this.items);

  final List<InvProduct> items;
  int fetches = 0;

  @override
  List<InvProduct> get products => items;

  @override
  Future<void> fetchProducts({int page = 1, String? q, String? status, bool? lowStock}) async {
    fetches++;
  }
}

Future<void> _bigScreen(final WidgetTester tester) async {
  tester.view.physicalSize = const Size(411, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ranking', () {
    test('lists the products with the most units first, the same way everywhere', () {
      final List<InvProduct> shuffled = _products(5).reversed.toList();

      expect(rankedForProfit(shuffled).map((InvProduct p) => p.name).toList(),
          <String>[_name(1), _name(2), _name(3), _name(4), _name(5)]);
      expect(rankedForProfit(<InvProduct>[]), isEmpty);
    });
  });

  group('the table', () {
    Future<void> pumpTable(final WidgetTester tester, final int count, {final int? limit}) async {
      await _bigScreen(tester);
      await tester.pumpWidget(_scaled(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfitByProductTable(products: rankedForProfit(_products(count)), limit: limit),
          ),
        ),
      )));
    }

    testWidgets('with a limit it lists only that many, numbered from 1', (tester) async {
      await pumpTable(tester, 12, limit: 8);

      for (int i = 1; i <= 8; i++) {
        expect(find.text(_name(i)), findsOneWidget, reason: 'row $i is shown');
      }
      for (int i = 9; i <= 12; i++) {
        expect(find.text(_name(i)), findsNothing, reason: 'row $i is beyond the limit');
      }
    });

    testWidgets('without a limit it lists every product', (tester) async {
      await pumpTable(tester, 12);

      for (int i = 1; i <= 12; i++) {
        expect(find.text(_name(i)), findsOneWidget);
      }
      expect(find.text('12'), findsWidgets, reason: 'rank 12 is numbered');
    });

    testWidgets('a short list is shown whole even with a limit', (tester) async {
      await pumpTable(tester, 5, limit: 8);

      for (int i = 1; i <= 5; i++) {
        expect(find.text(_name(i)), findsOneWidget);
      }
    });

    testWidgets('each row shows unit, quantity, cost and expected profit', (tester) async {
      await pumpTable(tester, 1);

      // Item 01: 990 units, cost 1,000 each, profit 500 each.
      expect(find.text('CARTON'), findsOneWidget);
      expect(find.text('990'), findsOneWidget);
      expect(find.text('990,000'), findsOneWidget, reason: 'total cost');
      expect(find.text('495,000'), findsOneWidget, reason: 'expected profit');
      // Header columns, in the Swahili the dashboard uses.
      for (final String header in <String>['Na.', 'Bidhaa', 'Idadi', 'Gharama', 'Faida']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
    });
  });

  group('the "see all" button', () {
    Future<List<int>> pumpButton(final WidgetTester tester, final int total) async {
      final List<int> taps = <int>[];
      await tester.pumpWidget(_scaled(MaterialApp(
        home: Scaffold(body: ProfitSeeAllButton(total: total, onPressed: () => taps.add(1))),
      )));

      return taps;
    }

    OutlinedButton button(final WidgetTester tester) =>
        tester.widget<OutlinedButton>(find.byKey(const ValueKey<String>('profit_see_all')));

    testWidgets('is live and tappable when there are more than 8 products', (tester) async {
      final List<int> taps = await pumpButton(tester, 9);

      expect(button(tester).onPressed, isNotNull);
      expect(find.text('Ona bidhaa zote (9)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('profit_see_all')));
      expect(taps, hasLength(1));
    });

    testWidgets('looks like a quiet accent button: arrow, cyan label, faint outline, no fill, full width', (tester) async {
      await pumpButton(tester, 9);

      final ButtonStyle style = button(tester).style!;
      expect(style.foregroundColor!.resolve(<WidgetState>{}), ThemeConstants.invAccent);
      expect(style.backgroundColor!.resolve(<WidgetState>{}), Colors.transparent, reason: 'no fill');
      final BorderSide side = style.side!.resolve(<WidgetState>{})!;
      expect(side.color, ThemeConstants.invAccent.withValues(alpha: 0.22));
      expect(style.textStyle!.resolve(<WidgetState>{})!.fontWeight, FontWeight.w700);

      expect(find.descendant(of: find.byKey(const ValueKey<String>('profit_see_all')), matching: find.byIcon(Icons.arrow_forward_rounded)),
          findsOneWidget);
      expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);

      // Across the whole card, not just as wide as its text.
      expect(tester.getSize(find.byKey(const ValueKey<String>('profit_see_all'))).width, tester.getSize(find.byType(Scaffold)).width);
    });

    for (final int total in <int>[0, 3, 8]) {
      testWidgets('stays in place but muted and read-only with $total product(s)', (tester) async {
        final List<int> taps = await pumpButton(tester, total);

        expect(find.byKey(const ValueKey<String>('profit_see_all')), findsOneWidget, reason: 'it does not jump');
        expect(button(tester).onPressed, isNull, reason: 'disabled');

        await tester.tap(find.byKey(const ValueKey<String>('profit_see_all')), warnIfMissed: false);
        expect(taps, isEmpty, reason: 'a muted button does nothing');
      });
    }
  });

  group('the full screen', () {
    Future<_FakeInventory> pumpScreen(final WidgetTester tester, final int count) async {
      await _bigScreen(tester);
      final _FakeInventory inventory = _FakeInventory(_products(count));
      await tester.pumpWidget(_scaled(ChangeNotifierProvider<InventoryProvider>.value(
        value: inventory,
        child: const MaterialApp(home: ProfitByProductScreen()),
      )));
      await tester.pump();

      return inventory;
    }

    testWidgets('is named "Faida kwa Bidhaa", sorted by sales, and lists every product', (tester) async {
      await pumpScreen(tester, 12);

      expect(find.text(_title), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('profit_subtitle')), findsOneWidget);
      expect(find.text(_subtitle), findsOneWidget);
      for (int i = 1; i <= 12; i++) {
        expect(find.text(_name(i)), findsOneWidget, reason: 'product $i is listed');
      }
      expect(find.text('12'), findsWidgets);
    });

    testWidgets('shows a message instead of an empty table when there are no products', (tester) async {
      final _FakeInventory inventory = await pumpScreen(tester, 0);
      await tester.pump(); // the refresh it started has finished

      expect(find.byType(ProfitByProductTable), findsNothing);
      expect(find.text('Hakuna taarifa'), findsOneWidget);
      expect(inventory.fetches, 1, reason: 'it tried to load the products itself');
    });

    testWidgets('does not reload products that are already there', (tester) async {
      final _FakeInventory inventory = await pumpScreen(tester, 3);

      expect(inventory.fetches, 0);
    });
  });

  group('on the dashboard', () {
    Future<void> pumpDashboard(final WidgetTester tester, final int count) async {
      await _bigScreen(tester);
      await tester.pumpWidget(MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuth()),
          ChangeNotifierProvider<InventoryProvider>(create: (_) => _FakeInventory(_products(count))),
          ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider()),
          ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
        ],
        // In the app the dashboard sits inside the home screen's Scaffold.
        child: _scaled(const MaterialApp(home: Scaffold(body: InventoryDashboardScreen()))),
      ));
      await tester.pump(const Duration(seconds: 2));
    }

    OutlinedButton button(final WidgetTester tester) =>
        tester.widget<OutlinedButton>(find.byKey(const ValueKey<String>('profit_see_all')));

    testWidgets('lists 8 products and a live button that opens the full screen', (tester) async {
      await pumpDashboard(tester, 12);

      expect(find.text(_name(8)), findsWidgets);
      expect(find.text(_name(9)), findsNothing, reason: 'only 8 on the dashboard');
      expect(button(tester).onPressed, isNotNull);

      await tester.ensureVisible(find.byKey(const ValueKey<String>('profit_see_all')));
      await tester.tap(find.byKey(const ValueKey<String>('profit_see_all')));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.byType(ProfitByProductScreen), findsOneWidget);
      expect(find.text(_name(12)), findsOneWidget, reason: 'the full screen shows the rest');
      expect(find.text(_subtitle), findsOneWidget);
    });

    testWidgets('with 8 or fewer products the button is muted and nothing else changes', (tester) async {
      await pumpDashboard(tester, 8);

      for (int i = 1; i <= 8; i++) {
        expect(find.text(_name(i)), findsWidgets);
      }
      expect(button(tester).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey<String>('profit_see_all')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ProfitByProductScreen), findsNothing, reason: 'a muted button goes nowhere');
    });
  });
}
