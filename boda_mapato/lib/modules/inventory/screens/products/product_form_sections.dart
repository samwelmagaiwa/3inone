import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../constants/theme_constants.dart';
import '../../models/inv_product.dart';
import 'product_form_logic.dart';

/// The pieces of the product page that are not "name, price, stock": ways of selling it, sizes / colours, VAT.
/// They hold no state of their own beyond text controllers; the page owns the drafts and saves them.

/// One extra way to sell a product, being typed.
class UnitDraft {
  UnitDraft({String name = '', String factor = '', String retail = '', String wholesale = ''})
      : name = TextEditingController(text: name),
        factor = TextEditingController(text: factor),
        retail = TextEditingController(text: retail),
        wholesale = TextEditingController(text: wholesale);

  final TextEditingController name;
  final TextEditingController factor;
  final TextEditingController retail;
  final TextEditingController wholesale;

  bool get isEmpty => name.text.trim().isEmpty;

  /// A usable row: a name, and a size of at least 2 base units (1 would just be the base unit again).
  UnitInput? toInput() {
    final int f = wholeNumber(factor.text);
    if (name.text.trim().isEmpty || f < 1) return null;
    return UnitInput(name: name.text, factor: f, retail: optionalAmount(retail.text), wholesale: optionalAmount(wholesale.text));
  }

  void dispose() {
    for (final TextEditingController c in <TextEditingController>[name, factor, retail, wholesale]) {
      c.dispose();
    }
  }
}

/// One size / colour, being typed.
class VariantDraft {
  VariantDraft({String label = '', String qty = '', String price = '', String barcode = ''})
      : label = TextEditingController(text: label),
        qty = TextEditingController(text: qty),
        price = TextEditingController(text: price),
        barcode = TextEditingController(text: barcode);

  final TextEditingController label;
  final TextEditingController qty;
  final TextEditingController price;
  final TextEditingController barcode;

  VariantInput? toInput() {
    if (label.text.trim().isEmpty) return null;
    return VariantInput(label: label.text, quantity: wholeNumber(qty.text), price: optionalAmount(price.text), barcode: barcode.text);
  }

  void dispose() {
    for (final TextEditingController c in <TextEditingController>[label, qty, price, barcode]) {
      c.dispose();
    }
  }
}

InputDecoration _dec(String hint) => ThemeConstants.glassInputDecoration(hint);

Widget _title(String text) => Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Text(text, style: ThemeConstants.headingStyle.copyWith(fontSize: 14.sp)),
    );

Widget _small(Key key, String hint, TextEditingController c, {bool digitsOnly = false, bool money = false, TextInputType? keyboard}) => SizedBox(
      height: 38.h,
      child: TextField(
        key: key,
        controller: c,
        keyboardType: keyboard ?? ((digitsOnly || money) ? TextInputType.number : null),
        inputFormatters: <TextInputFormatter>[
          if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
          if (money) FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
        ],
        decoration: _dec(hint),
        style: ThemeConstants.bodyStyle,
      ),
    );

/// A choice chip in the page's glass colours: a faint white fill and a hairline border, the cyan accent
/// when chosen. (Flutter's default chip is lilac and white, which clashes with the dark teal card.)
Widget glassChoiceChip({
  Key? key,
  required String label,
  required bool selected,
  required ValueChanged<bool>? onSelected,
}) =>
    ChoiceChip(
      key: key,
      label: Text(label, style: TextStyle(fontSize: 12.sp, color: Colors.white)),
      selected: selected,
      showCheckmark: false,
      backgroundColor: ThemeConstants.glassFieldFill,
      disabledColor: ThemeConstants.glassFieldFill,
      selectedColor: ThemeConstants.invAccent.withValues(alpha: 0.30),
      side: BorderSide(color: selected ? ThemeConstants.invAccent : ThemeConstants.glassFieldBorder),
      onSelected: onSelected,
    );

/// What kind of goods: counted (pieces, packs), by weight (stocked in grams, sold in g / kg) or by volume
/// (stocked in millilitres, sold in ml / litres).
class MeasureChips extends StatelessWidget {
  const MeasureChips({super.key, required this.value, required this.onChanged, required this.sw, this.enabled = true});

