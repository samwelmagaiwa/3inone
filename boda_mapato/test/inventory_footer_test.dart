import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/notifications_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/dashboard/inventory_dashboard_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/hubs/products_hub_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/inventory_home.dart';
import 'package:boda_mapato/modules/inventory/screens/products/add_edit_product_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/settings/depot_settings_screen.dart';
import 'package:boda_mapato/screens/settings/settings_screen.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The inventory footer on the product form. The form used to carry a copy of an older footer, with placeholder
/// icons, whose gear opened the app's profile Settings instead of the inventory's. These tests open a real
/// inventory home, put the form on top of it, and press the footer.

class _Auth extends AuthProvider {
  _Auth([this.role = 'admin']);

  final String role;

  @override
  UserData? get user => UserData(id: 'o1', name: 'Owner', email: 'o@example.test', role: role, isActive: true);

  @override
  UserPermissions get permissions => UserPermissions.fromRole(role);
}

class _Server extends ApiService {
  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{
        'data': <String, dynamic>{'inventory_type': 'retail', 'use_crates': '0', 'sale_tier': 'retail', 'depot_name': 'Shop'},
      };
    }
    return null; // what an unreachable endpoint gives: every screen copes with "no data"
  }
}

void _ignoreTestFontOverflow() {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Finder get _footer => find.byType(InventoryFooter);
Finder _footerIcon(IconData icon) => find.descendant(of: _footer, matching: find.byIcon(icon));
final LocalizationService _loc = LocalizationService.instance;

/// The title in the app bar of the inventory home.
Finder _title(String text) => find.descendant(of: find.byType(AppBar).first, matching: find.text(text));

Future<NavigatorState> _openHome(WidgetTester t, {String role = 'admin'}) async {
  _ignoreTestFontOverflow();
  t.view.physicalSize = const Size(411, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Server server = _Server();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>(create: (_) => InventoryProvider(api: server)),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: server)),
        ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider(api: server)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(role)),
        ChangeNotifierProvider<LocalizationService>.value(value: _loc),
      ],
      child: ScreenUtilInit(
        designSize: const Size(411, 900),
        minTextAdapt: true,
        builder: (_, __) => const MaterialApp(home: InventoryHome()),
      ),
    ),
  );
  for (int i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
  return t.state<NavigatorState>(find.byType(Navigator));
}

/// Puts the product form on top of the home, as the "Add product" button does.
Future<void> _openForm(WidgetTester t, NavigatorState navigator) async {
  navigator.push(MaterialPageRoute<void>(builder: (_) => const AddEditProductScreen()));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  group('the product form\'s footer', () {
    testWidgets('is the inventory footer: dashboard, products, all sections, sales, settings', (t) async {
      final NavigatorState nav = await _openHome(t);
      await _openForm(t, nav);

      expect(find.byType(AddEditProductScreen), findsOneWidget);
      expect(_footer, findsOneWidget, reason: 'one footer on the screen: the form\'s');
      for (final IconData icon in <IconData>[
        Icons.bar_chart_rounded,
        Icons.inventory_2_rounded,
        Icons.grid_view_rounded,
        Icons.point_of_sale_rounded,
        Icons.settings_rounded,
      ]) {
        expect(_footerIcon(icon), findsOneWidget, reason: '$icon');
      }
    });

    testWidgets('no longer has the placeholder icons of the old copy', (t) async {
      final NavigatorState nav = await _openHome(t);
      await _openForm(t, nav);

      expect(_footerIcon(Icons.calendar_today_outlined), findsNothing);
      expect(_footerIcon(Icons.pets_outlined), findsNothing);
      expect(_footerIcon(Icons.person_outline), findsNothing);
      expect(_footerIcon(Icons.settings_outlined), findsNothing, reason: 'the old gear is gone');
    });

    testWidgets('the gear opens the inventory\'s Settings, not the app\'s profile settings', (t) async {
      final NavigatorState nav = await _openHome(t);
      await _openForm(t, nav);

      await t.tap(_footerIcon(Icons.settings_rounded));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(find.byType(AddEditProductScreen), findsNothing, reason: 'the form is closed');
      expect(find.byType(InventoryHome), findsOneWidget);
      expect(find.byType(DepotSettingsScreen), findsOneWidget, reason: 'the inventory Settings is showing');
      expect(_title(_loc.translate('settings')), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'no unknown "/settings" route was pushed');
    });

    testWidgets('for a sales officer the gear opens their account page, not another section', (t) async {
      await _openHome(t, role: 'sales_officer');

      await t.tap(_footerIcon(Icons.settings_rounded));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(DepotSettingsScreen), findsNothing, reason: 'the business settings are for whoever may change them');
    });

    testWidgets('Products brings the Products section back', (t) async {
      final NavigatorState nav = await _openHome(t);
      await _openForm(t, nav);

      await t.tap(_footerIcon(Icons.inventory_2_rounded));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(find.byType(AddEditProductScreen), findsNothing);
      expect(find.byType(ProductsHubScreen), findsOneWidget);
    });

    testWidgets('the dashboard button brings the dashboard back', (t) async {
      final NavigatorState nav = await _openHome(t);
      await t.tap(_footerIcon(Icons.inventory_2_rounded)); // leave the dashboard first
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await _openForm(t, nav);

      await t.tap(_footerIcon(Icons.bar_chart_rounded));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(find.byType(AddEditProductScreen), findsNothing);
      expect(find.byType(InventoryDashboardScreen), findsOneWidget);
    });

    testWidgets('the grid button opens the inventory\'s own menu of sections', (t) async {
      final NavigatorState nav = await _openHome(t);
      await _openForm(t, nav);

      await t.tap(_footerIcon(Icons.grid_view_rounded));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(find.byType(AddEditProductScreen), findsNothing, reason: 'back on the home, where the menu belongs');
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text(_loc.translate('settings')), findsWidgets, reason: 'the menu lists Settings under its real name');
    });

    testWidgets('from deeper in the app the gear still returns to the one home, with no second one stacked', (t) async {
      final NavigatorState nav = await _openHome(t);
      nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('an in-between screen'))));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await _openForm(t, nav);

      await t.tap(_footerIcon(Icons.settings_rounded));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(find.byType(InventoryHome), findsOneWidget);
      expect(find.text('an in-between screen'), findsNothing);
      expect(nav.canPop(), isFalse, reason: 'back on the very first screen: nothing stacked above or under it');
    });
  });

  group('the inventory home', () {
    testWidgets('calls its Settings section "Settings", not "Depot settings"', (t) async {
      await _openHome(t);

      await t.tap(_footerIcon(Icons.settings_rounded));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(_title(_loc.translate('settings')), findsOneWidget);
      expect(_title(_loc.translate('depot_settings')), findsNothing);
    });
  });
}
