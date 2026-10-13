import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../constants/theme_constants.dart';
import '../../models/inv_product.dart';
import '../widgets/inventory_widgets.dart' show ThousandsFormatter, formatAmount, parseAmount;
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

InputDecoration _dec(String hint) => ThemeConstants.invInputDecoration(hint);

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
          // 22000 reads as 22,000 while it is typed, like the main price boxes (no decimals: the filter above).
          if (money) ThousandsFormatter(),
        ],
        decoration: _dec(hint),
        style: ThemeConstants.bodyStyle,
      ),
    );

/// A field with its question written ABOVE it, so the words stay visible while typing (a hint inside the box
/// disappears with the first letter) and the hint can be an example instead.
Widget _labelled(String label, Key key, String example, TextEditingController c, {bool digitsOnly = false, bool money = false, TextInputType? keyboard}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AutoSizeText(
          label,
          maxLines: 1,
          minFontSize: 9,
          style: ThemeConstants.captionStyle.copyWith(fontSize: 11.5.sp, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        SizedBox(height: 4.h),
        _small(key, example, c, digitsOnly: digitsOnly, money: money, keyboard: keyboard),
      ],
    );

/// One of the optional extras of the product page, as a card a shop owner can read at a glance: a coloured icon,
/// a QUESTION in plain words ("Do you also sell it in packs?"), an example, and what to do about it. [trailing]
/// is a switch for yes / no; [children] are what opens when the answer is yes.
class ExtraOptionCard extends StatelessWidget {
  const ExtraOptionCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.children = const <Widget>[],
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final List<Widget> children;

  /// The round-cornered icon badge (also used by the VAT card).
  static Widget badge(IconData icon, Color color) => Container(
        width: 40.w,
        height: 40.w,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[color, Color.lerp(color, Colors.black, 0.40)!],
          ),
          boxShadow: <BoxShadow>[BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Icon(icon, color: Colors.white, size: 22.sp),
      );

  /// The card's own look, for the VAT card to share.
  static BoxDecoration decoration(Color color) => BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[color.withValues(alpha: 0.15), Colors.white.withValues(alpha: 0.04)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: decoration(color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              badge(icon, color),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, fontSize: 14.sp, height: 1.25)),
                    SizedBox(height: 3.h),
                    Text(subtitle, style: ThemeConstants.captionStyle.copyWith(fontSize: 11.5.sp, color: Colors.white70, height: 1.3)),
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[SizedBox(width: 8.w), trailing!],
            ],
          ),
          if (children.isNotEmpty) ...<Widget>[SizedBox(height: 12.h), ...children],
        ],
      ),
    );
  }
}

/// A small box inside an [ExtraOptionCard] for one pack or one size / colour being typed: a numbered heading,
/// a remove button, and its fields.
class _DraftBox extends StatelessWidget {
  const _DraftBox({required this.heading, required this.removeKey, required this.onRemove, required this.removeTip, required this.children});

  final String heading;
  final Key removeKey;
  final VoidCallback onRemove;
  final String removeTip;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: 10.h),
        padding: EdgeInsets.fromLTRB(10.w, 4.h, 4.w, 10.h),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text(heading, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700, fontSize: 13.sp))),
                IconButton(
                  key: removeKey,
                  tooltip: removeTip,
                  onPressed: onRemove,
                  icon: Icon(Icons.delete_outline_rounded, size: 20.sp, color: Colors.white60),
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(width: 36.w, height: 36.w),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.only(right: 6.w),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ],
        ),
      );
}

/// The wide "+ Add ..." button under a card's rows.
Widget _addButton(Key key, String label, VoidCallback onPressed, Color color) => SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: key,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.6), width: 1.2),
          minimumSize: Size.fromHeight(44.h),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
        icon: Icon(Icons.add_circle_outline_rounded, size: 20.sp),
        label: Text(label, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700)),
      ),
    );

