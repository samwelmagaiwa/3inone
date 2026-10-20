import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/models/inv_sale.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/notifications_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/inventory_home.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/staff_picker.dart';
import 'package:boda_mapato/models/business_registration.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/screens/service_selection_screen.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:boda_mapato/utils/role_services.dart';
import 'package:boda_mapato/widgets/service_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Salon service: its own entry on the service picker, its own home (the inventory shell with the salon's
/// sections), and the sheet that says who served a client.
class _Auth extends AuthProvider {
  _Auth({this.services = const <String>['salon'], this.role = 'admin'});

  final List<String> services;
  final String role;

  @override
  UserData? get user => UserData(
        id: 'o1',
        name: 'Owner',
        email: 'o@example.test',
        role: role,
        isActive: true,
        serviceTypes: services,
      );

  @override
  UserPermissions get permissions => UserPermissions.fromRole(role);
}

class _Counting extends ApiService {
  final List<String> calls = <String>[];

  int count(String path) => calls.where((String c) => c == path || c.startsWith('$path?')).length;

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    calls.add(endpoint);
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{
        'data': <String, dynamic>{'inventory_type': 'retail', 'use_crates': '0', 'sale_tier': 'retail', 'depot_name': 'Glow Salon'},
      };
    }
    if (endpoint.startsWith('/inventory/salon/staff')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'u-asha', 'name': 'Asha', 'role': 'sales_officer'},
          <String, dynamic>{'id': 'u-bahati', 'name': 'Bahati', 'role': 'manager'},
        ],
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

Future<(_Counting, InventoryProvider)> _openHome(WidgetTester t, {required bool salon, bool sw = false}) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(411, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final _Counting server = _Counting();
  final InventoryProvider inv = InventoryProvider(api: server);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: server)),
        ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider(api: server)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(411, 900),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: InventoryHome(salon: salon)),
      ),
    ),
  );
  for (int i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
  return (server, inv);
}