  final ProductMeasure value;
  final ValueChanged<ProductMeasure> onChanged;
  final bool sw;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final List<(ProductMeasure, String)> options = <(ProductMeasure, String)>[
      (ProductMeasure.count, sw ? 'Kwa idadi (pcs)' : 'By count (pcs)'),
      (ProductMeasure.weight, sw ? 'Kwa uzito (kg)' : 'By weight (kg)'),
      (ProductMeasure.volume, sw ? 'Kwa ujazo (lita)' : 'By volume (litres)'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _title(sw ? 'Bidhaa inauzwaje?' : 'How is it sold?'),
        Wrap(
          spacing: 8.w,
          runSpacing: 4.h,
          children: <Widget>[
            for (final (ProductMeasure m, String label) in options)
              glassChoiceChip(
                key: ValueKey<String>('measure_${m.name}'),
                label: label,
                selected: value == m,
                onSelected: enabled ? (_) => onChanged(m) : null,
              ),
          ],
        ),
        if (value != ProductMeasure.count)
          Padding(
            padding: EdgeInsets.only(top: 4.h),
            child: Text(
              value == ProductMeasure.weight
                  ? (sw ? 'Stoo huhesabiwa kwa gramu; unauza kwa gramu au kilo. Hakuna desimali: kilo 2.5 ni gramu 2,500.' : 'Stock is counted in grams; you sell in grams or kilograms. No decimals: 2.5 kg is 2,500 g.')
                  : (sw ? 'Stoo huhesabiwa kwa mililita; unauza kwa mililita au lita. Hakuna desimali: lita 1.5 ni mililita 1,500.' : 'Stock is counted in millilitres; you sell in millilitres or litres. No decimals: 1.5 litres is 1,500 ml.'),
              style: ThemeConstants.captionStyle.copyWith(fontSize: 11.sp, color: Colors.white70),
            ),
          ),
      ],
    );
  }
}

/// "Also sold as ...": extra ways to sell the product, each holding a whole number of base units
/// (1 carton = 24 pcs), with their own prices.
class UnitsEditor extends StatelessWidget {
  const UnitsEditor({
    super.key,
    required this.drafts,
    required this.baseUnit,
    required this.onAdd,
    required this.onRemove,
    required this.sw,
    this.showWholesale = true,
    this.depotLabels = false,
  });

  final List<UnitDraft> drafts;
  final String baseUnit;
  final VoidCallback onAdd;
  final ValueChanged<UnitDraft> onRemove;
  final bool sw;
  final bool showWholesale;

  /// The depot's own wording for the two price columns (Actual / Discounted price).
  final bool depotLabels;

  @override
  Widget build(BuildContext context) {
    final String retailLabel = depotLabels ? (sw ? 'Bei halisi' : 'Actual price') : (sw ? 'Bei ya rejareja' : 'Retail price');
    final String wholesaleLabel = depotLabels ? (sw ? 'Bei ya punguzo' : 'Discounted price') : (sw ? 'Bei ya jumla' : 'Wholesale price');

    return Column(
      key: const ValueKey<String>('units_editor'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _title(sw ? 'Inauzwa pia kama...' : 'Also sold as...'),
        Text(
          sw
              ? 'Mfano: katoni 1 = $baseUnit 24. Kila moja ina bei yake. Hesabu ya stoo inabaki kwa $baseUnit.'
              : 'For example 1 carton = 24 $baseUnit. Each has its own price; stock stays counted in $baseUnit.',
          style: ThemeConstants.captionStyle.copyWith(fontSize: 11.sp, color: Colors.white70),
        ),
        SizedBox(height: 6.h),
        for (int i = 0; i < drafts.length; i++) ...<Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: 3, child: _small(ValueKey<String>('unit_row_name_$i'), sw ? 'Jina (katoni)' : 'Name (carton)', drafts[i].name)),
              SizedBox(width: 6.w),
              Expanded(flex: 2, child: _small(ValueKey<String>('unit_row_factor_$i'), '= ? $baseUnit', drafts[i].factor, digitsOnly: true)),
              IconButton(
                key: ValueKey<String>('unit_row_remove_$i'),
                onPressed: () => onRemove(drafts[i]),
                icon: Icon(Icons.close, size: 18.sp, color: Colors.white54),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(width: 32.w, height: 32.w),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          Row(
            children: <Widget>[
              Expanded(child: _small(ValueKey<String>('unit_row_retail_$i'), retailLabel, drafts[i].retail, money: true)),
              if (showWholesale) ...<Widget>[
                SizedBox(width: 6.w),
                Expanded(child: _small(ValueKey<String>('unit_row_wholesale_$i'), wholesaleLabel, drafts[i].wholesale, money: true)),
              ],
            ],
          ),
          SizedBox(height: 10.h),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey<String>('unit_add'),
            onPressed: onAdd,
            style: TextButton.styleFrom(foregroundColor: ThemeConstants.invAccent),
            icon: Icon(Icons.add, size: 18.sp),
            label: Text(sw ? 'Ongeza kifurushi / katoni' : 'Add a pack / carton'),
          ),
        ),
      ],
    );
  }
}

/// "Comes in sizes or colours": each is its own stock item with its own count.
class VariantsEditor extends StatelessWidget {
  const VariantsEditor({
    super.key,
    required this.enabled,
    required this.onToggle,
    required this.drafts,
    required this.onAdd,
    required this.onRemove,
    required this.sw,
    this.family = const <InvProduct>[],
    this.currentId,
  });

  final bool enabled;
  final ValueChanged<bool> onToggle;

  /// New sizes / colours being typed.
  final List<VariantDraft> drafts;
  final VoidCallback onAdd;
  final ValueChanged<VariantDraft> onRemove;
  final bool sw;

