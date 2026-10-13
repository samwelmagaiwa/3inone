import 'package:boda_mapato/constants/theme_constants.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/products/add_edit_product_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/products/product_form_sections.dart' show ExtraOptionCard;
import 'package:boda_mapato/modules/inventory/screens/widgets/joined_sections.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Canned answers instead of a server. Remembers what the page tried to save.
class _FakeApi extends ApiService {
  _FakeApi({this.settings = const <String, dynamic>{}});

  /// What GET /inventory/settings says: the kind of business and how its inventory is set up.
  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> created = <Map<String, dynamic>>[];
  Object? postError;

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data, {bool requireAuth = true}) async {
    if (endpoint == '/inventory/products') {
      if (postError != null) throw postError!;
      created.add(data);
    }
    return <String, dynamic>{
      'data': <String, dynamic>{'id': 1}
    };
  }

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/settings')) {
      return <String, dynamic>{'data': settings};
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
const Map<String, dynamic> _wholesaler = <String, dynamic>{
  'inventory_type': 'wholesale',
  'use_crates': '0',
  'sale_tier': 'wholesale',
  'prices_include_vat': '1',
  'tax_percent': '0',
};

late _FakeApi _api;

/// Flutter's test font draws every letter as a wide square, so rows that fit on a phone "overflow" here.
/// Those warnings say nothing about the real app; every other error still fails the test.
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

Future<void> _openPage(WidgetTester t, {Map<String, dynamic> settings = const <String, dynamic>{}}) async {
  _ignoreTestFontOverflow();
  _api = _FakeApi(settings: settings);
  t.view.physicalSize = const Size(800, 6000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final InventoryProvider inv = InventoryProvider(api: _api);
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
                onPressed: () => Navigator.push<void>(ctx, MaterialPageRoute<void>(builder: (_) => const AddEditProductScreen())),
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
  // The settings arrive after the page has opened.
  await t.pump(const Duration(milliseconds: 200));
}

Future<void> _fillBasics(WidgetTester t, {String name = 'Soap', String cost = '700', String price = '1000', String? qty = '30'}) async {
  await t.enterText(_hint('e.g. Coca-Cola 350ml'), name);
  await t.enterText(_hint('e.g. 20,000'), cost);
  await t.enterText(_hint('e.g. 25,000'), price);
  if (qty != null) await t.enterText(_hint('e.g. 100'), qty);
  await t.pump();
}

Future<void> _save(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.save).first);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  // The success banner stays up for a few seconds; let it go before the test ends.
  await t.pump(const Duration(seconds: 4));
}

