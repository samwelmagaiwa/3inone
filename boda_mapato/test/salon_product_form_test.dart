import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/products/add_edit_product_screen.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A salon adds SERVICES on the same form as goods: a switch says "this is a service", and then the form drops
/// everything about stock and asks only for the price, how long it takes and when to remind the client to come back.
class _FakeApi extends ApiService {
  final List<(String, Map<String, dynamic>)> puts = <(String, Map<String, dynamic>)>[];
  final List<(String, Map<String, dynamic>)> posts = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> put(String endpoint, Map<String, dynamic> data) async {
    puts.add((endpoint, data));
    return <String, dynamic>{'data': <String, dynamic>{'id': 9}};
  }

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data, {bool requireAuth = true}) async {
    posts.add((endpoint, data));
    return <String, dynamic>{'data': <String, dynamic>{'id': 9}};
  }

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{
        'data': <String, dynamic>{'inventory_type': 'retail', 'use_crates': '0', 'sale_tier': 'retail', 'prices_include_vat': '1', 'tax_percent': '0'},
      };
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }
}

late _FakeApi _api;

InvProduct _braids() => InvProduct(
      id: 9,
      name: 'Braids',
      sku: 'BRA-1',
      category: '',
      costPrice: 0,
      sellingPrice: 40000,
      unit: 'pcs',
      quantity: 0,
      minStock: 0,
      status: 'active',
      barcode: 'BRA-1',
      createdBy: 1,
      isService: true,
      durationMinutes: 90,
      rebookAfterWeeks: 3,
    );

InvProduct _shampoo() => InvProduct(
      id: 8,
      name: 'Shampoo',
      sku: 'SHA-1',
      category: '',
      costPrice: 3000,
      sellingPrice: 8000,
      unit: 'pcs',
      quantity: 20,
      minStock: 2,
      status: 'active',
      barcode: 'SHA-1',
      createdBy: 1,
    );

void _ignoreTestFontOverflow() {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));
Finder _hint(String h) => find.byWidgetPredicate((Widget w) => w is TextField && w.decoration?.hintText == h);
String _typed(WidgetTester t, Finder f) => t.widget<TextField>(f).controller!.text;
Finder _switchLabelled(String label) => find.descendant(of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first, matching: find.byType(Switch));