  /// The sizes / colours this product already has (edit mode), including itself.
  final List<InvProduct> family;
  final int? currentId;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('variants_editor'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: ThemeConstants.glassFieldFill,
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: ThemeConstants.glassFieldBorder),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  sw ? 'Ina saizi au rangi tofauti' : 'Comes in sizes or colours',
                  style: ThemeConstants.bodyStyle,
                ),
              ),
              Switch(
                key: const ValueKey<String>('variant_toggle'),
                value: enabled,
                onChanged: onToggle,
                activeThumbColor: Colors.white,
                activeTrackColor: ThemeConstants.invAccent,
              ),
            ],
          ),
        ),
        if (enabled) ...<Widget>[
          SizedBox(height: 6.h),
          Text(
            sw
                ? 'Kila saizi/rangi ni bidhaa ya stoo yake mwenyewe: ina idadi yake, SKU yake na barcode yake.'
                : 'Each size or colour is its own stock item: its own count, SKU and barcode.',
            style: ThemeConstants.captionStyle.copyWith(fontSize: 11.sp, color: Colors.white70),
          ),
          if (family.isNotEmpty) ...<Widget>[
            SizedBox(height: 8.h),
            _title(sw ? 'Zilizopo' : 'Already there'),
            Wrap(
              spacing: 6.w,
              runSpacing: 4.h,
              children: <Widget>[
                for (final InvProduct p in family)
                  Chip(
                    key: ValueKey<String>('family_${p.id}'),
                    label: Text(
                      '${(p.variantLabel ?? '').isEmpty ? p.name : p.variantLabel}: ${p.quantity}${p.id == currentId ? (sw ? ' (hii)' : ' (this)') : ''}',
                      style: TextStyle(fontSize: 11.sp),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
          SizedBox(height: 8.h),
          for (int i = 0; i < drafts.length; i++) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(flex: 3, child: _small(ValueKey<String>('variant_label_$i'), sw ? 'Saizi / rangi (M / Nyekundu)' : 'Size / colour (M / Red)', drafts[i].label)),
                SizedBox(width: 6.w),
                Expanded(flex: 2, child: _small(ValueKey<String>('variant_qty_$i'), sw ? 'Idadi' : 'Stock', drafts[i].qty, digitsOnly: true)),
                IconButton(
                  key: ValueKey<String>('variant_remove_$i'),
                  onPressed: () => onRemove(drafts[i]),
                  icon: Icon(Icons.close, size: 18.sp, color: Colors.white54),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(width: 32.w, height: 32.w),
                ),
              ],
            ),
            SizedBox(height: 4.h),
            Row(
              children: <Widget>[
                Expanded(child: _small(ValueKey<String>('variant_price_$i'), sw ? 'Bei yake (si lazima)' : 'Its own price (optional)', drafts[i].price, money: true)),
                SizedBox(width: 6.w),
                Expanded(child: _small(ValueKey<String>('variant_barcode_$i'), sw ? 'Barcode (si lazima)' : 'Barcode (optional)', drafts[i].barcode, keyboard: TextInputType.text)),
              ],
            ),
            SizedBox(height: 10.h),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey<String>('variant_add'),
              onPressed: onAdd,
              style: TextButton.styleFrom(foregroundColor: ThemeConstants.invAccent),
              icon: Icon(Icons.add, size: 18.sp),
              label: Text(sw ? 'Ongeza saizi / rangi' : 'Add a size / colour'),
            ),
          ),
        ],
      ],
    );
  }
}

/// The optional VAT rate of the product. Collapsed by default: nothing changes unless it is filled in.
class VatSection extends StatelessWidget {
  const VatSection({super.key, required this.controller, required this.defaultPercent, required this.sw});

  final TextEditingController controller;

  /// What a product with no rate of its own is charged (the business's default).
  final double defaultPercent;
  final bool sw;

  @override
  Widget build(BuildContext context) {
    final String fallback = defaultPercent == 0
        ? (sw ? 'Bila VAT' : 'no VAT')
        : '${defaultPercent.toStringAsFixed(defaultPercent % 1 == 0 ? 0 : 1)}%';

    // The page paints a coloured panel behind its fields; a ListTile needs a Material of its own between it and
    // that panel, or Flutter complains (and shows an error box in debug builds) that its ink would be hidden.
    return Material(
      type: MaterialType.transparency,
      child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey<String>('vat_section'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white70,
        title: Text(sw ? 'VAT (si lazima)' : 'VAT (optional)', style: ThemeConstants.headingStyle.copyWith(fontSize: 14.sp)),
        children: <Widget>[
          _small(const ValueKey<String>('vat_field'), sw ? 'VAT % ya bidhaa hii' : 'VAT % for this product', controller, keyboard: const TextInputType.numberWithOptions(decimal: true)),
          Padding(
            padding: EdgeInsets.only(top: 4.h, bottom: 8.h),
            child: Text(
              sw
                  ? 'Acha wazi kutumia ya biashara ($fallback). Andika 0 kama bidhaa haina VAT.'
                  : 'Leave empty to use the business default ($fallback). Type 0 if this product is VAT-exempt.',
              style: ThemeConstants.captionStyle.copyWith(fontSize: 11.sp, color: Colors.white70),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
