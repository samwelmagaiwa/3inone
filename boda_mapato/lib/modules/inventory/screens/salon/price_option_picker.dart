import 'package:flutter/material.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_product.dart';
import '../../providers/inventory_provider.dart';
import '../widgets/inventory_widgets.dart';
import '../../models/inv_sale.dart';
import '../../services/salon_api.dart';
import 'goods_used_sheet.dart';
import 'salon_text.dart';

/// Put a product in the cart. A service that comes at several prices (short, medium or long hair) first asks which
/// one, and the line carries that price and name; anything else goes straight in, as it always did. Returns false
/// when the person chose nothing, so the caller can leave the cart alone.
Future<bool> addToCartAskingPrice(BuildContext context, InventoryProvider inv, InvProduct product, {SalonApi? api}) async {
  if (!product.isService || product.priceOptions.isEmpty) {
    inv.addProductToCart(product);
    await _askGoods(context, inv, product, api);
    return true;
  }

  final bool sw = LocalizationService.instance.isSwahili;
  // `null` inside the box = the usual price; no box at all = the sheet was closed.
  final _Choice? chosen = await showModalBottomSheet<_Choice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheet) => InvSheetShell(
      title: product.name,
      children: <Widget>[
        Material(
          type: MaterialType.transparency,
          child: Column(
            children: <Widget>[
              ListTile(
                key: const ValueKey<String>('price_usual'),
                contentPadding: EdgeInsets.zero,
                title: Text(sw ? 'Bei ya kawaida' : 'Usual price', style: ThemeConstants.bodyStyle),
                trailing: Text(tsh(product.sellingPrice), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(sheet, const _Choice(null)),
              ),
              for (final PriceOption o in product.priceOptions)
                ListTile(
                  key: ValueKey<String>('price_option_${o.label}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(o.label, style: ThemeConstants.bodyStyle),
                  trailing: Text(tsh(o.price), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                  onTap: () => Navigator.pop(sheet, _Choice(o)),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  if (chosen == null) return false;
  inv.addProductToCart(product, option: chosen.option);
  if (context.mounted) await _askGoods(context, inv, product, api);
  return true;
}

/// A salon service has just gone in the cart: say which goods this visit used, starting from the usual ones. (Only for a
/// service that was not already picked for this client in this cart.)
Future<void> _askGoods(BuildContext context, InventoryProvider inv, InvProduct product, SalonApi? api) async {
  if (!product.isService || !inv.salonMode || !context.mounted) return;
  final InvSaleItem? line = inv.cart.where((InvSaleItem i) => i.productId == product.id && i.usedGoods == null).lastOrNull;
  if (line == null) return;
  await pickGoodsUsed(context, inv, line, api: api);
}

class _Choice {
  const _Choice(this.option);

  final PriceOption? option;
}
