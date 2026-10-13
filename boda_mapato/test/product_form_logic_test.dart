import 'package:boda_mapato/modules/inventory/models/inv_capabilities.dart';
import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/models/inv_product_unit.dart';
import 'package:boda_mapato/modules/inventory/screens/products/product_form_logic.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/inv_units_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const InvCapabilities _depot = InvCapabilities();
const InvCapabilities _retail = InvCapabilities(inventoryType: 'retail', useCrates: false, saleTier: 'retail');
const InvCapabilities _wholesale = InvCapabilities(inventoryType: 'wholesale', useCrates: false, saleTier: 'wholesale');
const InvCapabilities _mixed = InvCapabilities(inventoryType: 'mixed', useCrates: false, saleTier: 'retail');

InvProduct _product({int quantity = 0, String unit = 'pcs', String measure = 'count'}) => InvProduct(
      id: 1,
      name: 'Thing',
      sku: 'T-1',
      category: '',
      costPrice: 1,
      sellingPrice: 2,
      unit: unit,
      quantity: quantity,
      minStock: 0,
      status: 'active',
      barcode: '',
      createdBy: 1,
      measure: measure,
    );

InvProductUnit _unit(int id, String name, int factor, {bool base = false, String status = 'active'}) =>
    InvProductUnit(id: id, productId: 1, name: name, factor: factor, isBase: base, status: status);