Future<void> _open(WidgetTester t, {InvProduct? product, bool salon = true, bool sw = false}) async {
  _ignoreTestFontOverflow();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  _api = _FakeApi();
  t.view.physicalSize = const Size(800, 6000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final InventoryProvider inv = InventoryProvider(api: _api);
  await inv.fetchCapabilities();
  inv.setSalonMode(salon);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: _api)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(
        designSize: const Size(800, 6000),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(
          home: Builder(
            builder: (BuildContext ctx) => Scaffold(
              body: TextButton(
                key: const ValueKey<String>('open_page'),
                onPressed: () => Navigator.push<void>(ctx, MaterialPageRoute<void>(builder: (_) => AddEditProductScreen(product: product))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(_key('open_page'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await t.pump(const Duration(milliseconds: 200));
}

Future<void> _save(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.save).first);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(seconds: 4));
}

Future<void> _serviceOn(WidgetTester t) async {
  await t.tap(_switchLabelled('This is a service (no stock)'));
  await t.pump();
}

void main() {
  group('the switch', () {
    testWidgets('a business that is not a salon is never asked about services', (t) async {
      await _open(t, salon: false);

      expect(find.text('This is a service (no stock)'), findsNothing);
    });

    testWidgets('a salon is asked, and it starts off: a new item is goods until it says otherwise', (t) async {
      await _open(t);

      expect(find.text('This is a service (no stock)'), findsOneWidget);
      expect(t.widget<Switch>(_switchLabelled('This is a service (no stock)')).value, isFalse);
      expect(_hint('e.g. 100'), findsOneWidget, reason: 'the stock count is there for goods');
    });

    testWidgets('in Swahili the switch and its fields are Swahili', (t) async {
      await _open(t, sw: true);
      await t.tap(_switchLabelled('Hii ni huduma (haina stock)'));
      await t.pump();

      expect(find.text('Muda (dakika)'), findsOneWidget);
      expect(find.text('Mkumbushe baada ya (wiki)'), findsOneWidget);
      expect(find.text('Bei ya huduma (TZS)'), findsOneWidget);
    });
  });

  group('a service has no stock', () {
    testWidgets('switching it on removes cost, stock, alert level, packs and sizes, and asks for the price, time and wait', (t) async {
      await _open(t);
      expect(_hint('e.g. 20,000'), findsOneWidget, reason: 'cost price, for goods');
      expect(_hint('e.g. 24'), findsOneWidget, reason: 'stock alert level, for goods');

      await _serviceOn(t);

      expect(_hint('e.g. 100'), findsNothing, reason: 'no stock count');
      expect(_hint('e.g. 20,000'), findsNothing, reason: 'no cost of goods');
      expect(_hint('e.g. 24'), findsNothing, reason: 'no stock alert');
      expect(find.text('Service price (TZS)'), findsOneWidget);
      expect(_hint('e.g. 120'), findsOneWidget, reason: 'duration');
      expect(_hint('e.g. 6'), findsOneWidget, reason: 'weeks to remind');
      expect(_key('service_rebook_hint'), findsOneWidget);
      expect(find.text('Packs and cartons'), findsNothing);
    });

    testWidgets('switching it off brings the stock fields back', (t) async {
      await _open(t);
      await _serviceOn(t);
      await t.tap(_switchLabelled('This is a service (no stock)'));
      await t.pump();

      expect(_hint('e.g. 100'), findsOneWidget);
      expect(_hint('e.g. 120'), findsNothing);
    });
  });

  group('adding a service', () {
    testWidgets('sends it as a service, with its time and wait, and nothing about stock', (t) async {
      await _open(t);
      await t.enterText(_hint('e.g. Coca-Cola 350ml'), 'Braids');
      await _serviceOn(t);
      await t.enterText(_hint('e.g. 15,000'), '40000');
      await t.enterText(_hint('e.g. 120'), '180');
      await t.enterText(_hint('e.g. 6'), '6');
      await _save(t);

      final (String, Map<String, dynamic>) post = _api.posts.firstWhere(((String, Map<String, dynamic>) p) => p.$1 == '/inventory/products');
      final Map<String, dynamic> body = post.$2;
      expect(body['name'], 'Braids');
      expect(body['is_service'], true);
      expect(body['duration_minutes'], 180);
      expect(body['rebook_after_weeks'], 6);
      expect(body['selling_price'], 40000);
      expect(body['cost_price'], 0, reason: 'a service carries no cost of goods');
      expect(body['quantity'], 0);
      expect(body['min_stock'], 0);
      expect(body.containsKey('units'), isFalse);
      expect(body.containsKey('variants'), isFalse);
    });

    testWidgets('the time and the wait are optional', (t) async {
      await _open(t);
      await t.enterText(_hint('e.g. Coca-Cola 350ml'), 'Wash');
      await _serviceOn(t);
      await t.enterText(_hint('e.g. 15,000'), '5000');
      await _save(t);

      final Map<String, dynamic> body = _api.posts.firstWhere(((String, Map<String, dynamic>) p) => p.$1 == '/inventory/products').$2;
      expect(body['is_service'], true);
      expect(body.containsKey('duration_minutes'), isFalse);
      expect(body.containsKey('rebook_after_weeks'), isFalse, reason: 'the salon\'s own number applies');
    });

    testWidgets('goods added in a salon are not marked as services', (t) async {
      await _open(t);
      await t.enterText(_hint('e.g. Coca-Cola 350ml'), 'Shampoo');
      await t.enterText(_hint('e.g. 20,000'), '3000');
      await t.enterText(_hint('e.g. 25,000'), '8000');
      await t.enterText(_hint('e.g. 100'), '20');
      await _save(t);

      final Map<String, dynamic> body = _api.posts.firstWhere(((String, Map<String, dynamic>) p) => p.$1 == '/inventory/products').$2;
      expect(body.containsKey('is_service'), isFalse);
      expect(body['quantity'], 20);
      expect(body['cost_price'], 3000);
    });

    for (final (String field, String hint, String typed, String message) in <(String, String, String, String)>[
      ('weeks above 52', 'e.g. 6', '60', 'The weeks to remind the client must be between 1 and 52.'),
      ('weeks of zero', 'e.g. 6', '0', 'The weeks to remind the client must be between 1 and 52.'),
      ('a duration of zero', 'e.g. 120', '0', 'The duration must be between 1 and 1440 minutes.'),
      ('a duration over a day', 'e.g. 120', '2000', 'The duration must be between 1 and 1440 minutes.'),
    ]) {
      testWidgets('$field is refused with a reason, and nothing is sent', (t) async {
        await _open(t);
        await t.enterText(_hint('e.g. Coca-Cola 350ml'), 'Braids');
        await _serviceOn(t);
        await t.enterText(_hint('e.g. 15,000'), '40000');
        await t.enterText(_hint(hint), typed);
        await _save(t);

        expect(find.text(message), findsOneWidget);
        expect(_api.posts.where(((String, Map<String, dynamic>) p) => p.$1 == '/inventory/products'), isEmpty);
      });
    }
  });

  group('editing', () {
    testWidgets('a service comes back as a service with its price, time and wait', (t) async {
      await _open(t, product: _braids());

      expect(t.widget<Switch>(_switchLabelled('This is a service (no stock)')).value, isTrue);
      expect(_typed(t, _hint('e.g. 15,000')), '40,000');
      expect(_typed(t, _hint('e.g. 120')), '90');
      expect(_typed(t, _hint('e.g. 6')), '3');
      expect(_hint('e.g. 100'), findsNothing);
    });

    testWidgets('saving it sends the service fields back, with no stock', (t) async {
      await _open(t, product: _braids());
      await t.enterText(_hint('e.g. 120'), '120');
      await _save(t);

      final Map<String, dynamic> body = _api.puts.single.$2;
      expect(_api.puts.single.$1, '/inventory/products/9');
      expect(body['is_service'], true);
      expect(body['duration_minutes'], 120);
      expect(body['rebook_after_weeks'], 3);
      expect(body['quantity'], 0);
      expect(body['cost_price'], 0);
    });

    testWidgets('emptying the wait puts the service back to the salon\'s own number', (t) async {
      await _open(t, product: _braids());
      await t.enterText(_hint('e.g. 6'), '');
      await _save(t);

      final Map<String, dynamic> body = _api.puts.single.$2;
      expect(body.containsKey('rebook_after_weeks'), isTrue);
      expect(body['rebook_after_weeks'], isNull, reason: 'null clears it on the server');
    });

    testWidgets('goods stay goods: no service fields are sent for them', (t) async {
      await _open(t, product: _shampoo());
      await _save(t);

      final Map<String, dynamic> body = _api.puts.single.$2;
      expect(body['is_service'], false);
      expect(body.containsKey('duration_minutes'), isFalse);
      expect(body.containsKey('rebook_after_weeks'), isFalse);
      expect(body['quantity'], 20);
    });
  });
}