void main() {
  group('a depot keeps the page it has always had', () {
    testWidgets('no measure chips, no sizes and colours, but the optional VAT is there', (t) async {
      await _openPage(t);

      expect(_key('measure_count'), findsNothing);
      expect(_key('variant_toggle'), findsNothing);
      expect(_key('vat_section'), findsOneWidget);
    });

    testWidgets('saves a crate product at the wholesale level with its quantity, as before', (t) async {
      await _openPage(t);
      await _fillBasics(t, name: 'Coca-Cola', cost: '20000', price: '25000', qty: '10');
      await _save(t);

      expect(_api.created, hasLength(1));
      final Map<String, dynamic> body = _api.created.single;
      expect(body['name'], 'Coca-Cola');
      expect(body['unit'], 'crate');
      expect(body['unit_factor'], 1);
      expect(body['price_tier'], 'wholesale');
      expect(body['cost_price'], 20000);
      expect(body['selling_price'], 25000);
      expect(body['quantity'], 10);
      expect(body.containsKey('measure'), isFalse);
      expect(body.containsKey('units'), isFalse);
      expect(body.containsKey('variants'), isFalse);
      expect(body.containsKey('tax_percent'), isFalse);
      expect(body.containsKey('other_price'), isFalse);
    });
  });

  group('a retail shop', () {
    testWidgets('counts in pieces, offers weight and volume, sizes and colours, and no crate default', (t) async {
      await _openPage(t, settings: _retailShop);

      expect(_key('measure_count'), findsOneWidget);
      expect(_key('measure_weight'), findsOneWidget);
      expect(_key('measure_volume'), findsOneWidget);
      expect(_key('variant_toggle'), findsOneWidget);
      expect(_key('units_editor'), findsOneWidget);
      expect(_key('vat_section'), findsOneWidget);
    });

    testWidgets('saves a plain piece product at the retail level', (t) async {
      await _openPage(t, settings: _retailShop);
      await _fillBasics(t);
      await _save(t);

      final Map<String, dynamic> body = _api.created.single;
      expect(body['unit'], 'pcs');
      expect(body['unit_factor'], 1);
      expect(body['price_tier'], 'retail');
      expect(body['quantity'], 30);
      expect(body['quantity'], isA<int>());
      expect(body.containsKey('variants'), isFalse);
      expect(body.containsKey('units'), isFalse);
    });

    testWidgets('the stock boxes take digits only: a quantity can never be a fraction', (t) async {
      await _openPage(t, settings: _retailShop);
      await t.enterText(_hint('e.g. 100'), '2.5');
      await t.pump();

      final TextField qty = t.widget<TextField>(_hint('e.g. 100'));
      expect(qty.controller!.text, '25', reason: 'the dot is filtered out as it is typed');
    });

    testWidgets('an extra way to sell it (carton) is saved with its size and price', (t) async {
      await _openPage(t, settings: _retailShop);
      await _fillBasics(t);
      await t.tap(_key('unit_add'));
      await t.pump();
      await t.enterText(_key('unit_row_name_0'), 'carton');
      await t.enterText(_key('unit_row_factor_0'), '24');
      await t.enterText(_key('unit_row_retail_0'), '22000');
      await _save(t);

      final List<dynamic> units = _api.created.single['units'] as List<dynamic>;
      expect(units, hasLength(1));
      expect((units.single as Map<String, dynamic>)['name'], 'carton');
      expect((units.single as Map<String, dynamic>)['factor'], 24);
      expect((units.single as Map<String, dynamic>)['retail_price'], 22000);
      expect((units.single as Map<String, dynamic>).containsKey('wholesale_price'), isFalse,
          reason: 'a retail business is not asked for a wholesale price');
    });

    testWidgets('a half-filled selling unit stops the save and says why', (t) async {
      await _openPage(t, settings: _retailShop);
      await _fillBasics(t);
      await t.tap(_key('unit_add'));
      await t.pump();
      await t.enterText(_key('unit_row_name_0'), 'carton');
      await _save(t);

      expect(_api.created, isEmpty);
      expect(_key('product_save_error'), findsOneWidget);
    });

    testWidgets('sizes and colours become separate stock items and the single-item boxes go away', (t) async {
      await _openPage(t, settings: _retailShop);
      await _fillBasics(t, name: 'Shirt', qty: '99');
      await t.tap(_key('variant_toggle'));
      await t.pump();
      expect(_hint('e.g. 100'), findsNothing, reason: 'each size carries its own stock');

      await t.enterText(_key('variant_label_0'), 'M / Red');
      await t.enterText(_key('variant_qty_0'), '5');
      await t.tap(_key('variant_add'));
      await t.pump();
      await t.enterText(_key('variant_label_1'), 'L / Red');
      await t.enterText(_key('variant_qty_1'), '7');
      await t.enterText(_key('variant_price_1'), '15000');
      await _save(t);

      final Map<String, dynamic> body = _api.created.single;
      expect(body['quantity'], 0);
      final List<dynamic> variants = body['variants'] as List<dynamic>;
      expect(variants, hasLength(2));
      expect((variants[0] as Map<String, dynamic>)['label'], 'M / Red');
      expect((variants[0] as Map<String, dynamic>)['quantity'], 5);
      expect((variants[0] as Map<String, dynamic>).containsKey('selling_price'), isFalse);
      expect((variants[1] as Map<String, dynamic>)['label'], 'L / Red');
      expect((variants[1] as Map<String, dynamic>)['selling_price'], 15000);
    });

    testWidgets('a size with no name stops the save', (t) async {
      await _openPage(t, settings: _retailShop);
      await _fillBasics(t, name: 'Shirt', qty: null);
      await t.tap(_key('variant_toggle'));
      await t.pump();
      await t.enterText(_key('variant_qty_0'), '5');
      await _save(t);

      expect(_api.created, isEmpty);
      expect(_key('product_save_error'), findsOneWidget);
    });

    testWidgets('turning sizes on and adding none is not saved', (t) async {
      await _openPage(t, settings: _retailShop);
      await _fillBasics(t, name: 'Shirt', qty: null);
      await t.tap(_key('variant_toggle'));
      await t.pump();
      await _save(t);

      expect(_api.created, isEmpty);
      expect(_key('product_save_error'), findsOneWidget);
    });

    testWidgets('VAT is optional: left alone, no rate is sent (the business default applies)', (t) async {
      await _openPage(t, settings: _retailShop);
      await _fillBasics(t);
      await _save(t);
      expect(_api.created.single.containsKey('tax_percent'), isFalse);
    });

    testWidgets('a VAT rate typed for the product is sent, and 0 means exempt', (t) async {
      await _openPage(t, settings: _retailShop);
      await _fillBasics(t, name: 'Bread');
      await t.tap(_key('vat_section'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(_key('vat_field'), '0');
      await _save(t);

      expect(_api.created.single['tax_percent'], 0, reason: '0 is exempt, which is different from blank (business default)');
    });

    testWidgets('a VAT rate outside 0..100 is refused', (t) async {
      await _openPage(t, settings: _retailShop);
      await _fillBasics(t);
      await t.tap(_key('vat_section'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(_key('vat_field'), '180');
      await _save(t);

      expect(_api.created, isEmpty);
      expect(_key('product_save_error'), findsOneWidget);
    });

    testWidgets('the server\'s own reason is shown when it refuses', (t) async {
      await _openPage(t, settings: _retailShop);
      _api.postError = ApiException('That SKU is already used in this business');
      await _fillBasics(t);
      await _save(t);

      expect(find.text('That SKU is already used in this business'), findsWidgets);
      expect(_key('product_save_error'), findsOneWidget);
    });
  });

  group('goods sold by weight', () {
    testWidgets('are priced per kg, counted in grams and saved as whole numbers', (t) async {
      await _openPage(t, settings: _retailShop);
      await t.tap(_key('measure_weight'));
      await t.pump();
      expect(_key('variant_toggle'), findsNothing, reason: 'sizes and colours are for counted goods');
      expect(find.textContaining('Hakuna desimali'), findsOneWidget);

      await _fillBasics(t, name: 'Sugar', cost: '1500', price: '2200', qty: '5');
      await t.tap(_key('stock_unit_1000'));
      await t.pump();
      await _save(t);

      final Map<String, dynamic> body = _api.created.single;
      expect(body['measure'], 'weight');
      expect(body['unit'], 'g');
      expect(body['unit_factor'], 1);
      expect(body['quantity'], 5000, reason: '5 kg is 5,000 g');
      expect(body['cost_price'], 1.5);
      expect(body['selling_price'], 2.2);
      final List<dynamic> units = body['units'] as List<dynamic>;
      expect((units.single as Map<String, dynamic>)['name'], 'kg');
      expect((units.single as Map<String, dynamic>)['factor'], 1000);
      expect((units.single as Map<String, dynamic>)['retail_price'], 2200);
    });

    testWidgets('the g | kg choice sits right under "How is it sold?", before the unit, price and stock fields', (t) async {
      await _openPage(t, settings: _retailShop);
      await t.tap(_key('measure_weight'));
      await t.pump();

      final Rect lowestMeasure = <String>['measure_count', 'measure_weight', 'measure_volume']
          .map((String k) => t.getRect(_key(k)))
          .reduce((Rect a, Rect b) => a.bottom > b.bottom ? a : b);
      expect(_key('stock_unit_1'), findsOneWidget);
      expect(_key('stock_unit_1000'), findsOneWidget);
      final Rect grams = t.getRect(_key('stock_unit_1'));
      final Rect kilos = t.getRect(_key('stock_unit_1000'));

      // The three choices are followed by one line saying what the choice means; the g | kg chips come after it.
      final Rect explanation = t.getRect(find.byWidgetPredicate(
          (Widget w) => w is Text && RegExp('No decimals|Hakuna desimali').hasMatch(w.data ?? '')));
      expect(explanation.top, greaterThanOrEqualTo(lowestMeasure.bottom - 1), reason: 'the explanation is under the choices');
      expect(grams.top, greaterThanOrEqualTo(explanation.bottom), reason: 'below the three choices and what they mean');
      expect(grams.top - explanation.bottom, lessThan(24), reason: 'directly after them, no other field in between');
      expect(kilos.top, grams.top, reason: 'g and kg are one row');
      expect(grams.left, lessThan(kilos.left));
      expect(grams.bottom, lessThanOrEqualTo(t.getTopLeft(_hint('e.g. 20,000')).dy), reason: 'above the cost price');
      expect(grams.bottom, lessThanOrEqualTo(t.getTopLeft(_hint('e.g. 100')).dy), reason: 'above the quantity it chooses the unit of');
    });

    testWidgets('litres: the ml | litre choice is under the three choices too, and only there', (t) async {
      await _openPage(t, settings: _retailShop);
      await t.tap(_key('measure_volume'));
      await t.pump();

      expect(_key('stock_unit_1'), findsOneWidget, reason: 'one set of chips, not one under the choices and one under the stock');
      expect(_key('stock_unit_1000'), findsOneWidget);
      expect(t.getTopLeft(_key('stock_unit_1')).dy, lessThan(t.getTopLeft(_hint('e.g. 100')).dy));
      expect(t.getTopLeft(_key('stock_unit_1')).dy, greaterThan(t.getRect(_key('measure_volume')).bottom - 1));
    });

    testWidgets('counted goods have no g | kg choice', (t) async {
      await _openPage(t, settings: _retailShop);

      expect(_key('stock_unit_1'), findsNothing);
      expect(_key('stock_unit_1000'), findsNothing);
    });

    testWidgets('stock typed in grams stays in grams', (t) async {
      await _openPage(t, settings: _retailShop);
      await t.tap(_key('measure_weight'));
      await t.pump();
      await _fillBasics(t, name: 'Sugar', cost: '1500', price: '2200', qty: '750');
      await _save(t);

      expect(_api.created.single['quantity'], 750);
    });

    testWidgets('goods by volume are kept in millilitres and sold by the litre', (t) async {
      await _openPage(t, settings: _retailShop);
      await t.tap(_key('measure_volume'));
      await t.pump();
      await _fillBasics(t, name: 'Cooking oil', cost: '4000', price: '5000', qty: '20');
      await t.tap(_key('stock_unit_1000'));
      await t.pump();
      await _save(t);

      final Map<String, dynamic> body = _api.created.single;
      expect(body['measure'], 'volume');
      expect(body['unit'], 'ml');
      expect(body['quantity'], 20000);
      expect((body['units'] as List<dynamic>).single['name'], 'litre');
    });
  });

  group('a wholesaler', () {
    testWidgets('prices at the wholesale level and can add a retail price for the same unit', (t) async {
      await _openPage(t, settings: _wholesaler);
      await _fillBasics(t, name: 'Rice 25kg', cost: '40000', price: '48000', qty: '40');
      await t.enterText(_hint('e.g. 22,000'), '52000');
      await _save(t);

      final Map<String, dynamic> body = _api.created.single;
      expect(body['price_tier'], 'wholesale');
      expect(body['selling_price'], 48000);
      expect(body['other_price'], 52000);
      expect(body['unit'], 'pcs', reason: 'no crate default for a business without returnable packaging');
    });

    testWidgets('a retail shop is not offered a second price level', (t) async {
      await _openPage(t, settings: _retailShop);
      expect(_hint('e.g. 22,000'), findsNothing);
    });

    testWidgets('selling units show the wholesale price column', (t) async {
      await _openPage(t, settings: _wholesaler);
      await t.tap(_key('unit_add'));
      await t.pump();
      expect(_key('unit_row_wholesale_0'), findsOneWidget);
    });
  });

  group('the page is one joined card, told apart by divider lines', () {
    const List<String> retailSections = <String>['details', 'pricing', 'extras', 'barcode'];
    Finder section(String id) => _key('product_section_$id');
    Finder inside(String id, Finder f) => find.descendant(of: section(id), matching: f);

    /// The section dividers (the full-width glowing lines), top to bottom.
    final Finder dividerFinder = find.byWidgetPredicate(
        (Widget w) => w is SectionGlowDivider && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('product_section_divider_'));
    List<double> dividerTops(WidgetTester t) =>
        dividerFinder.evaluate().map((Element e) => (e.renderObject! as RenderBox).localToGlobal(Offset.zero).dy).toList()..sort();

    testWidgets('a retail shop gets details, pricing, extras and barcode, in that order', (t) async {
      await _openPage(t, settings: _retailShop);

      double previousTop = -1;
      for (final String id in retailSections) {
        expect(section(id), findsOneWidget, reason: id);
        final double top = t.getTopLeft(section(id)).dy;
        expect(top, greaterThan(previousTop), reason: '$id comes after the section before it');
        previousTop = top;
      }
      expect(section('depot_units'), findsNothing);
    });

    testWidgets('the sections are joined: no gap, no box of their own, one hairline between each pair', (t) async {
      await _openPage(t, settings: _retailShop);

      final List<double> dividers = dividerTops(t);
      expect(dividers, hasLength(retailSections.length - 1), reason: 'one divider between each pair of sections');

      for (int i = 0; i < retailSections.length - 1; i++) {
        final double bottom = t.getBottomLeft(section(retailSections[i])).dy;
        final double nextTop = t.getTopLeft(section(retailSections[i + 1])).dy;
        // The divider sits exactly between the two: the sections touch it, with no gap of page background.
        expect(dividers[i], closeTo(bottom, 1.0), reason: '${retailSections[i]} ends where its divider is');
        expect(nextTop, closeTo(dividers[i] + 1, 1.5), reason: '${retailSections[i + 1]} starts right under it');
      }

      // Nothing is drawn around a section on its own.
      for (final String id in retailSections) {
        expect(t.widget(section(id)), isA<Padding>(), reason: '$id is just padding, not a card');
      }
    });

    testWidgets('all sections live in ONE glass card', (t) async {
      await _openPage(t, settings: _retailShop);

      final Finder card = _key('product_card');
      expect(card, findsOneWidget, reason: 'one glass card around the sections');
      for (final String id in retailSections) {
        expect(find.descendant(of: card, matching: section(id)), findsOneWidget, reason: '$id is inside that same card');
      }
      expect(find.byKey(const ValueKey<String>('product_section_pricing')), findsOneWidget);
    });

    testWidgets('the card is the Depot settings card: glass fill, 20 radius, cyan edge and glow', (t) async {
      await _openPage(t, settings: _retailShop);

      final Container card = t.widget<Container>(_key('product_card'));
      final BoxDecoration d = card.decoration! as BoxDecoration;
      expect(d.color, ThemeConstants.cardColor, reason: 'the same glass fill as the Settings cards');
      expect(d.gradient, isNull, reason: 'no separate sheen: the fill is the Settings colour');
      expect(d.borderRadius, BorderRadius.circular(20));
      expect(d, joinedCardDecoration(), reason: 'built by the same helper Depot settings uses, so the two cannot drift apart');

      final BoxDecoration edge = card.foregroundDecoration! as BoxDecoration;
      expect(edge, joinedCardBorder());
      final Border border = edge.border! as Border;
      expect(border.top.color.b, greaterThan(border.top.color.r), reason: 'the edge is cyan, not white');
      expect(border.top.width, 1.8);
    });

    testWidgets('the glow is cyan: a bright one at the top edge and a wider one around the card', (t) async {
      await _openPage(t, settings: _retailShop);

      final BoxDecoration d = t.widget<Container>(_key('product_card')).decoration! as BoxDecoration;
      final List<BoxShadow> cyan = d.boxShadow!.where((BoxShadow b) => b.color.b > b.color.r).toList();
      expect(cyan.length, greaterThanOrEqualTo(2));
      expect(cyan.every((BoxShadow b) => b.color.a >= 0.15), isTrue, reason: 'visible glows, not hints');
    });

    testWidgets('there is room around the card for its shadow to be seen at the sides and underneath', (t) async {
      await _openPage(t, settings: _retailShop);

      final Rect card = t.getRect(_key('product_card'));
      final Size screen = t.getSize(find.byType(Scaffold).first);
      expect(card.left, greaterThanOrEqualTo(8), reason: 'a gutter on the left');
      expect(screen.width - card.right, greaterThanOrEqualTo(8), reason: 'a gutter on the right');
    });

    testWidgets('the page background is the same flat dark teal as Settings', (t) async {
      await _openPage(t, settings: _retailShop);

      expect(find.byWidgetPredicate((Widget w) => w is ColoredBox && w.color == ThemeConstants.primaryBlue), findsWidgets);
    });

    testWidgets('fields wear the Depot settings teal fill and border', (t) async {
      await _openPage(t, settings: _retailShop);

      final InputDecoration name = t.widget<TextField>(_hint('e.g. Coca-Cola 350ml')).decoration!;
      expect(name.fillColor, ThemeConstants.invFill);
      final OutlineInputBorder border = name.enabledBorder! as OutlineInputBorder;
      expect(border.borderSide.color, ThemeConstants.invBorder);
    });

    testWidgets('fields side by side are split by a glowing vertical line, in the gap between them', (t) async {
      await _openPage(t, settings: _retailShop);

      final Finder lines = find.byKey(const ValueKey<String>('product_col_divider'));
      expect(find.byType(SectionGlowVerticalDivider), findsNWidgets(5), reason: 'the lines are the glowing ones');
      // name | SKU, category | brand, cost | price, stock | alert threshold, barcode | status  (nothing beside the QR code)
      expect(lines, findsNWidgets(5));
      expect(inside('details', lines), findsOneWidget);
      expect(inside('pricing', lines), findsNWidgets(3));
      expect(inside('barcode', lines), findsOneWidget);

      // The line in the details row sits between the name field and the SKU field, not on top of either.
      final Rect nameBox = t.getRect(_hint('e.g. Coca-Cola 350ml'));
      final Rect skuBox = t.getRect(_hint('e.g. COC-8429'));
      final double x = t.getCenter(inside('details', lines)).dx;
      expect(x, greaterThan(nameBox.right));
      expect(x, lessThan(skuBox.left));
      // ... and runs the whole height of the row.
      expect(t.getSize(inside('details', lines)).height, greaterThanOrEqualTo(nameBox.height));
    });

    testWidgets('each field sits in the section it belongs to', (t) async {
      await _openPage(t, settings: _retailShop);

      expect(inside('details', _hint('e.g. Coca-Cola 350ml')), findsOneWidget);
      expect(inside('pricing', _hint('e.g. 20,000')), findsOneWidget);
      expect(inside('pricing', _hint('e.g. 25,000')), findsOneWidget);
      expect(inside('pricing', _hint('e.g. 100')), findsOneWidget);
      expect(inside('barcode', find.byType(Switch)), findsOneWidget, reason: 'the status switch');
      expect(inside('extras', _key('units_editor')), findsOneWidget);
      expect(inside('extras', _key('variant_toggle')), findsOneWidget);
      expect(inside('extras', _key('vat_section')), findsOneWidget);
    });

    testWidgets('there is no "Created by" box any more: no section, no label, no read-only name field', (t) async {
      await _openPage(t, settings: _retailShop);

      expect(section('created_by'), findsNothing);
      expect(find.byKey(const ValueKey<String>('product_section_divider_created_by')), findsNothing);
      expect(find.byIcon(Icons.person_outline), findsNothing, reason: 'the name field had a person icon');
      expect(find.text(LocalizationService.instance.translate('created_by')), findsNothing);
    });

    testWidgets('and the same for a depot', (t) async {
      await _openPage(t);

      expect(section('created_by'), findsNothing);
      expect(find.byIcon(Icons.person_outline), findsNothing);
    });

    testWidgets('the save request names no creator: the server records the signed-in user', (t) async {
      await _openPage(t, settings: _retailShop);
      await _fillBasics(t, name: 'Soap', cost: '700', price: '1000', qty: '30');
      await _save(t);

      final Map<String, dynamic> body = _api.created.single;
      expect(body.keys.where((String k) => k.contains('created') || k.contains('user')), isEmpty,
          reason: 'nothing about who is sending it: the token says');
    });

    testWidgets('Barcode & status is the last section, and the QR code is the last field in it', (t) async {
      await _openPage(t, settings: _retailShop);

      // the section: last of all
      for (final String id in retailSections.where((String s) => s != 'barcode')) {
        expect(t.getTopLeft(section('barcode')).dy, greaterThan(t.getTopLeft(section(id)).dy), reason: 'below the $id section');
      }
      // its fields: the barcode and the status, then the QR code under them
      final Finder qr = _key('qr_preview');
      expect(inside('barcode', qr), findsOneWidget, reason: 'the QR code stays with its barcode');
      expect(inside('barcode', find.byType(Switch)), findsOneWidget, reason: 'the status switch');
      final Rect barcodeField = t.getRect(inside('barcode', find.byType(TextField)).first);
      expect(t.getTopLeft(qr).dy, greaterThanOrEqualTo(barcodeField.bottom), reason: 'the QR code is under the barcode box');
      // ... and the QR code is the last thing in the card
      expect(t.getRect(_key('product_card')).bottom - t.getRect(qr).bottom, lessThan(40));
    });

    testWidgets('while sizes / colours each carry their own barcode there is no QR code', (t) async {
      await _openPage(t, settings: _retailShop);
      expect(_key('qr_preview'), findsOneWidget);

      await t.tap(_key('variant_toggle'));
      await t.pump();
      expect(_key('qr_preview'), findsNothing);
    });

    testWidgets('the extras are three cards, in order, under a line saying they can be skipped', (t) async {
      await _openPage(t, settings: _retailShop);

      expect(inside('extras', _key('extras_hint')), findsOneWidget);
      expect(find.byType(ExtraOptionCard), findsNWidgets(2), reason: 'packs, and sizes / colours; the VAT card shares their look');
      final double hint = t.getTopLeft(_key('extras_hint')).dy;
      final double packs = t.getTopLeft(_key('units_editor')).dy;
      final double sizes = t.getTopLeft(_key('variants_editor')).dy;
      final double vat = t.getTopLeft(_key('vat_section')).dy;
      expect(hint < packs && packs < sizes && sizes < vat, isTrue, reason: 'hint, packs, sizes / colours, VAT from top to bottom');
      // cards are separated by a gap, the page's section lines stay between sections
      expect(t.getRect(_key('vat_section')).top - t.getRect(_key('variants_editor')).bottom, greaterThan(4));
    });

    testWidgets('a depot\'s extras are what they were: no hint, no cards, the plain VAT row', (t) async {
      await _openPage(t);

      expect(_key('extras_hint'), findsNothing);
      expect(find.byType(ExtraOptionCard), findsNothing);
      expect(find.textContaining('own VAT rate'), findsNothing);
      expect(_key('vat_section'), findsOneWidget);
    });

    testWidgets('a depot in retail mode keeps its compact packs section too', (t) async {
      await _openPage(t);
      await t.tap(find.byType(Switch).first);
      await t.pump();

      expect(_key('units_editor'), findsOneWidget);
      expect(find.byType(ExtraOptionCard), findsNothing, reason: 'the depot does not get the guided cards');
    });

    testWidgets('a depot keeps its mode banner as the first row; retail mode adds the packs section', (t) async {
      await _openPage(t);

      for (final String id in retailSections) {
        expect(section(id), findsOneWidget, reason: id);
      }
      expect(section('depot_units'), findsNothing, reason: 'wholesale mode has no packs');
      expect(inside('extras', _key('vat_section')), findsOneWidget);
      // Every row of two fields has its vertical line, the depot's unit | quantity-per-unit row included.
      final Finder lines = find.byKey(const ValueKey<String>('product_col_divider'));
      expect(inside('pricing', lines), findsNWidgets(4), reason: 'category|brand, unit|qty per unit, cost|price, stock|alert');
      final Rect unitBox = t.getRect(find.byType(DropdownButton<String>).first);
      final Rect factorBox = t.getRect(_hint('e.g. 1'));
      final double unitLineX = List<double>.generate(4, (int i) => t.getCenter(inside('pricing', lines).at(i)).dx)
          .firstWhere((double x) => x > unitBox.right - 1 && x < factorBox.left + 1, orElse: () => -1);
      expect(unitLineX, isNot(-1), reason: 'a line sits between the unit box and the quantity-per-unit box');
      // The banner is above the details, with a divider under it.
      expect(dividerTops(t), hasLength(retailSections.length), reason: 'one more divider: under the banner');
      expect(dividerTops(t).first, lessThan(t.getTopLeft(section('details')).dy));

      // The mode switch is the first one on the page.
      await t.tap(find.byType(Switch).first);
      await t.pump();
      expect(section('depot_units'), findsOneWidget, reason: 'retail mode: the real selling units');
      expect(inside('depot_units', _key('units_editor')), findsOneWidget);
      expect(dividerTops(t), hasLength(retailSections.length + 1));
      // ... and it sits between the details and the pricing.
      expect(t.getTopLeft(section('depot_units')).dy, greaterThan(t.getTopLeft(section('details')).dy));
      expect(t.getTopLeft(section('depot_units')).dy, lessThan(t.getTopLeft(section('pricing')).dy));
    });
  });

  group('the stock box says what it counts in', () {
    testWidgets('a retail shop counts in pieces', (t) async {
      await _openPage(t, settings: _retailShop);
      expect(find.text('Kiasi Kilichopo (pcs)'), findsOneWidget);
    });

    testWidgets('it follows the unit that is chosen', (t) async {
      await _openPage(t, settings: _retailShop);
      expect(find.text('Kiasi Kilichopo (pcs)'), findsOneWidget);

      await t.tap(find.text('pcs').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('carton').last);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));

      expect(find.text('Kiasi Kilichopo (carton)'), findsOneWidget);
      expect(find.text('Kiasi Kilichopo (pcs)'), findsNothing);
    });

    testWidgets('a depot in wholesale mode counts in the unit it chose (crates)', (t) async {
      await _openPage(t);
      expect(find.text('Kiasi Kilichopo (crate)'), findsOneWidget);
    });

    testWidgets('goods by weight count in grams, or in kg once that is chosen', (t) async {
      await _openPage(t, settings: _retailShop);
      await t.tap(_key('measure_weight'));
      await t.pump();
      expect(find.text('Kiasi Kilichopo (g)'), findsOneWidget);

      await t.tap(_key('stock_unit_1000'));
      await t.pump();
      expect(find.text('Kiasi Kilichopo (kg)'), findsOneWidget);
    });
  });
}
