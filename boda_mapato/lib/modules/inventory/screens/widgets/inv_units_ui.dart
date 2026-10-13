import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../constants/theme_constants.dart';
import '../../models/inv_capabilities.dart';
import '../../models/inv_product.dart';
import '../../models/inv_product_unit.dart';

/// Stock as a person says it, in whole units: "12 kg 500 g", "4 crate 4 bottle".
///
/// Stock is stored as a whole number of the smallest unit (grams, bottles), so the picture of it is built
/// from the selling units, biggest first -- never with a decimal point. Only goods by weight or volume, and
/// businesses that are not depots, get this picture: a depot keeps showing the plain number it always did.
String stockLabel(InvProduct product, List<InvProductUnit> units, InvCapabilities caps) =>
    stockLabelOf(product.quantity, baseUnit: product.unit, weighed: product.isWeighed, units: units, caps: caps);

/// [stockLabel] for a bare number of the smallest unit (a quantity being typed, a total that does not exist yet).
String stockLabelOf(
  int total, {
  required String baseUnit,
  required bool weighed,
  required List<InvProductUnit> units,
  required InvCapabilities caps,
}) {
  if (!(weighed || !caps.isDepot)) return '$total';

  final List<InvProductUnit> bigger = units.where((InvProductUnit u) => u.isActive && !u.isBase && u.factor > 1).toList()
    ..sort((InvProductUnit a, InvProductUnit b) => b.factor.compareTo(a.factor));
  if (bigger.isEmpty || total <= 0) return '$total';

  int left = total;
  final List<String> parts = <String>[];
  for (final InvProductUnit u in bigger) {
    final int n = left ~/ u.factor;
    if (n > 0) {
      parts.add('$n ${u.name}');
      left -= n * u.factor;
    }
  }
  if (left > 0 || parts.isEmpty) parts.add('$left $baseUnit');

  return parts.join(' ');
}

/// Ask for a whole number (digits only: no fractions, ever). Returns null if cancelled.
Future<int?> askWholeNumber(
  BuildContext context, {
  required String title,
  required int initial,
  required String okLabel,
  required String cancelLabel,
}) async {
  // No controller owned by this function: it would be disposed while the dialog is still animating out.
  String draft = '$initial';
  return showDialog<int>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      backgroundColor: ThemeConstants.primaryBlue,
      title: Text(title, style: ThemeConstants.headingStyle),
      content: TextFormField(
        key: const ValueKey<String>('whole_number_field'),
        initialValue: draft,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
        style: ThemeConstants.bodyStyle,
        decoration: ThemeConstants.invInputDecoration(title),
        onChanged: (String v) => draft = v,
        onFieldSubmitted: (String v) => Navigator.pop(ctx, int.tryParse(v)),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(cancelLabel)),
        TextButton(
          key: const ValueKey<String>('whole_number_ok'),
          onPressed: () => Navigator.pop(ctx, int.tryParse(draft)),
          child: Text(okLabel),
        ),
      ],
    ),
  );
}

/// One chip per way to sell a product (crate / bottle, kg / g): pick the one the customer asks for.
class UnitChips extends StatelessWidget {
  const UnitChips({
    super.key,
    required this.units,
    required this.selectedUnitId,
    required this.baseLabel,
    required this.onSelected,
  });

  final List<InvProductUnit> units;

  /// The selected unit's id; null = the base unit.
  final int? selectedUnitId;

  /// What to call the base unit if it is not in [units].
  final String baseLabel;
  final ValueChanged<InvProductUnit> onSelected;

  @override
  Widget build(BuildContext context) {
    // Biggest first: "crate  bottle", "kg  g".
    final List<InvProductUnit> ordered = <InvProductUnit>[...units]
      ..sort((InvProductUnit a, InvProductUnit b) => (b.isBase ? 1 : b.factor).compareTo(a.isBase ? 1 : a.factor));

    return Wrap(
      spacing: 6.w,
      runSpacing: 4.h,
      children: <Widget>[
        for (final InvProductUnit u in ordered)
          ChoiceChip(
            key: ValueKey<String>('unit_chip_${u.id}'),
            label: Text(u.isBase && u.name.isEmpty ? baseLabel : u.name, style: TextStyle(fontSize: 12.sp)),
            selected: u.isBase ? selectedUnitId == null : selectedUnitId == u.id,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) => onSelected(u),
          ),
      ],
    );
  }
}
