import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/notifications_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/inventory_home.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Opening the inventory home used to build all eight sections at once, and with them about thirty requests, most
/// of them for screens nobody was looking at; and a business without crates still asked for crate data. A section
/// is now built (and loads) the first time it is opened, and crate data is asked for only by businesses with crates.
class _Auth extends AuthProvider {
  @override
  UserData? get user => UserData(id: 'o1', name: 'Owner', email: 'o@example.test', role: 'admin', isActive: true);

  @override
  UserPermissions get permissions => UserPermissions.fromRole('admin');
}

/// Remembers every request; answers the settings, and nothing else (like an unreachable endpoint).
class _Counting extends ApiService {
  _Counting(this.kind);

  final String kind;
  final List<String> calls = <String>[];

  /// Requests for this path (ignoring any query string).
  int count(String path) => calls.where((String c) => c == path || c.startsWith('$path?')).length;

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    calls.add(endpoint);
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{
        'data': <String, dynamic>{
          'inventory_type': kind,
          'use_crates': kind == 'depot' ? '1' : '0',
          'sale_tier': kind == 'depot' ? 'product' : 'retail',
          'depot_name': 'Shop',
        },
      };
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> get(String endpoint, {bool requireAuth = true, Map<String, dynamic>? queryParams}) async {
    calls.add(endpoint);
    throw ApiException('offline');
  }
}

Future<_Counting> _openHome(WidgetTester t, String kind) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  t.view.physicalSize = const Size(411, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Counting server = _Counting(kind);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>(create: (_) => InventoryProvider(api: server)),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: server)),
        ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider(api: server)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(411, 900),
        minTextAdapt: true,
        builder: (_, __) => const MaterialApp(home: InventoryHome()),
      ),
    ),
  );
  await _settle(t);
  return server;
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _tapFooter(WidgetTester t, IconData icon) async {
  await t.tap(find.descendant(of: find.byType(InventoryFooter), matching: find.byIcon(icon)));
  await _settle(t);
}

void main() {
  group('opening the inventory home', () {
    testWidgets('asks only for what the dashboard needs, not for the other sections', (t) async {
      final _Counting server = await _openHome(t, 'retail');

      for (final String path in <String>[
        '/inventory/audit-log', // Settings
        '/inventory/suppliers', // Purchasing
        '/inventory/purchase-orders',
        '/inventory/supplier-invoices',
        '/inventory/cash-sessions', // Daily cash
        '/inventory/credit/customers', // Customers & credit
        '/inventory/credit/debtors-ageing',
      ]) {
        expect(server.count(path), 0, reason: '$path belongs to a section nobody has opened yet');
      }
      expect(server.calls.length, lessThan(14), reason: 'it was 19 before; calls: ${server.calls}');
    });

    testWidgets('a section loads when it is opened, and only once however often it is revisited', (t) async {
      final _Counting server = await _openHome(t, 'retail');
      expect(server.count('/inventory/audit-log'), 0);

      await _tapFooter(t, Icons.settings_rounded);
      expect(server.count('/inventory/audit-log'), 1, reason: 'Settings was opened');

      await _tapFooter(t, Icons.bar_chart_rounded);
      await _tapFooter(t, Icons.settings_rounded);
      expect(server.count('/inventory/audit-log'), 1, reason: 'kept, not built and loaded again');
    });

    testWidgets('the dashboard is there straight away', (t) async {
      final _Counting server = await _openHome(t, 'retail');

      expect(server.count('/inventory/sales/monthly-chart'), greaterThanOrEqualTo(0));
      expect(find.byType(InventoryHome), findsOneWidget);
      expect(find.byType(InventoryFooter), findsOneWidget);
    });
  });

  group('crates', () {
    testWidgets('a shop never asks for crate data, in any section it opens', (t) async {
      final _Counting server = await _openHome(t, 'retail');

      await _tapFooter(t, Icons.settings_rounded);
      await _tapFooter(t, Icons.point_of_sale_rounded);
      await _tapFooter(t, Icons.inventory_2_rounded);

      for (final String path in <String>['/inventory/crate-types', '/inventory/crate-balances', '/inventory/crate-position']) {
        expect(server.count(path), 0, reason: '$path is for businesses with crates; calls: ${server.calls}');
      }
    });

    testWidgets('a depot asks for its crate types when Settings opens', (t) async {
      final _Counting server = await _openHome(t, 'depot');

      await _tapFooter(t, Icons.settings_rounded);

      expect(server.count('/inventory/crate-types'), greaterThanOrEqualTo(1));
    });
  });

  group('DepotProvider crate calls', () {
    for (final (String settings, bool asks) in <(String, bool)>[('0', false), ('1', true)]) {
      test('with use_crates=$settings it ${asks ? "asks" : "does not ask"} for crate types, balances and position', () async {
        final _Counting api = _Counting(settings == '1' ? 'depot' : 'retail');
        final DepotProvider depot = DepotProvider(api: api);
        await depot.fetchSettings();
        api.calls.clear();

        await depot.fetchCrateTypes();
        await depot.fetchCrateBalances();
        await depot.fetchCratePosition();

        expect(api.calls.where((String c) => c.contains('crate')).length, asks ? 3 : 0);
      });
    }

    test('before the settings are known it asks, as a depot always did', () async {
      final _Counting api = _Counting('retail');
      final DepotProvider depot = DepotProvider(api: api);

      await depot.fetchCrateTypes();

      expect(api.count('/inventory/crate-types'), 1);
    });
  });
}
