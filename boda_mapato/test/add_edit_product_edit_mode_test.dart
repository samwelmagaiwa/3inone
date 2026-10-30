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

/// Canned answers instead of a server. Remembers every change the page asks for.
class _FakeApi extends ApiService {
  _FakeApi(this.settings, {this.family = const <Map<String, dynamic>>[]});

  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> family;
  final List<(String, Map<String, dynamic>)> puts = <(String, Map<String, dynamic>)>[];
  final List<(String, Map<String, dynamic>)> posts = <(String, Map<String, dynamic>)>[];

  Map<String, dynamic> unit(int id, String name, int factor, {bool base = false}) =>
      <String, dynamic>{'id': id, 'product_id': 2, 'name': name, 'factor': factor, 'is_base': base, 'status': 'active', 'prices': <dynamic>[]};

  @override
  Future<Map<String, dynamic>> put(String endpoint, Map<String, dynamic> data) async {
    puts.add((endpoint, data));
    return <String, dynamic>{'data': <String, dynamic>{'id': 2}};
  }

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data, {bool requireAuth = true}) async {
    posts.add((endpoint, data));
    return <String, dynamic>{'data': <String, dynamic>{'id': 2}};
  }

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) return <String, dynamic>{'data': settings};
    if (endpoint.contains('family_id=')) return <String, dynamic>{'data': family};
    if (endpoint.endsWith('/units')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[unit(20, 'g', 1, base: true), unit(21, 'kg', 1000), unit(22, 'sack', 50000)],
      };
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }
}

const Map<String, dynamic> _retailShop = <String, dynamic>{
  'inventory_type': 'retail',
  'use_crates': '0',
  'sale_tier': 'retail',
  'prices_include_vat': '1',
  'tax_percent': '18',
};

InvProduct _sugar({double? tax = 16, int quantity = 5500}) => InvProduct(
      id: 2,
      name: 'Sugar',
      sku: 'SUG-1',
      category: '',
      costPrice: 1.5,
      sellingPrice: 2.2,
      unit: 'g',
      quantity: quantity,
      minStock: 1000,
      status: 'active',
      barcode: 'SUG-1',
      createdBy: 1,
      measure: 'weight',
      taxPercent: tax,
    );

InvProduct _shirt({int id = 2, String label = 'M'}) => InvProduct(
      id: id,
      name: 'Shirt — $label',
      sku: 'SH-$label',
      category: '',
      costPrice: 8000,
      sellingPrice: 12000,
      unit: 'pcs',
      quantity: 4,
      minStock: 1,
      status: 'active',
      barcode: 'SH-$label',
      createdBy: 1,
      familyId: 2,
      variantLabel: label,
    );

late _FakeApi _api;

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