Future<void> _openMenu(WidgetTester t) async {
  await t.tap(find.descendant(of: find.byType(InventoryFooter), matching: find.byIcon(Icons.grid_view_rounded)));
  for (int i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  group('the salon\'s home', () {
    testWidgets('knows it is a salon and reads who can serve, once', (t) async {
      final (_Counting server, InventoryProvider inv) = await _openHome(t, salon: true);

      expect(inv.salonMode, isTrue);
      expect(server.count('/inventory/salon/staff'), 1);
      expect(inv.salonStaff.map((Map<String, String> s) => s['name']).toList(), <String>['Asha', 'Bahati']);
    });

    testWidgets('has the salon\'s sections and none of the stock-taking ones', (t) async {
      await _openHome(t, salon: true);
      await _openMenu(t);

      for (final String label in <String>['Services & Goods', 'Sales', 'Stylists', 'Come back', 'Reports', 'Clients & Credit', 'Settings']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Stock Levels'), findsNothing);
      expect(find.text('Purchasing'), findsNothing);
    });

    testWidgets('in Swahili the sections are Swahili', (t) async {
      await _openHome(t, salon: true, sw: true);
      await _openMenu(t);

      expect(find.text('Huduma na Bidhaa'), findsOneWidget);
      expect(find.text('Wahudumu'), findsOneWidget);
      expect(find.text('Vikumbusho vya kurudi'), findsOneWidget);
      expect(find.text('Wateja na Madeni'), findsOneWidget);
    });

    testWidgets('the footer still opens sales and settings, the way it does everywhere', (t) async {
      await _openHome(t, salon: true);

      await t.tap(find.descendant(of: find.byType(InventoryFooter), matching: find.byIcon(Icons.point_of_sale_rounded)));
      for (int i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 250));
      }
      expect(find.text('Sales'), findsWidgets);
      expect(t.takeException(), isNull);
    });

    testWidgets('an ordinary inventory home is not a salon: no stylists, no come-back section, no staff asked for', (t) async {
      final (_Counting server, InventoryProvider inv) = await _openHome(t, salon: false);
      await _openMenu(t);

      expect(inv.salonMode, isFalse);
      expect(server.count('/inventory/salon/staff'), 0);
      expect(find.text('Stylists'), findsNothing);
      expect(find.text('Come back'), findsNothing);
      expect(find.text('Purchasing'), findsOneWidget);
    });
  });

  group('the service picker and the guards', () {
    test('a super admin has all four services, and nobody else gets the salon by role', () {
      expect(servicesForRole('super_admin'), <String>['inventory', 'rental', 'transport', 'salon']);
      for (final String role in <String>['admin', 'manager', 'sales_officer', 'operator', 'driver', 'landlord']) {
        expect(servicesForRole(role), isNot(contains('salon')), reason: role);
      }
      expect(kBusinessServices, <String>['inventory', 'rental', 'transport', 'salon']);
    });

    testWidgets('Salon is a tile of its own, and opens the salon', (t) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      String? opened;
      t.view.physicalSize = const Size(411, 860);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ChangeNotifierProvider<LocalizationService>.value(
          value: LocalizationService.instance,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            minTextAdapt: true,
            builder: (_, __) => MaterialApp(
              home: const ServiceSelectionScreen(allowedServices: <String>['inventory', 'salon']),
              onGenerateRoute: (RouteSettings s) {
                opened = s.name;
                return MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('salon opened')), settings: s);
              },
            ),
          ),
        ),
      );
      await t.pump();

      expect(find.text('Salon'), findsOneWidget);
      expect(find.byIcon(Icons.content_cut_rounded), findsOneWidget);

      await t.tap(find.byIcon(Icons.content_cut_rounded));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));

      expect(opened, '/salon');
    });

    testWidgets('a business with no salon is not offered one', (t) async {
      t.view.physicalSize = const Size(411, 860);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ChangeNotifierProvider<LocalizationService>.value(
          value: LocalizationService.instance,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            minTextAdapt: true,
            builder: (_, __) => const MaterialApp(home: ServiceSelectionScreen(allowedServices: <String>['inventory', 'rental', 'transport'])),
          ),
        ),
      );
      await t.pump();

      expect(find.byIcon(Icons.content_cut_rounded), findsNothing);
    });

    testWidgets('the salon route is guarded: a user without the salon service is sent back to the picker', (t) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      t.view.physicalSize = const Size(411, 860);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      Future<void> show(List<String> services) async {
        await t.pumpWidget(
          MultiProvider(
            key: UniqueKey(),
            providers: <ChangeNotifierProvider<ChangeNotifier>>[
              ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(services: services)),
              ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
            ],
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              minTextAdapt: true,
              builder: (_, __) => const MaterialApp(home: ServiceGuard(service: 'salon', child: Text('the salon'))),
            ),
          ),
        );
        await t.pump();
      }

      await show(<String>['salon']);
      expect(find.text('the salon'), findsOneWidget);

      await show(<String>['inventory']);
      expect(find.text('the salon'), findsNothing);
      expect(find.byType(ServiceSelectionScreen), findsOneWidget);
    });
  });

  group('who served the client', () {
    Future<InvSaleItem> openSheet(WidgetTester t, {InvSaleItem? item}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      t.view.physicalSize = const Size(411, 900);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final InventoryProvider inv = InventoryProvider(api: _Counting());
      final InvSaleItem line = item ?? InvSaleItem(productId: 1, name: 'Braids', qty: 1, unitPrice: 40000, unitCostSnapshot: 0, isService: true);
      await t.pumpWidget(
        MultiProvider(
          providers: <ChangeNotifierProvider<ChangeNotifier>>[
            ChangeNotifierProvider<InventoryProvider>.value(value: inv),
            ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
          ],
          child: ScreenUtilInit(
            designSize: const Size(411, 900),
            minTextAdapt: true,
            builder: (_, __) => MaterialApp(
              home: Builder(
                builder: (BuildContext ctx) => Scaffold(body: TextButton(onPressed: () => pickStylist(ctx, line), child: const Text('who'))),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('who'));
      for (int i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 250));
      }
      return line;
    }

    testWidgets('lists the salon\'s people and "nobody"', (t) async {
      await openSheet(t);

      expect(find.text('Who served the client?'), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Bahati'), findsOneWidget);
      expect(find.text('Nobody (do not name a stylist)'), findsOneWidget);
    });

    testWidgets('choosing someone names them on the line and closes the sheet', (t) async {
      final InvSaleItem line = await openSheet(t);

      await t.tap(find.text('Bahati'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));

      expect(line.staffId, 'u-bahati');
      expect(line.staffName, 'Bahati');
      expect(find.text('Who served the client?'), findsNothing);
    });

    testWidgets('the one already chosen is ticked, and "nobody" clears it', (t) async {
      final InvSaleItem line = InvSaleItem(productId: 1, name: 'Braids', qty: 1, unitPrice: 40000, unitCostSnapshot: 0, isService: true, staffId: 'u-asha', staffName: 'Asha');
      await openSheet(t, item: line);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await t.tap(find.text('Nobody (do not name a stylist)'));
      await t.pump(const Duration(milliseconds: 400));

      expect(line.staffId, isNull);
      expect(line.staffName, isNull);
    });
  });
}