void main() {
  group('numbers are whole and prices are per base unit', () {
    test('a price per kg becomes a price per gram, to two decimals', () {
      expect(perBaseUnit(2200, 1000), 2.2);
      expect(perBaseUnit(2500, 1000), 2.5);
      expect(perBaseUnit(1, 3), 0.33);
      expect(perBaseUnit(5000, 1), 5000, reason: 'a factor of 1 leaves the price alone');
    });

    test('wholeNumber never turns a fraction into a bigger number', () {
      expect(wholeNumber('120'), 120);
      expect(wholeNumber('1,200'), 1200);
      expect(wholeNumber(' 40 '), 40);
      expect(wholeNumber('2.5'), 0, reason: '"2.5" must not quietly become 25');
      expect(wholeNumber('-3'), 0);
      expect(wholeNumber('abc'), 0);
      expect(wholeNumber(null), 0);
      expect(wholeNumber(''), 0);
    });

    test('optionalAmount reads money with thousands separators and leaves blanks out', () {
      expect(optionalAmount('22,000'), 22000);
      expect(optionalAmount('  '), isNull);
      expect(optionalAmount(null), isNull);
      expect(optionalAmount('x'), isNull);
    });

    test('the measure parses its wire name and knows its units', () {
      expect(ProductMeasure.parse('weight'), ProductMeasure.weight);
      expect(ProductMeasure.parse('nonsense'), ProductMeasure.count);
      expect(ProductMeasure.parse(null), ProductMeasure.count);
      expect(ProductMeasure.weight.baseUnit, 'g');
      expect(ProductMeasure.weight.bigUnit, 'kg');
      expect(ProductMeasure.volume.baseUnit, 'ml');
      expect(ProductMeasure.volume.bigUnit, 'litre');
      expect(ProductMeasure.volume.bigFactor, 1000);
      expect(ProductMeasure.count.bigFactor, 1);
    });
  });

  group('a depot is built exactly as it always was', () {
    test('retail mode: the price is the retail one, in the unit it was typed in', () {
      final ProductRequest r = buildProductRequest(
        caps: _depot,
        measure: ProductMeasure.count,
        depotWholesaleMode: false,
        unit: 'pcs',
        unitFactor: 1,
        cost: 900,
        price: 1200,
        quantity: 48,
        minStock: 12,
      );
      expect(r.priceTier, 'retail');
      expect(r.unit, 'pcs');
      expect(r.unitFactor, 1);
      expect(r.costPrice, 900);
      expect(r.sellingPrice, 1200);
      expect(r.quantity, 48);
      expect(r.minStock, 12);
      expect(r.units, isEmpty);
      expect(r.variants, isEmpty);
    });

    test('wholesale mode keeps the crate and its bottles-per-crate', () {
      final ProductRequest r = buildProductRequest(
        caps: _depot,
        measure: ProductMeasure.count,
        depotWholesaleMode: true,
        unit: 'crate',
        unitFactor: 24,
        cost: 20000,
        price: 25000,
        quantity: 10,
        minStock: 2,
      );
      expect(r.priceTier, 'wholesale');
      expect(r.unit, 'crate');
      expect(r.unitFactor, 24);
      expect(r.quantity, 10);
    });

    test('a factor below 1 is sent as 1', () {
      final ProductRequest r = buildProductRequest(
        caps: _depot,
        measure: ProductMeasure.count,
        depotWholesaleMode: true,
        unit: 'crate',
        unitFactor: 0,
        cost: 1,
        price: 2,
        quantity: 1,
        minStock: 0,
      );
      expect(r.unitFactor, 1);
    });
  });

  group('other kinds of business', () {
    ProductRequest build(InvCapabilities caps, {double? other}) => buildProductRequest(
          caps: caps,
          measure: ProductMeasure.count,
          depotWholesaleMode: true, // a depot-only switch: must be ignored
          unit: 'pcs',
          unitFactor: 24, // a depot-only field: must be ignored
          cost: 700,
          price: 1000,
          otherPrice: other,
          quantity: 30,
          minStock: 5,
        );

    test('a retail business prices at retail whatever the depot switch says', () {
      final ProductRequest r = build(_retail, other: 900);
      expect(r.priceTier, 'retail');
      expect(r.unitFactor, 1);
      expect(r.sellingPrice, 1000);
      expect(r.otherPrice, 900, reason: 'the same unit at the other level');
    });

    test('a wholesale business prices at wholesale', () {
      expect(build(_wholesale).priceTier, 'wholesale');
    });

    test('a mixed business starts at retail and can carry a wholesale price', () {
      final ProductRequest r = build(_mixed, other: 800);
      expect(r.priceTier, 'retail');
      expect(r.otherPrice, 800);
      expect(_mixed.offersWholesalePrice, isTrue);
      expect(_retail.offersWholesalePrice, isFalse);
    });

    test('extra selling units and sizes travel with the request', () {
      final ProductRequest r = buildProductRequest(
        caps: _retail,
        measure: ProductMeasure.count,
        depotWholesaleMode: false,
        unit: 'pcs',
        unitFactor: 1,
        cost: 700,
        price: 1000,
        quantity: 0,
        minStock: 0,
        extraUnits: const <UnitInput>[UnitInput(name: ' carton ', factor: 24, retail: 22000, wholesale: 20000)],
        variants: const <VariantInput>[VariantInput(label: ' M / Red ', quantity: 5, price: 1500, barcode: ' 123 ')],
      );
      expect(r.unitsJson, <Map<String, dynamic>>[
        <String, dynamic>{'name': 'carton', 'factor': 24, 'retail_price': 22000.0, 'wholesale_price': 20000.0},
      ]);
      expect(r.variantsJson, <Map<String, dynamic>>[
        <String, dynamic>{'label': 'M / Red', 'quantity': 5, 'selling_price': 1500.0, 'barcode': '123'},
      ]);
    });

    test('unset prices and barcodes are left out of the JSON', () {
      const UnitInput u = UnitInput(name: 'pack', factor: 6);
      expect(u.toJson().containsKey('retail_price'), isFalse);
      expect(u.toJson().containsKey('wholesale_price'), isFalse);
      const VariantInput v = VariantInput(label: 'XL');
      expect(v.toJson(), <String, dynamic>{'label': 'XL', 'quantity': 0});
    });
  });

  group('goods by weight and volume are stocked in grams and millilitres', () {
    ProductRequest weighed({
      InvCapabilities caps = _retail,
      ProductMeasure measure = ProductMeasure.weight,
      double? other,
      int stockUnitFactor = 1,
      List<UnitInput> extra = const <UnitInput>[],
    }) =>
        buildProductRequest(
          caps: caps,
          measure: measure,
          depotWholesaleMode: false,
          unit: 'pcs',
          unitFactor: 1,
          cost: 1500,
          price: 2200,
          otherPrice: other,
          quantity: 5,
          minStock: 2,
          stockUnitFactor: stockUnitFactor,
          extraUnits: extra,
        );

    test('prices typed per kg are stored per gram and the kg unit keeps the exact price', () {
      final ProductRequest r = weighed();
      expect(r.unit, 'g');
      expect(r.unitFactor, 1);
      expect(r.costPrice, 1.5);
      expect(r.sellingPrice, 2.2);
      expect(r.units, hasLength(1));
      expect(r.units.single.name, 'kg');
      expect(r.units.single.factor, 1000);
      expect(r.units.single.retail, 2200, reason: 'the owner typed 2,200 per kg, so that is the kg price, exactly');
      expect(r.units.single.wholesale, isNull);
    });

    test('stock typed in kg is sent as whole grams', () {
      final ProductRequest r = weighed(stockUnitFactor: 1000);
      expect(r.quantity, 5000);
      expect(r.minStock, 2000);
      expect(r.quantity, isA<int>());
    });

    test('stock typed in grams stays in grams', () {
      final ProductRequest r = weighed();
      expect(r.quantity, 5);
      expect(r.minStock, 2);
    });

    test('litres work the same way', () {
      final ProductRequest r = weighed(measure: ProductMeasure.volume, stockUnitFactor: 1000);
      expect(r.unit, 'ml');
      expect(r.units.single.name, 'litre');
      expect(r.quantity, 5000);
    });

    test('a wholesale business quotes the per-kg price at wholesale', () {
      final ProductRequest r = weighed(caps: _wholesale, other: 2500);
      expect(r.priceTier, 'wholesale');
      expect(r.units.single.wholesale, 2200);
      expect(r.units.single.retail, 2500);
      expect(r.otherPrice, 2.5);
    });

    test('a second price level at retail lands on the kg unit as well', () {
      final ProductRequest r = weighed(caps: _mixed, other: 2000);
      expect(r.units.single.retail, 2200);
      expect(r.units.single.wholesale, 2000);
    });

    test('a pack typed by hand is kept but a second kg is not added', () {
      final ProductRequest r = weighed(extra: const <UnitInput>[
        UnitInput(name: 'sack', factor: 50000, retail: 100000),
        UnitInput(name: 'KG', factor: 1000, retail: 1),
      ]);
      expect(r.units.map((UnitInput u) => u.name), <String>['kg', 'sack']);
      expect(r.units.first.retail, 2200, reason: 'the kg price that was typed on the page wins');
    });
  });

  group('what the business is set up to do', () {
    test('settings the server did not send read as a depot, which is what it always was', () {
      final InvCapabilities c = InvCapabilities.fromSettings(<String, String>{});
      expect(c.inventoryType, 'depot');
      expect(c.isDepot, isTrue);
      expect(c.useCrates, isTrue);
      expect(c.saleTier, 'product');
      expect(c.usesPriceLevels, isFalse);
      expect(c.pricesIncludeVat, isTrue);
      expect(c.defaultTaxPercent, 0);
      expect(c, _depot);
    });

    test('a retail business has no crates and sells at the retail level', () {
      final InvCapabilities c = InvCapabilities.fromSettings(<String, String>{
        'inventory_type': 'retail',
        'use_crates': '0',
        'sale_tier': 'retail',
        'prices_include_vat': '0',
        'tax_percent': '18',
      });
      expect(c.isRetail, isTrue);
      expect(c.useCrates, isFalse);
      expect(c.usesPriceLevels, isTrue);
      expect(c.startingTier, 'retail');
      expect(c.pricesIncludeVat, isFalse);
      expect(c.defaultTaxPercent, 18);
    });

    test('a wholesale business starts the till at the wholesale level', () {
      final InvCapabilities c = InvCapabilities.fromSettings(<String, String>{
        'inventory_type': 'wholesale',
        'sale_tier': 'wholesale',
        'use_crates': '0',
      });
      expect(c.isWholesale, isTrue);
      expect(c.startingTier, 'wholesale');
      expect(c.offersWholesalePrice, isTrue);
    });

    test('an unknown type or tier falls back to the depot way', () {
      final InvCapabilities c = InvCapabilities.fromSettings(<String, String>{
        'inventory_type': 'spaceship',
        'sale_tier': 'moon',
      });
      expect(c.inventoryType, 'depot');
      expect(c.saleTier, 'product');
    });

    test('every offered type has a label and a hint in both languages', () {
      expect(kInventoryTypes, <String>['retail', 'wholesale', 'mixed', 'depot']);
      for (final String t in kInventoryTypes) {
        for (final bool sw in <bool>[true, false]) {
          expect(inventoryTypeLabel(t, sw: sw), isNot(t));
          expect(inventoryTypeHint(t, sw: sw), isNotEmpty);
        }
      }
    });
  });

  group('stock reads as a person says it', () {
    test('grams become "12 kg 500 g"', () {
      final InvProduct p = _product(quantity: 12500, unit: 'g', measure: 'weight');
      expect(stockLabel(p, <InvProductUnit>[_unit(1, 'g', 1, base: true), _unit(2, 'kg', 1000)], _retail), '12 kg 500 g');
    });

    test('an exact number of kilograms has no leftover grams', () {
      final InvProduct p = _product(quantity: 3000, unit: 'g', measure: 'weight');
      expect(stockLabel(p, <InvProductUnit>[_unit(1, 'g', 1, base: true), _unit(2, 'kg', 1000)], _retail), '3 kg');
    });

    test('less than the bigger unit stays in the small one', () {
      final InvProduct p = _product(quantity: 750, unit: 'g', measure: 'weight');
      expect(stockLabel(p, <InvProductUnit>[_unit(1, 'g', 1, base: true), _unit(2, 'kg', 1000)], _retail), '750 g');
    });

    test('cartons and pieces for a shop', () {
      final InvProduct p = _product(quantity: 51, unit: 'pcs');
      expect(stockLabel(p, <InvProductUnit>[_unit(1, 'pcs', 1, base: true), _unit(2, 'carton', 24)], _retail), '2 carton 3 pcs');
    });

    test('the biggest unit is used first', () {
      final InvProduct p = _product(quantity: 1250, unit: 'pcs');
      final List<InvProductUnit> units = <InvProductUnit>[
        _unit(1, 'pcs', 1, base: true),
        _unit(2, 'pack', 6),
        _unit(3, 'sack', 1000),
      ];
      expect(stockLabel(p, units, _retail), '1 sack 41 pack 4 pcs');
    });

    test('units that are switched off are not used', () {
      final InvProduct p = _product(quantity: 48, unit: 'pcs');
      expect(
        stockLabel(p, <InvProductUnit>[_unit(1, 'pcs', 1, base: true), _unit(2, 'carton', 24, status: 'inactive')], _retail),
        '48',
      );
    });

    test('a depot keeps the plain number it always showed', () {
      final InvProduct p = _product(quantity: 51, unit: 'bottle');
      expect(stockLabel(p, <InvProductUnit>[_unit(1, 'bottle', 1, base: true), _unit(2, 'crate', 24)], _depot), '51');
    });

    test('goods by weight read in kg even at a depot', () {
      final InvProduct p = _product(quantity: 2500, unit: 'g', measure: 'weight');
      expect(stockLabel(p, <InvProductUnit>[_unit(1, 'g', 1, base: true), _unit(2, 'kg', 1000)], _depot), '2 kg 500 g');
    });

    test('no stock reads as zero', () {
      final InvProduct p = _product(quantity: 0, unit: 'g', measure: 'weight');
      expect(stockLabel(p, <InvProductUnit>[_unit(2, 'kg', 1000)], _retail), '0');
    });

    test('stockLabelOf does the same for a number that is only being typed', () {
      expect(
        stockLabelOf(5500, baseUnit: 'g', weighed: true, units: <InvProductUnit>[_unit(2, 'kg', 1000)], caps: _retail),
        '5 kg 500 g',
      );
    });
  });
}