/// A choice chip in the page's glass colours: a faint white fill and a hairline border, the cyan accent
/// when chosen. (Flutter's default chip is lilac and white, which clashes with the dark teal card.)
///
/// [stretch]: the chip fills the width it is given (put it in an Expanded) and centres its label, which may
/// run to two lines, so a row of them stays one row on any phone.
Widget glassChoiceChip({
  Key? key,
  required String label,
  required bool selected,
  required ValueChanged<bool>? onSelected,
  bool stretch = false,
}) =>
    ChoiceChip(
      key: key,
      label: stretch
          ? SizedBox(
              width: double.infinity,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.sp, color: Colors.white, height: 1.25),
              ),
            )
          : Text(label, style: TextStyle(fontSize: 12.sp, color: Colors.white)),
      labelPadding: stretch ? EdgeInsets.symmetric(horizontal: 2.w) : null,
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
        // One row, three equal chips. Each label breaks before its bracket ("By count" / "(pcs)"), so all three
        // have two lines and the same height, and fit side by side on the narrowest phone too.
        Row(
          children: <Widget>[
            for (int i = 0; i < options.length; i++) ...<Widget>[
              if (i > 0) SizedBox(width: 6.w),
              Expanded(
                child: glassChoiceChip(
                  key: ValueKey<String>('measure_${options[i].$1.name}'),
                  label: options[i].$2.replaceFirst(' (', '\n('),
                  selected: value == options[i].$1,
                  onSelected: enabled ? (_) => onChanged(options[i].$1) : null,
                  stretch: true,
                ),
              ),
            ],
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

  /// Everyone but the depot gets the guided card: a question, an example, labelled fields and a plain sentence
  /// saying what was entered. The depot keeps the compact form it has always had.
  Widget _guided() {
    final String retailLabel = sw ? 'Bei ya rejareja' : 'Retail price';
    final String wholesaleLabel = sw ? 'Bei ya jumla' : 'Wholesale price';
    const Color color = ThemeConstants.warningAmber;

    return ExtraOptionCard(
      key: const ValueKey<String>('units_editor'),
      icon: Icons.inventory_2_rounded,
      color: color,
      title: sw ? 'Je, unauza pia kwa vifurushi au katoni?' : 'Do you also sell it in packs or cartons?',
      subtitle: sw
          ? 'Mfano: katoni 1 = $baseUnit 24, yenye bei yake. Stoo inabaki ikihesabiwa kwa $baseUnit.'
          : 'Example: 1 carton = 24 $baseUnit, with its own price. Stock stays counted in $baseUnit.',
      children: <Widget>[
        for (int i = 0; i < drafts.length; i++)
          _DraftBox(
            heading: sw ? 'Kifurushi ${i + 1}' : 'Pack ${i + 1}',
            removeKey: ValueKey<String>('unit_row_remove_$i'),
            removeTip: sw ? 'Ondoa' : 'Remove',
            onRemove: () => onRemove(drafts[i]),
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 3, child: _labelled(sw ? 'Jina la kifurushi' : 'Name of the pack', ValueKey<String>('unit_row_name_$i'), sw ? 'mf. Katoni' : 'e.g. Carton', drafts[i].name)),
                  SizedBox(width: 8.w),
                  Expanded(
                    flex: 3,
                    child: _labelled(sw ? '$baseUnit ngapi ndani?' : 'How many $baseUnit inside?', ValueKey<String>('unit_row_factor_$i'), sw ? 'mf. 24' : 'e.g. 24', drafts[i].factor, digitsOnly: true),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: _labelled(retailLabel, ValueKey<String>('unit_row_retail_$i'), sw ? 'mf. 22,000' : 'e.g. 22,000', drafts[i].retail, money: true)),
                  if (showWholesale) ...<Widget>[
                    SizedBox(width: 8.w),
                    Expanded(child: _labelled(wholesaleLabel, ValueKey<String>('unit_row_wholesale_$i'), sw ? 'mf. 20,000' : 'e.g. 20,000', drafts[i].wholesale, money: true)),
                  ],
                ],
              ),
              // What was entered, in a sentence anyone can check: "1 Carton = 24 pcs · TZS 22,000".
              ListenableBuilder(
                listenable: Listenable.merge(<Listenable>[drafts[i].name, drafts[i].factor, drafts[i].retail]),
                builder: (BuildContext _, Widget? __) {
                  final String name = drafts[i].name.text.trim();
                  final int factor = wholeNumber(drafts[i].factor.text);
                  if (name.isEmpty || factor < 1) return const SizedBox.shrink();
                  final double price = parseAmount(drafts[i].retail.text);
                  return Padding(
                    padding: EdgeInsets.only(top: 8.h),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.check_circle_rounded, size: 15.sp, color: ThemeConstants.successGreen),
                        SizedBox(width: 6.w),
                        Expanded(
                          child: Text(
                            '1 $name = $factor $baseUnit${price > 0 ? '  ·  TZS ${formatAmount(price)}' : ''}',
                            key: ValueKey<String>('unit_row_summary_$i'),
                            style: ThemeConstants.captionStyle.copyWith(fontSize: 12.sp, color: ThemeConstants.successGreen, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        _addButton(
          const ValueKey<String>('unit_add'),
          drafts.isEmpty ? (sw ? 'Ongeza kifurushi / katoni' : 'Add a pack / carton') : (sw ? 'Ongeza kifurushi kingine' : 'Add another pack'),
          onAdd,
          color,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!depotLabels) return _guided();
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
    const Color color = Color(0xFF8B8CF5);

    return ExtraOptionCard(
      key: const ValueKey<String>('variants_editor'),
      icon: Icons.palette_rounded,
      color: color,
      title: sw ? 'Je, ina saizi au rangi tofauti?' : 'Does it come in different sizes or colours?',
      subtitle: sw
          ? 'Mfano: shati ya S, M, L, au nyekundu na bluu. Kila moja ina idadi yake ya stoo.'
          : 'Example: a shirt in S, M, L, or red and blue. Each one has its own stock count.',
      // A word beside the switch, so nobody has to guess which way "on" is.
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            enabled ? (sw ? 'Ndiyo' : 'Yes') : (sw ? 'Hapana' : 'No'),
            style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w800, color: enabled ? Colors.white : Colors.white60),
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
      children: <Widget>[
        if (enabled) ...<Widget>[
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
          SizedBox(height: 10.h),
          for (int i = 0; i < drafts.length; i++)
            _DraftBox(
              heading: sw ? 'Saizi / rangi ${i + 1}' : 'Size / colour ${i + 1}',
              removeKey: ValueKey<String>('variant_remove_$i'),
              removeTip: sw ? 'Ondoa' : 'Remove',
              onRemove: () => onRemove(drafts[i]),
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(flex: 3, child: _labelled(sw ? 'Saizi au rangi' : 'Size or colour', ValueKey<String>('variant_label_$i'), sw ? 'mf. M / Nyekundu' : 'e.g. M / Red', drafts[i].label)),
                    SizedBox(width: 8.w),
                    Expanded(flex: 2, child: _labelled(sw ? 'Zipo ngapi?' : 'How many in stock?', ValueKey<String>('variant_qty_$i'), sw ? 'mf. 12' : 'e.g. 12', drafts[i].qty, digitsOnly: true)),
                  ],
                ),
                SizedBox(height: 8.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: _labelled(sw ? 'Bei yake (si lazima)' : 'Its own price (optional)', ValueKey<String>('variant_price_$i'), sw ? 'wazi = bei kuu' : 'empty = main price', drafts[i].price, money: true)),
                    SizedBox(width: 8.w),
                    Expanded(child: _labelled(sw ? 'Barcode (si lazima)' : 'Barcode (optional)', ValueKey<String>('variant_barcode_$i'), 'e.g. 6001234567890', drafts[i].barcode, keyboard: TextInputType.text)),
                  ],
                ),
              ],
            ),
          _addButton(const ValueKey<String>('variant_add'), drafts.isEmpty ? (sw ? 'Ongeza saizi / rangi' : 'Add a size / colour') : (sw ? 'Ongeza nyingine' : 'Add another'), onAdd, color),
        ],
      ],
    );
  }
}

