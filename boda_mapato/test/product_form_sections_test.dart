import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/screens/products/product_form_logic.dart';
import 'package:boda_mapato/modules/inventory/screens/products/product_form_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => ScreenUtilInit(
      designSize: const Size(400, 1600),
      minTextAdapt: true,
      builder: (_, __) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(400, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

InvProduct _p(int id, String label, int qty) => InvProduct(
      id: id,
      name: 'Shirt — $label',
      sku: 'S-$id',
      category: '',
      costPrice: 1,
      sellingPrice: 2,
      unit: 'pcs',
      quantity: qty,
      minStock: 0,
      status: 'active',
      barcode: '',
      createdBy: 1,
      variantLabel: label,
      familyId: 1,
    );

void main() {
  group('UnitDraft', () {
    test('a name and a size make a selling unit', () {
      final UnitDraft d = UnitDraft(name: ' carton ', factor: '24', retail: '22,000', wholesale: '20,000');
      final UnitInput? u = d.toInput();
      expect(u, isNotNull);
      expect(u!.factor, 24);
      expect(u.retail, 22000);
      expect(u.wholesale, 20000);
      d.dispose();
    });

    test('a row missing its name or its size is not a unit', () {
      final UnitDraft noName = UnitDraft(factor: '24');
      final UnitDraft noSize = UnitDraft(name: 'carton');
      final UnitDraft fraction = UnitDraft(name: 'carton', factor: '2.5');
      expect(noName.toInput(), isNull);
      expect(noSize.toInput(), isNull);
      expect(fraction.toInput(), isNull, reason: 'a size is a whole number of base units');
      expect(noName.isEmpty, isTrue);
      expect(noSize.isEmpty, isFalse);
      for (final UnitDraft d in <UnitDraft>[noName, noSize, fraction]) {
        d.dispose();
      }
    });

    test('prices are optional', () {
      final UnitDraft d = UnitDraft(name: 'pack', factor: '6');
      final UnitInput u = d.toInput()!;
      expect(u.retail, isNull);
      expect(u.wholesale, isNull);
      d.dispose();
    });
  });

  group('VariantDraft', () {
    test('a label is all a size or colour needs', () {
      final VariantDraft d = VariantDraft(label: 'M / Red');
      final VariantInput v = d.toInput()!;
      expect(v.label, 'M / Red');
      expect(v.quantity, 0);
      expect(v.price, isNull);
      d.dispose();
    });

    test('stock is a whole number and a fraction counts as none', () {
      final VariantDraft whole = VariantDraft(label: 'L', qty: '12', price: '15,000', barcode: '555');
      final VariantDraft fraction = VariantDraft(label: 'XL', qty: '1.5');
      expect(whole.toInput()!.quantity, 12);
      expect(whole.toInput()!.price, 15000);
      expect(whole.toInput()!.barcode, '555');
      expect(fraction.toInput()!.quantity, 0);
      whole.dispose();
      fraction.dispose();
    });

    test('no label, no variant', () {
      final VariantDraft d = VariantDraft(qty: '5');
      expect(d.toInput(), isNull);
      d.dispose();
    });
  });

  group('MeasureChips', () {
    testWidgets('offer count, weight and volume and report the choice', (t) async {
      _tall(t);
      ProductMeasure? picked;
      await t.pumpWidget(_host(MeasureChips(value: ProductMeasure.count, sw: false, onChanged: (ProductMeasure m) => picked = m)));

      expect(_key('measure_count'), findsOneWidget);
      expect(_key('measure_weight'), findsOneWidget);
      expect(_key('measure_volume'), findsOneWidget);
      expect(find.textContaining('No decimals'), findsNothing, reason: 'only explained once weight or volume is chosen');

      await t.tap(_key('measure_weight'));
      expect(picked, ProductMeasure.weight);
    });

    for (final (String name, double width, bool sw) in <(String, double, bool)>[
      ('a normal phone', 400, false),
      ('a narrow phone', 320, false),
      ('the narrowest phone, in Swahili', 280, true),
    ]) {
      testWidgets('the three choices are ONE row of equal chips on $name', (t) async {
        t.view.physicalSize = Size(width, 1600);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        await t.pumpWidget(_host(MeasureChips(value: ProductMeasure.count, sw: sw, onChanged: (_) {})));

        final Rect count = t.getRect(_key('measure_count'));
        final Rect weight = t.getRect(_key('measure_weight'));
        final Rect volume = t.getRect(_key('measure_volume'));
        expect(t.takeException(), isNull, reason: 'nothing overflows at ${width}px');
        expect(weight.top, count.top, reason: 'weight is on the same row as count');
        expect(volume.top, count.top, reason: 'volume is on the same row as count');
        expect(count.left < weight.left && weight.left < volume.left, isTrue, reason: 'count, weight, volume from left to right');
        expect(weight.width, closeTo(count.width, 0.5), reason: 'equal widths');
        expect(volume.width, closeTo(count.width, 0.5));
        expect(weight.height, count.height, reason: 'equal heights');
        expect(volume.height, count.height);
        expect(volume.right, lessThanOrEqualTo(width + 0.01), reason: 'inside the screen');
      });
    }

    testWidgets('the labels are kept whole, only broken before their bracket', (t) async {
      _tall(t);
      await t.pumpWidget(_host(MeasureChips(value: ProductMeasure.count, sw: false, onChanged: (_) {})));

      expect(find.text('By count\n(pcs)'), findsOneWidget);
      expect(find.text('By weight\n(kg)'), findsOneWidget);
      expect(find.text('By volume\n(litres)'), findsOneWidget);
    });

    testWidgets('weight explains that nothing is ever a fraction', (t) async {
      _tall(t);
      await t.pumpWidget(_host(MeasureChips(value: ProductMeasure.weight, sw: false, onChanged: (_) {})));
      expect(find.textContaining('No decimals'), findsOneWidget);
      expect(find.textContaining('2,500 g'), findsOneWidget);
    });

    testWidgets('volume explains the same in Swahili', (t) async {
      _tall(t);
      await t.pumpWidget(_host(MeasureChips(value: ProductMeasure.volume, sw: true, onChanged: (_) {})));
      expect(find.textContaining('Hakuna desimali'), findsOneWidget);
    });

    testWidgets('cannot be changed when disabled (an existing product keeps its measure)', (t) async {
      _tall(t);
      ProductMeasure? picked;
      await t.pumpWidget(_host(MeasureChips(
        value: ProductMeasure.weight,
        sw: false,
        enabled: false,
        onChanged: (ProductMeasure m) => picked = m,
      )));
      await t.tap(_key('measure_count'), warnIfMissed: false);
      expect(picked, isNull);
    });
  });

  group('UnitsEditor', () {
    testWidgets('rows are added, filled and removed through the page', (t) async {
      _tall(t);
      final List<UnitDraft> drafts = <UnitDraft>[];
      await t.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => UnitsEditor(
          drafts: drafts,
          baseUnit: 'pcs',
          sw: false,
          onAdd: () => setState(() => drafts.add(UnitDraft())),
          onRemove: (UnitDraft d) => setState(() => drafts.remove(d)),
        ),
      )));

      expect(_key('unit_row_name_0'), findsNothing);
      await t.tap(_key('unit_add'));
      await t.pump();
      expect(_key('unit_row_name_0'), findsOneWidget);
      expect(find.text('How many pcs inside?'), findsOneWidget, reason: 'the size is asked in the base unit, in words');

      await t.enterText(_key('unit_row_name_0'), 'carton');
      await t.enterText(_key('unit_row_factor_0'), '24');
      await t.enterText(_key('unit_row_retail_0'), '22000');
      expect(drafts.single.toInput()!.factor, 24);

      await t.tap(_key('unit_add'));
      await t.pump();
      expect(_key('unit_row_name_1'), findsOneWidget);

      await t.tap(_key('unit_row_remove_0'));
      await t.pump();
      expect(drafts, hasLength(1));
      expect(_key('unit_row_name_1'), findsNothing);
    });

    testWidgets('asks a plain question with an example, and only offers the button until a pack is added', (t) async {
      _tall(t);
      final List<UnitDraft> drafts = <UnitDraft>[];
      await t.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => UnitsEditor(
          drafts: drafts,
          baseUnit: 'pcs',
          sw: false,
          onAdd: () => setState(() => drafts.add(UnitDraft())),
          onRemove: (UnitDraft d) => setState(() => drafts.remove(d)),
        ),
      )));

      expect(find.text('Do you also sell it in packs or cartons?'), findsOneWidget);
      expect(find.textContaining('Example: 1 carton = 24 pcs'), findsOneWidget);
      expect(find.text('Add a pack / carton'), findsOneWidget);
      expect(_key('unit_row_name_0'), findsNothing, reason: 'nothing to fill in until the owner says yes');

      await t.tap(_key('unit_add'));
      await t.pump();
      expect(find.text('Pack 1'), findsOneWidget);
      expect(find.text('Add another pack'), findsOneWidget, reason: 'the button now says what it will do');
      expect(find.text('Add a pack / carton'), findsNothing);
    });

    testWidgets('every field has its question written above it, not only a hint that disappears', (t) async {
      _tall(t);
      final List<UnitDraft> drafts = <UnitDraft>[UnitDraft()];
      await t.pumpWidget(_host(UnitsEditor(drafts: drafts, baseUnit: 'pcs', sw: false, onAdd: () {}, onRemove: (_) {})));

      expect(find.text('Name of the pack'), findsOneWidget);
      expect(find.text('How many pcs inside?'), findsOneWidget);
      expect(find.text('Retail price'), findsOneWidget);
      expect(find.text('Wholesale price'), findsOneWidget);
      // ... and the box itself shows an example
      expect(find.byWidgetPredicate((Widget w) => w is TextField && w.decoration?.hintText == 'e.g. Carton'), findsOneWidget);
      expect(find.byWidgetPredicate((Widget w) => w is TextField && w.decoration?.hintText == 'e.g. 24'), findsOneWidget);
    });

    testWidgets('a sentence says what was entered, once there is a name and a size', (t) async {
      _tall(t);
      final List<UnitDraft> drafts = <UnitDraft>[UnitDraft()];
      await t.pumpWidget(_host(UnitsEditor(drafts: drafts, baseUnit: 'pcs', sw: false, onAdd: () {}, onRemove: (_) {})));

      expect(_key('unit_row_summary_0'), findsNothing);
      await t.enterText(_key('unit_row_name_0'), 'Carton');
      await t.pump();
      expect(_key('unit_row_summary_0'), findsNothing, reason: 'a name alone says nothing yet');
      await t.enterText(_key('unit_row_factor_0'), '24');
      await t.pump();
      expect(find.text('1 Carton = 24 pcs'), findsOneWidget);
      await t.enterText(_key('unit_row_retail_0'), '22000');
      await t.pump();
      expect(find.textContaining('1 Carton = 24 pcs'), findsOneWidget);
      expect(find.textContaining('TZS 22,000'), findsOneWidget);
      expect(drafts.single.retail.text, '22,000', reason: 'the price reads with its thousands separator while it is typed');
      expect(drafts.single.toInput()!.retail, 22000, reason: '... and is still the plain number when saved');
    });

    testWidgets('prices cannot carry a decimal point', (t) async {
      _tall(t);
      final List<UnitDraft> drafts = <UnitDraft>[UnitDraft()];
      await t.pumpWidget(_host(UnitsEditor(drafts: drafts, baseUnit: 'pcs', sw: false, onAdd: () {}, onRemove: (_) {})));

      await t.enterText(_key('unit_row_retail_0'), '22000.50');
      expect(drafts.single.retail.text, '2,200,050', reason: 'the dot is filtered out as it is typed, as before');
    });

    testWidgets('says the same in Swahili', (t) async {
      _tall(t);
      final List<UnitDraft> drafts = <UnitDraft>[UnitDraft()];
      await t.pumpWidget(_host(UnitsEditor(drafts: drafts, baseUnit: 'pcs', sw: true, onAdd: () {}, onRemove: (_) {})));

      expect(find.text('Je, unauza pia kwa vifurushi au katoni?'), findsOneWidget);
      expect(find.text('Kifurushi 1'), findsOneWidget);
      expect(find.text('Jina la kifurushi'), findsOneWidget);
      expect(find.text('pcs ngapi ndani?'), findsOneWidget);
    });

    testWidgets('a depot keeps its compact form: its title, no guiding card', (t) async {
      _tall(t);
      await t.pumpWidget(_host(UnitsEditor(drafts: <UnitDraft>[UnitDraft()], baseUnit: 'bottle', sw: false, depotLabels: true, onAdd: () {}, onRemove: (_) {})));

      expect(find.text('Also sold as...'), findsOneWidget);
      expect(find.text('Do you also sell it in packs or cartons?'), findsNothing);
      expect(find.byType(ExtraOptionCard), findsNothing);
    });

    testWidgets('the size box takes digits only, so no fraction can be typed', (t) async {
      _tall(t);
      final List<UnitDraft> drafts = <UnitDraft>[UnitDraft()];
      await t.pumpWidget(_host(UnitsEditor(drafts: drafts, baseUnit: 'pcs', sw: false, onAdd: () {}, onRemove: (_) {})));

      await t.enterText(_key('unit_row_factor_0'), '2.5');
      expect(drafts.single.factor.text, '25', reason: 'the dot is filtered out as it is typed');
    });

    testWidgets('wholesale prices can be hidden for a retail business', (t) async {
      _tall(t);
      final List<UnitDraft> drafts = <UnitDraft>[UnitDraft()];
      await t.pumpWidget(_host(UnitsEditor(
        drafts: drafts,
        baseUnit: 'pcs',
        sw: false,
        showWholesale: false,
        onAdd: () {},
        onRemove: (_) {},
      )));

      expect(_key('unit_row_retail_0'), findsOneWidget);
      expect(_key('unit_row_wholesale_0'), findsNothing);
    });

    testWidgets('a depot sees its own wording for the two prices', (t) async {
      _tall(t);
      final List<UnitDraft> drafts = <UnitDraft>[UnitDraft()];
      await t.pumpWidget(_host(UnitsEditor(
        drafts: drafts,
        baseUnit: 'bottle',
        sw: false,
        depotLabels: true,
        onAdd: () {},
        onRemove: (_) {},
      )));

      expect(find.text('Actual price'), findsOneWidget);
      expect(find.text('Discounted price'), findsOneWidget);
    });
  });

  group('VariantsEditor', () {
    testWidgets('is a switch, and the rows appear only when it is on', (t) async {
      _tall(t);
      bool on = false;
      final List<VariantDraft> drafts = <VariantDraft>[];
      await t.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => VariantsEditor(
          enabled: on,
          sw: false,
          drafts: drafts,
          onToggle: (bool v) => setState(() {
            on = v;
            if (v && drafts.isEmpty) drafts.add(VariantDraft());
          }),
          onAdd: () => setState(() => drafts.add(VariantDraft())),
          onRemove: (VariantDraft d) => setState(() => drafts.remove(d)),
        ),
      )));

      expect(_key('variant_label_0'), findsNothing);
      await t.tap(_key('variant_toggle'));
      await t.pump();
      expect(_key('variant_label_0'), findsOneWidget);

      await t.enterText(_key('variant_label_0'), 'M / Red');
      await t.enterText(_key('variant_qty_0'), '12');
      await t.tap(_key('variant_add'));
      await t.pump();
      expect(_key('variant_label_1'), findsOneWidget);
      expect(drafts.first.toInput()!.quantity, 12);

      await t.tap(_key('variant_remove_1'));
      await t.pump();
      expect(drafts, hasLength(1));

      await t.tap(_key('variant_toggle'));
      await t.pump();
      expect(_key('variant_label_0'), findsNothing);
    });

    testWidgets('stock per size takes digits only', (t) async {
      _tall(t);
      final List<VariantDraft> drafts = <VariantDraft>[VariantDraft()];
      await t.pumpWidget(_host(VariantsEditor(
        enabled: true,
        sw: false,
        drafts: drafts,
        onToggle: (_) {},
        onAdd: () {},
        onRemove: (_) {},
      )));
      await t.enterText(_key('variant_qty_0'), '1.5');
      expect(drafts.single.qty.text, '15');
    });

    testWidgets('lists the sizes a product already has and marks the one being edited', (t) async {
      _tall(t);
      await t.pumpWidget(_host(VariantsEditor(
        enabled: true,
        sw: false,
        drafts: <VariantDraft>[],
        family: <InvProduct>[_p(1, 'M', 4), _p(2, 'L', 9)],
        currentId: 2,
        onToggle: (_) {},
        onAdd: () {},
        onRemove: (_) {},
      )));

      expect(find.text('M: 4'), findsOneWidget);
      expect(find.text('L: 9 (this)'), findsOneWidget);
    });
  });

  group('VariantsEditor in plain words', () {
    testWidgets('asks the question, with an example, and the switch says Yes or No', (t) async {
      _tall(t);
      bool on = false;
      await t.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => VariantsEditor(
          enabled: on,
          sw: false,
          drafts: <VariantDraft>[],
          onToggle: (bool v) => setState(() => on = v),
          onAdd: () {},
          onRemove: (_) {},
        ),
      )));

      expect(find.text('Does it come in different sizes or colours?'), findsOneWidget);
      expect(find.textContaining('a shirt in S, M, L'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Yes'), findsNothing);

      await t.tap(_key('variant_toggle'));
      await t.pump();
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsNothing);
    });

    testWidgets('each size has labelled fields and a numbered heading, and the add button says what it adds', (t) async {
      _tall(t);
      final List<VariantDraft> drafts = <VariantDraft>[VariantDraft()];
      await t.pumpWidget(_host(VariantsEditor(enabled: true, sw: false, drafts: drafts, onToggle: (_) {}, onAdd: () {}, onRemove: (_) {})));

      expect(find.text('Size / colour 1'), findsOneWidget);
      expect(find.text('Size or colour'), findsOneWidget);
      expect(find.text('How many in stock?'), findsOneWidget);
      expect(find.text('Its own price (optional)'), findsOneWidget);
      expect(find.text('Barcode (optional)'), findsOneWidget);
      expect(find.text('Add another'), findsOneWidget);
    });

    testWidgets('with no size yet the button invites the first one', (t) async {
      _tall(t);
      await t.pumpWidget(_host(VariantsEditor(enabled: true, sw: false, drafts: <VariantDraft>[], onToggle: (_) {}, onAdd: () {}, onRemove: (_) {})));

      expect(find.text('Add a size / colour'), findsOneWidget);
    });

    testWidgets('says the same in Swahili', (t) async {
      _tall(t);
      await t.pumpWidget(_host(VariantsEditor(enabled: false, sw: true, drafts: <VariantDraft>[], onToggle: (_) {}, onAdd: () {}, onRemove: (_) {})));

      expect(find.text('Je, ina saizi au rangi tofauti?'), findsOneWidget);
      expect(find.text('Hapana'), findsOneWidget);
    });
  });

  group('VatSection', () {
    testWidgets('is closed until opened and explains what empty means', (t) async {
      _tall(t);
      final TextEditingController c = TextEditingController();
      addTearDown(c.dispose);
      await t.pumpWidget(_host(VatSection(controller: c, defaultPercent: 18, sw: false)));

      expect(_key('vat_field'), findsNothing, reason: 'collapsed: nothing changes unless it is opened');
      await t.tap(_key('vat_section'));
      await t.pumpAndSettle();
      expect(_key('vat_field'), findsOneWidget);
      expect(find.textContaining('business default (18%)'), findsOneWidget);
      expect(find.textContaining('Type 0'), findsOneWidget);
    });

    testWidgets('says "no VAT" when the business has no default rate', (t) async {
      _tall(t);
      final TextEditingController c = TextEditingController();
      addTearDown(c.dispose);
      await t.pumpWidget(_host(VatSection(controller: c, defaultPercent: 0, sw: false)));
      await t.tap(_key('vat_section'));
      await t.pumpAndSettle();
      expect(find.textContaining('business default (no VAT)'), findsOneWidget);
    });

    testWidgets('writes what is typed into its controller', (t) async {
      _tall(t);
      final TextEditingController c = TextEditingController();
      addTearDown(c.dispose);
      await t.pumpWidget(_host(VatSection(controller: c, defaultPercent: 18, sw: true)));
      await t.tap(_key('vat_section'));
      await t.pumpAndSettle();
      await t.enterText(_key('vat_field'), '16.5');
      expect(c.text, '16.5', reason: 'VAT is a rate, so it may carry a decimal; quantities may not');
    });

    testWidgets('as a card it asks a question and says what skipping it means, still closed until opened', (t) async {
      _tall(t);
      final TextEditingController c = TextEditingController();
      addTearDown(c.dispose);
      await t.pumpWidget(_host(VatSection(controller: c, defaultPercent: 18, sw: false, card: true)));

      expect(find.text('Does this product have its own VAT rate?'), findsOneWidget);
      expect(find.textContaining('your usual rate applies (18%)'), findsOneWidget);
      expect(_key('vat_field'), findsNothing);
      await t.tap(_key('vat_section'));
      await t.pumpAndSettle();
      expect(_key('vat_field'), findsOneWidget);
      expect(find.textContaining('business default (18%)'), findsOneWidget);
    });

    testWidgets('without the card (a depot) it is the plain row it always was', (t) async {
      _tall(t);
      final TextEditingController c = TextEditingController();
      addTearDown(c.dispose);
      await t.pumpWidget(_host(VatSection(controller: c, defaultPercent: 18, sw: false)));

      expect(find.text('VAT (optional)'), findsOneWidget);
      expect(find.text('Does this product have its own VAT rate?'), findsNothing);
    });
  });
}