Future<void> _open(WidgetTester t, InvProduct product,
    {Map<String, dynamic> settings = _retailShop, bool settingsFirst = true, List<Map<String, dynamic>> family = const <Map<String, dynamic>>[]}) async {
  _ignoreTestFontOverflow();
  _api = _FakeApi(settings, family: family);
  t.view.physicalSize = const Size(800, 6000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final InventoryProvider inv = InventoryProvider(api: _api);
  // The products list is normally opened after the home screen has read the settings.
  if (settingsFirst) await inv.fetchCapabilities();
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

void main() {
  group('changing how an existing item is measured (it was kg, make it pieces)', () {
    late bool wasSwahili;
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      wasSwahili = LocalizationService.instance.isSwahili;
      await LocalizationService.instance.changeLanguage('en');
    });
    tearDown(() => LocalizationService.instance.changeLanguage(wasSwahili ? 'sw' : 'en'));

    testWidgets('choosing another measure explains what happens, and the unit picker for it appears', (t) async {
      await _open(t, _sugar(quantity: 0));
      expect(_key('measure_change_note'), findsNothing);

      await t.tap(_key('measure_count'));
      await t.pump();

      expect(_key('measure_change_note'), findsOneWidget);
      expect(find.textContaining('Its stock must be 0'), findsOneWidget);
      expect(find.text('Counted in'), findsOneWidget, reason: 'by count it needs a label: pcs, pack, box ...');
    });

    testWidgets('with no stock the change is sent: the new measure and its label', (t) async {
      await _open(t, _sugar(quantity: 0));

      await t.tap(_key('measure_count'));
      await t.pump();
      await _save(t);

      final Map<String, dynamic> body = _api.puts.single.$2;
      expect(body['measure'], 'count');
      expect(body['unit'], 'pcs');
    });

    testWidgets('with stock held it is refused on the page, with the reason, and nothing is sent', (t) async {
      await _open(t, _sugar());

      await t.tap(_key('measure_count'));
      await t.pump();
      await _save(t);

      expect(_api.puts, isEmpty);
      expect(find.textContaining('It still has stock (5500)'), findsWidgets);
    });

    testWidgets('a size or colour of a product cannot change how it is measured', (t) async {
      await _open(t, _shirt());

      expect(t.widget<ChoiceChip>(_key('measure_weight')).onSelected, isNull);
    });
  });

  group('editing goods by weight', () {
    testWidgets('prices show per kg while they are stored per gram, and stock stays in grams', (t) async {
      await _open(t, _sugar());

      expect(_typed(t, _hint('e.g. 20,000')), '1,500', reason: '1.5 a gram is 1,500 a kg');
      expect(_typed(t, _hint('e.g. 25,000')), '2,200');
      expect(_typed(t, _hint('e.g. 100')), '5500', reason: 'stock is whole grams');
      expect(t.widget<ChoiceChip>(_key('measure_weight')).selected, isTrue);
      expect(t.widget<ChoiceChip>(_key('measure_count')).onSelected, isNotNull, reason: 'an existing item may be measured differently (the server decides when)');
    });

    testWidgets('saving without a change sends the same per-gram prices back', (t) async {
      await _open(t, _sugar());
      await _save(t);

      final Map<String, dynamic> body = _api.puts.single.$2;
      expect(body.containsKey('measure'), isFalse, reason: 'the measure is sent only when it was changed');
      expect(_api.puts.single.$1, '/inventory/products/2');
      expect(body['cost_price'], 1.5);
      expect(body['selling_price'], 2.2);
      expect(body['quantity'], 5500);
      expect(body['unit'], 'g');
      expect(body['tax_percent'], 16);
    });

    testWidgets('the new per-kg price also lands on the kg selling unit', (t) async {
      await _open(t, _sugar());
      await t.enterText(_hint('e.g. 25,000'), '2400');
      await _save(t);

      expect(_api.puts.single.$2['selling_price'], 2.4);
      final (String, Map<String, dynamic>) unitPrice = _api.posts.firstWhere(((String, Map<String, dynamic>) p) => p.$1.endsWith('/units/21/price'));
      expect(unitPrice.$2['tier'], 'retail');
      expect(unitPrice.$2['price'], 2400);
    });

    testWidgets('prices are converted even when the settings arrive after the page has opened', (t) async {
      await _open(t, _sugar(), settingsFirst: false);
      // The page opened as if for a depot; once the settings came in, it showed per-kg prices.
      expect(_typed(t, _hint('e.g. 25,000')), '2,200');
      await _save(t);
      expect(_api.puts.single.$2['selling_price'], 2.2, reason: 'not 2.2 divided by a thousand again');
    });
  });

  group('editing VAT', () {
    testWidgets('the product\'s own rate is shown, and clearing it puts it back to the business default', (t) async {
      await _open(t, _sugar(tax: 16));
      await t.tap(_key('vat_section'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(_typed(t, _key('vat_field')), '16');

      await t.enterText(_key('vat_field'), '');
      await _save(t);

      final Map<String, dynamic> body = _api.puts.single.$2;
      expect(body.containsKey('tax_percent'), isTrue);
      expect(body['tax_percent'], isNull, reason: 'null = use the business default again');
    });

    testWidgets('a product with no rate of its own sends none', (t) async {
      await _open(t, _sugar(tax: null));
      await _save(t);
      expect(_api.puts.single.$2.containsKey('tax_percent'), isFalse);
    });
  });

  group('editing sizes and colours', () {
    testWidgets('a size shows its own label and the family it belongs to', (t) async {
      await _open(t, _shirt(), family: <Map<String, dynamic>>[
        <String, dynamic>{'id': 2, 'name': 'Shirt — M', 'sku': 'SH-M', 'cost_price': 8000, 'selling_price': 12000, 'unit': 'pcs', 'quantity': 4, 'min_stock': 1, 'status': 'active', 'variant_label': 'M', 'family_id': 2},
        <String, dynamic>{'id': 3, 'name': 'Shirt — L', 'sku': 'SH-L', 'cost_price': 8000, 'selling_price': 12000, 'unit': 'pcs', 'quantity': 9, 'min_stock': 1, 'status': 'active', 'variant_label': 'L', 'family_id': 2},
      ]);

      expect(_hint('e.g. M / Red'), findsOneWidget);
      expect(_typed(t, _hint('e.g. M / Red')), 'M');
      expect(find.text('M: 4 (hii)'), findsOneWidget);
      expect(find.text('L: 9'), findsOneWidget);
    });

    testWidgets('renaming a size sends the new label; leaving it alone sends none', (t) async {
      await _open(t, _shirt());
      await _save(t);
      expect(_api.puts.single.$2.containsKey('variant_label'), isFalse);

      await _open(t, _shirt());
      await t.enterText(_hint('e.g. M / Red'), 'Medium');
      await _save(t);
      expect(_api.puts.single.$2['variant_label'], 'Medium');
    });

    testWidgets('more sizes can be added to an existing product', (t) async {
      await _open(t, _shirt());
      await t.tap(_key('variant_add'));
      await t.pump();
      await t.enterText(_key('variant_label_0'), 'L');
      await t.enterText(_key('variant_qty_0'), '6');
      await _save(t);

      final (String, Map<String, dynamic>) added = _api.posts.firstWhere(((String, Map<String, dynamic>) p) => p.$1 == '/inventory/products/2/variants');
      final List<dynamic> variants = added.$2['variants'] as List<dynamic>;
      expect(variants, hasLength(1));
      expect((variants.single as Map<String, dynamic>)['label'], 'L');
      expect((variants.single as Map<String, dynamic>)['quantity'], 6);
    });
  });

  group('managing the selling units of an existing product', () {
    testWidgets('editing offers the full units screen instead of the quick editor', (t) async {
      await _open(t, _shirt());
      expect(_key('manage_units'), findsOneWidget);
      expect(_key('units_editor'), findsNothing);
    });
  });
}
