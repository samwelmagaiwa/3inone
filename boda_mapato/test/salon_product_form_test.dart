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
    if (endpoint.startsWith('/inventory/salon/staff')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'u-asha', 'name': 'Asha', 'role': 'sales_officer'},
          <String, dynamic>{'id': 'u-bahati', 'name': 'Bahati', 'role': 'manager'},
        ],
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

/// A new item in a salon opens as a service; these make sure of the one a test wants.
Future<void> _serviceOn(WidgetTester t) async {
  if (!t.widget<Switch>(_switchLabelled('This is a service (no stock)')).value) {
    await t.tap(_switchLabelled('This is a service (no stock)'));
    await t.pump();
  }
}

Future<void> _goodsOn(WidgetTester t) async {
  if (t.widget<Switch>(_switchLabelled('This is a service (no stock)')).value) {
    await t.tap(_switchLabelled('This is a service (no stock)'));
    await t.pump();
  }
}

void main() {
  group('the switch', () {
    testWidgets('a business that is not a salon is never asked about services', (t) async {
      await _open(t, salon: false);

      expect(find.text('This is a service (no stock)'), findsNothing);
    });

    testWidgets('a salon is asked, and it starts on: a new item is a service until it says otherwise', (t) async {
      await _open(t);

      expect(find.text('This is a service (no stock)'), findsOneWidget);
      expect(t.widget<Switch>(_switchLabelled('This is a service (no stock)')).value, isTrue);
      expect(_hint('e.g. 100'), findsNothing, reason: 'no stock count for a service');
      expect(find.text('Add service'), findsOneWidget);
    });

    testWidgets('the service form in a salon has no shelf paperwork: no SKU, barcode, packs, sizes or VAT', (t) async {
      await _open(t);

      expect(find.text('Service details'), findsOneWidget);
      expect(find.text('SKU Code'), findsNothing);
      expect(find.text('Barcode & status'), findsNothing);
      expect(find.text('Extra options (optional)'), findsNothing);
      expect(find.text('Does this product have its own VAT rate?'), findsNothing);
      expect(find.text('Status'), findsWidgets, reason: 'a service can still be switched off');
      expect(find.text('Stylist commission (%)'), findsOneWidget);
    });

    testWidgets('switched to goods, the form is the goods form again, with its title', (t) async {
      await _open(t);
      await _goodsOn(t);

      expect(find.text('Add goods'), findsOneWidget);
      expect(find.text('Product details'), findsOneWidget);
      expect(find.text('Barcode & status'), findsOneWidget);
      expect(find.text('Stylist commission (%)'), findsNothing);
    });

    testWidgets('in Swahili the switch and its fields are Swahili', (t) async {
      await _open(t, sw: true);

      expect(find.text('Muda (dakika)'), findsOneWidget);
      expect(find.text('Mkumbushe baada ya (wiki)'), findsOneWidget);
      expect(find.text('Bei ya huduma (TZS)'), findsOneWidget);
    });
  });

  group('a service has no stock', () {
    testWidgets('switching it on removes cost, stock, alert level, packs and sizes, and asks for the price, time and wait', (t) async {
      await _open(t);
      await _goodsOn(t);
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
      await t.tap(_switchLabelled('This is a service (no stock)'));
      await t.pump();

      expect(_hint('e.g. 100'), findsOneWidget);
      expect(_hint('e.g. 120'), findsNothing);
    });
  });

  group('adding a service', () {
    testWidgets('sends it as a service, with its time and wait, and nothing about stock', (t) async {
      await _open(t);
      await t.enterText(_hint('e.g. Braids (long)'), 'Braids');
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

    testWidgets('the commission of the stylist is sent with the service, and left out when empty', (t) async {
      await _open(t);
      await t.enterText(_hint('e.g. Braids (long)'), 'Braids');
      await t.enterText(_hint('e.g. 15,000'), '40000');
      await t.enterText(_hint('e.g. 30'), '30');
      await _save(t);
      final Map<String, dynamic> withRate = _api.posts.firstWhere(((String, Map<String, dynamic>) p) => p.$1 == '/inventory/products').$2;
      expect(withRate['commission_percent'], 30.0);
    });

    testWidgets('a fixed amount each time is sent beside the percent', (t) async {
      await _open(t);
      await t.enterText(_hint('e.g. Braids (long)'), 'Wash');
      await t.enterText(_hint('e.g. 15,000'), '5000');
      await t.enterText(_hint('e.g. 2,000'), '2000');
      await _save(t);

      final Map<String, dynamic> body = _api.posts.firstWhere(((String, Map<String, dynamic>) p) => p.$1 == '/inventory/products').$2;
      expect(body['commission_fixed'], 2000);
      expect(body.containsKey('commission_percent'), isFalse);
    });

    testWidgets('no commission typed sends none', (t) async {
      await _open(t);
      await t.enterText(_hint('e.g. Braids (long)'), 'Wash');
      await t.enterText(_hint('e.g. 15,000'), '5000');
      await _save(t);
      final Map<String, dynamic> body = _api.posts.firstWhere(((String, Map<String, dynamic>) p) => p.$1 == '/inventory/products').$2;
      expect(body.containsKey('commission_percent'), isFalse);
    });

    testWidgets('a commission above 100 is refused with a reason', (t) async {
      await _open(t);
      await t.enterText(_hint('e.g. Braids (long)'), 'Braids');
      await t.enterText(_hint('e.g. 15,000'), '40000');
      await t.enterText(_hint('e.g. 30'), '150');
      await _save(t);
      expect(find.text('The commission must be between 0 and 100 percent.'), findsOneWidget);
      expect(_api.posts.where(((String, Map<String, dynamic>) p) => p.$1 == '/inventory/products'), isEmpty);
    });

    testWidgets('who can do it and the other prices are sent with the service', (t) async {
      await _open(t);
      await t.enterText(_hint('e.g. Braids (long)'), 'Braids');
      await t.enterText(_hint('e.g. 15,000'), '40000');
      await t.tap(_key('service_staff_u-bahati'));
      await t.pump();
      await t.tap(_key('service_option_add'));
      await t.pump();
      await t.tap(_key('service_option_add'));
      await t.pump();
      await t.enterText(_hint('e.g. Long').first, 'Short');
      await t.enterText(find.byWidgetPredicate((Widget w) => w is TextField && w.decoration?.hintText == '60,000').first, '30000');
      await t.enterText(_hint('e.g. Long').last, 'Long');
      await t.enterText(find.byWidgetPredicate((Widget w) => w is TextField && w.decoration?.hintText == '60,000').last, '60000');
      await _save(t);

      final Map<String, dynamic> body = _api.posts.firstWhere(((String, Map<String, dynamic>) p) => p.$1 == '/inventory/products').$2;
      expect(body['staff_ids'], <String>['u-bahati']);
      expect(body['price_options'], <Map<String, dynamic>>[
        <String, dynamic>{'label': 'Short', 'price': 30000.0},
        <String, dynamic>{'label': 'Long', 'price': 60000.0},
      ]);
    });

    testWidgets('nobody chosen and no other prices send neither', (t) async {
      await _open(t);
      await t.enterText(_hint('e.g. Braids (long)'), 'Wash');
      await t.enterText(_hint('e.g. 15,000'), '5000');
      await _save(t);

      final Map<String, dynamic> body = _api.posts.firstWhere(((String, Map<String, dynamic>) p) => p.$1 == '/inventory/products').$2;
      expect(body.containsKey('staff_ids'), isFalse);
      expect(body.containsKey('price_options'), isFalse);
    });

    testWidgets('an empty row of other prices is ignored, a half-filled one is refused', (t) async {
      await _open(t);
      await t.enterText(_hint('e.g. Braids (long)'), 'Braids');
      await t.enterText(_hint('e.g. 15,000'), '40000');
      await t.tap(_key('service_option_add'));
      await t.pump();
      await _save(t);
      final Map<String, dynamic> body = _api.posts.firstWhere(((String, Map<String, dynamic>) p) => p.$1 == '/inventory/products').$2;
      expect(body.containsKey('price_options'), isFalse, reason: 'the empty row was ignored');

      _api.posts.clear();
      await _open(t);
      await t.enterText(_hint('e.g. Braids (long)'), 'Braids');
      await t.enterText(_hint('e.g. 15,000'), '40000');
      await t.tap(_key('service_option_add'));
      await t.pump();
      await t.enterText(_hint('e.g. Long'), 'Long');
      await _save(t);
      expect(find.text('Each other price needs a name (e.g. Long) and a price.'), findsOneWidget);
      expect(_api.posts.where(((String, Map<String, dynamic>) p) => p.$1 == '/inventory/products'), isEmpty);
    });

    testWidgets('the time and the wait are optional', (t) async {
      await _open(t);
      await t.enterText(_hint('e.g. Braids (long)'), 'Wash');
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
      await _goodsOn(t);
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
        await t.enterText(_hint('e.g. Braids (long)'), 'Braids');
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

    testWidgets('a service comes back with its people ticked and its other prices listed, and saving keeps them', (t) async {
      final InvProduct p = _braids()
        ..staffIds = <String>['u-asha']
        ..priceOptions = <PriceOption>[const PriceOption(label: 'Long', price: 60000)];
      await _open(t, product: p);

      expect(t.widget<FilterChip>(_key('service_staff_u-asha')).selected, isTrue);
      expect(t.widget<FilterChip>(_key('service_staff_u-bahati')).selected, isFalse);
      expect(_typed(t, _hint('e.g. Long')), 'Long');
      expect(_typed(t, _hint('60,000')), '60,000');

      await _save(t);
      final Map<String, dynamic> body = _api.puts.single.$2;
      expect(body['staff_ids'], <String>['u-asha']);
      expect((body['price_options'] as List<dynamic>).single, <String, dynamic>{'label': 'Long', 'price': 60000.0});
    });

    testWidgets('taking everyone off and every other price away sends empty lists, which clear them on the server', (t) async {
      final InvProduct p = _braids()
        ..staffIds = <String>['u-asha']
        ..priceOptions = <PriceOption>[const PriceOption(label: 'Long', price: 60000)];
      await _open(t, product: p);
      await t.tap(_key('service_staff_u-asha'));
      await t.pump();
      await t.tap(_key('service_option_remove_0'));
      await t.pump();

      await _save(t);

      final Map<String, dynamic> body = _api.puts.single.$2;
      expect(body['staff_ids'], isEmpty);
      expect(body['price_options'], isEmpty);
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

  group('packages', () {
    testWidgets('a package must name a service and have at least two visits before it is saved', (t) async {
      await _open(t);
      await _serviceOn(t);
      await t.enterText(_hint('e.g. Braids (long)'), 'Braids x5');
      await t.enterText(_hint('e.g. 15,000'), '150000');
      await t.tap(_key('service_is_package'));
      await t.pump();
      expect(_key('package_service'), findsOneWidget);
      await t.enterText(_hint('e.g. 5'), '1');
      await _save(t);

      expect(_api.posts.where((e) => e.$1 == '/inventory/products'), isEmpty, reason: 'nothing is saved');
      expect(find.text('A package needs a service and 2 or more visits.'), findsNothing, reason: 'the banner has gone by now');
    });

    testWidgets('editing a package keeps its visits and service and sends them back', (t) async {
      final InvProduct p = _braids()
        ..packageSessions = 5
        ..packageServiceId = 3
        ..packageValidDays = 90;
      await _open(t, product: p);
      expect(t.widget<Switch>(_key('service_is_package')).value, isTrue);
      expect(_typed(t, _hint('e.g. 5')), '5');
      expect(_typed(t, _hint('e.g. 90')), '90');

      await _save(t);
      final Map<String, dynamic> sent = _api.puts.firstWhere((e) => e.$1 == '/inventory/products/9').$2;
      expect(sent['package_sessions'], 5);
      expect(sent['package_service_id'], 3);
      expect(sent['package_valid_days'], 90);
    });

    testWidgets('an ordinary service sends no package, and turning the switch off clears it', (t) async {
      final InvProduct p = _braids()
        ..packageSessions = 5
        ..packageServiceId = 3;
      await _open(t, product: p);
      await t.tap(_key('service_is_package'));
      await t.pump();
      await _save(t);
      final Map<String, dynamic> sent = _api.puts.firstWhere((e) => e.$1 == '/inventory/products/9').$2;
      expect(sent['package_sessions'], isNull);
      expect(sent['package_service_id'], isNull);
    });
  });
}