/// The optional VAT rate of the product. Collapsed by default: nothing changes unless it is filled in.
///
/// [card]: drawn like the other extras of the product page, with a question a shop owner understands. A depot
/// keeps the plain collapsed row it has always had.
class VatSection extends StatelessWidget {
  const VatSection({super.key, required this.controller, required this.defaultPercent, required this.sw, this.card = false});

  final TextEditingController controller;

  /// What a product with no rate of its own is charged (the business's default).
  final double defaultPercent;
  final bool sw;
  final bool card;

  @override
  Widget build(BuildContext context) {
    final String fallback = defaultPercent == 0
        ? (sw ? 'Bila VAT' : 'no VAT')
        : '${defaultPercent.toStringAsFixed(defaultPercent % 1 == 0 ? 0 : 1)}%';

    final List<Widget> inside = <Widget>[
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
    ];

    // The page paints a coloured panel behind its fields; a ListTile needs a Material of its own between it and
    // that panel, or Flutter complains (and shows an error box in debug builds) that its ink would be hidden.
    return Material(
      type: MaterialType.transparency,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: card
            ? Container(
                decoration: ExtraOptionCard.decoration(ThemeConstants.successGreen),
                child: ExpansionTile(
                  key: const ValueKey<String>('vat_section'),
                  tilePadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 2.h),
                  childrenPadding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 4.h),
                  iconColor: Colors.white70,
                  collapsedIconColor: Colors.white70,
                  shape: const Border(),
                  collapsedShape: const Border(),
                  leading: ExtraOptionCard.badge(Icons.percent_rounded, ThemeConstants.successGreen),
                  title: Text(
                    sw ? 'Bidhaa hii ina VAT yake?' : 'Does this product have its own VAT rate?',
                    style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, fontSize: 14.sp, height: 1.25),
                  ),
                  subtitle: Padding(
                    padding: EdgeInsets.only(top: 3.h),
                    child: Text(
                      sw
                          ? 'Si lazima. Usipoigusa, inatumika VAT ya kawaida ya biashara ($fallback). Gusa kuifungua.'
                          : 'Optional. If you skip it, your usual rate applies ($fallback). Tap to open.',
                      style: ThemeConstants.captionStyle.copyWith(fontSize: 11.5.sp, color: Colors.white70, height: 1.3),
                    ),
                  ),
                  children: inside,
                ),
              )
            : ExpansionTile(
                key: const ValueKey<String>('vat_section'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                iconColor: Colors.white70,
                collapsedIconColor: Colors.white70,
                title: Text(sw ? 'VAT (si lazima)' : 'VAT (optional)', style: ThemeConstants.headingStyle.copyWith(fontSize: 14.sp)),
                children: inside,
              ),
      ),
    );
  }
}
