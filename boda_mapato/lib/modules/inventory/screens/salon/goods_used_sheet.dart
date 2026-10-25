import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_product.dart';
import '../../models/inv_sale.dart';
import '../../providers/inventory_provider.dart';
import '../../services/salon_api.dart';
import '../products/add_edit_product_screen.dart';
import '../widgets/inventory_widgets.dart';
import 'salon_input.dart';
import 'salon_text.dart';

/// What the goods a service line used are called in a few words, for the cart line ("Dye ×3, Shampoo ×1").
String usedGoodsSummary(final List<InvUsedGood>? goods, {required final bool sw}) {
  if (goods == null) return sw ? 'Bidhaa: za kawaida' : 'Goods: the usual';
  final List<InvUsedGood> used = goods.where((InvUsedGood g) => g.qty > 0).toList();
  if (used.isEmpty) return sw ? 'Bidhaa: hakuna' : 'Goods: none';

  return '${sw ? 'Bidhaa' : 'Goods'}: ${used.map((InvUsedGood g) => '${g.name} ×${g.qty}').join(', ')}';
}

/// The salon's goods (shampoo, dye, oil...) listed for the till: say which ones this visit used up and how many. It starts
/// from what the service usually uses, so an ordinary visit is one tap on Save. Saves onto the cart line.
Future<void> pickGoodsUsed(BuildContext context, InventoryProvider inv, InvSaleItem item, {SalonApi? api}) async {
  List<Map<String, dynamic>> usual = <Map<String, dynamic>>[];
  try {
    usual = await (api ?? SalonApi()).usualGoods(item.productId);
  } on Exception {
    // no usual list: the till starts empty
  }
  if (!context.mounted) return;

  final Map<int, int> start = <int, int>{
    if (item.usedGoods != null)
      for (final InvUsedGood g in item.usedGoods!) g.productId: g.qty
    else
      for (final Map<String, dynamic> u in usual) (u['product_id'] as num).toInt(): (u['quantity'] as num).toInt() * (item.qty < 1 ? 1 : item.qty),
  };

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheet) => _GoodsSheet(item: item, inv: inv, start: start),
  );
}

class _GoodsSheet extends StatefulWidget {
  const _GoodsSheet({required this.item, required this.inv, required this.start});

  final InvSaleItem item;
  final InventoryProvider inv;
  final Map<int, int> start;

  @override
  State<_GoodsSheet> createState() => _GoodsSheetState();
}

class _GoodsSheetState extends State<_GoodsSheet> {
  late final Map<int, int> _qty = Map<int, int>.of(widget.start);
  String _find = '';

  /// The salon's goods (never its services), as the product list has them now.
  List<InvProduct> get _goods => widget.inv.products.where((InvProduct p) => !p.isService && p.status != 'inactive').toList();

  /// Nothing to pick from, or something missing: open the add-goods page, and come back to a list that includes it.
  Future<void> _addGoods() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<InventoryProvider>.value(value: widget.inv, child: const AddEditProductScreen()),
    ));
    await widget.inv.fetchProducts();
    if (mounted) setState(() {});
  }

  void _save() {
    widget.item.usedGoods = <InvUsedGood>[
      for (final InvProduct p in _goods)
        if ((_qty[p.id] ?? 0) > 0) InvUsedGood(productId: p.id, name: p.name, qty: _qty[p.id]!),
    ];
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = LocalizationService.instance.isSwahili;
    final List<InvProduct> shown = <InvProduct>[
      for (final InvProduct p in _goods)
        if (_find.isEmpty || p.name.toLowerCase().contains(_find.toLowerCase())) p,
    ]..sort((InvProduct a, InvProduct b) {
        final int ua = (_qty[a.id] ?? 0) > 0 ? 0 : 1;
        final int ub = (_qty[b.id] ?? 0) > 0 ? 0 : 1;

        return ua != ub ? ua - ub : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final double cost = <double>[for (final InvProduct p in _goods) (_qty[p.id] ?? 0) * p.costPrice].fold(0, (double a, double b) => a + b);

    return InvSheetShell(
      title: sw ? 'Bidhaa zilizotumika: ${widget.item.name}' : 'Goods used: ${widget.item.name}',
      children: <Widget>[
        Material(
          type: MaterialType.transparency,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(sw ? 'Chagua bidhaa zote zilizotumika kwa mtindo huu.' : 'Choose every item used for this style.', style: ThemeConstants.captionStyle),
            SizedBox(height: 8.h),
            TextField(
              key: const ValueKey<String>('goods_find'),
              style: salonInputStyle,
              decoration: salonInput(labelText: sw ? 'Tafuta bidhaa' : 'Search goods'),
              onChanged: (String v) => setState(() => _find = v.trim()),
            ),
            if (shown.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16.h),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(sw ? 'Hakuna bidhaa bado.' : 'No goods yet.', key: const ValueKey<String>('goods_empty'), style: ThemeConstants.captionStyle),
                  SizedBox(height: 8.h),
                  OutlinedButton.icon(key: const ValueKey<String>('goods_add_first'), onPressed: _addGoods, icon: const Icon(Icons.add), label: Text(sw ? 'Ongeza bidhaa' : 'Add goods')),
                ]),
              ),
            for (final InvProduct p in shown)
              ListTile(
                key: ValueKey<String>('good_${p.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(p.name, style: ThemeConstants.bodyStyle),
                subtitle: Text('${sw ? 'Zilizopo' : 'In stock'}: ${p.quantity}', style: ThemeConstants.captionStyle),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  IconButton(
                    key: ValueKey<String>('good_minus_${p.id}'),
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
                    onPressed: (_qty[p.id] ?? 0) > 0 ? () => setState(() => _qty[p.id] = (_qty[p.id] ?? 0) - 1) : null,
                  ),
                  SizedBox(width: 24.w, child: Text('${_qty[p.id] ?? 0}', textAlign: TextAlign.center, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800))),
                  IconButton(
                    key: ValueKey<String>('good_plus_${p.id}'),
                    icon: const Icon(Icons.add_circle_outline, color: ThemeConstants.invAccent),
                    onPressed: () => setState(() => _qty[p.id] = (_qty[p.id] ?? 0) + 1),
                  ),
                ]),
              ),
            if (shown.isNotEmpty)
              Align(alignment: Alignment.centerLeft, child: TextButton.icon(key: const ValueKey<String>('goods_add_more'), onPressed: _addGoods, icon: const Icon(Icons.add, size: 18), label: Text(sw ? 'Bidhaa mpya' : 'New goods'))),
            SizedBox(height: 8.h),
            Text('${sw ? 'Gharama ya bidhaa' : 'Cost of the goods'}: ${tsh(cost)}', key: const ValueKey<String>('goods_cost'), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
            SizedBox(height: 8.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton(key: const ValueKey<String>('goods_save'), onPressed: _save, child: Text(sw ? 'Hifadhi' : 'Save')),
            ),
          ]),
        ),
      ],
    );
  }
}
