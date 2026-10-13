import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_sale.dart';

/// Everything the confirmation card shows. Built from the cart just before
/// checkout, so what the user confirms is exactly what will be sent.
class SaleConfirmation {
  const SaleConfirmation({
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paymentMode,
    this.customerName,
    this.paidNow = 0,
    this.crateTypeName,
    this.crateQty,
    this.tax = 0,
    this.taxIncluded = true,
  });

  final List<InvSaleItem> items;
  final double subtotal;
  final double discount;
  final double total;

  /// The VAT on this sale, and whether the prices already contain it (otherwise it is added to the total).
  final double tax;
  final bool taxIncluded;

  /// `cash`, `debt` or `partial`.
  final String paymentMode;
  final String? customerName;

  /// Amount received now (only meaningful for `partial`).
  final double paidNow;

  /// Crates the customer owes the depot, when they did not bring empties.
  final String? crateTypeName;
  final int? crateQty;

  double get balance {
    switch (paymentMode) {
      case 'debt':
        return total;
      case 'partial':
        return (total - paidNow).clamp(0, total).toDouble();
      default:
        return 0;
    }
  }
}

/// Asks "are you sure?" with the amount being sold. Resolves true only on Yes.
Future<bool> showSaleConfirmation(
  BuildContext context,
  SaleConfirmation sale, {
  bool? swahili,
}) async {
  final bool sw = swahili ?? LocalizationService.instance.isSwahili;
  final bool? ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) => _SaleConfirmationDialog(sale: sale, sw: sw),
  );
  return ok ?? false;
}

String _tzs(double v) => 'TZS ${v.toStringAsFixed(0)}';

class _SaleConfirmationDialog extends StatelessWidget {
  const _SaleConfirmationDialog({required this.sale, required this.sw});

  final SaleConfirmation sale;
  final bool sw;

  String get _modeLabel {
    switch (sale.paymentMode) {
      case 'debt':
        return sw ? 'Deni' : 'On debt';
      case 'partial':
        return sw ? 'Malipo ya sehemu' : 'Part payment';
      default:
        return sw ? 'Pesa taslimu' : 'Cash';
    }
  }

  @override
  Widget build(BuildContext context) {
    final double maxListHeight = MediaQuery.of(context).size.height * 0.30;

    return Dialog(
      backgroundColor: ThemeConstants.primaryBlue,
      insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Details scroll on small screens; Yes / No below always stay in view.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(Icons.shopping_cart_checkout,
                            color: ThemeConstants.invAccent, size: 24.sp),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            sw ? 'Thibitisha mauzo' : 'Confirm sale',
                            style: ThemeConstants.bodyStyle.copyWith(
                                fontWeight: FontWeight.bold, fontSize: 18.sp),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      sw
                          ? 'Unakaribia kuuza bidhaa zifuatazo:'
                          : 'You are about to sell the following:',
                      style: ThemeConstants.captionStyle,
                    ),
                    SizedBox(height: 10.h),
                    Container(
                      decoration: ThemeConstants.invCardDecoration,
                      padding: EdgeInsets.all(12.w),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ConstrainedBox(
                            constraints:
                                BoxConstraints(maxHeight: maxListHeight),
                            child: ListView.separated(
                              key: const ValueKey<String>('sale_confirm_items'),
                              shrinkWrap: true,
                              itemCount: sale.items.length,
                              separatorBuilder: (_, __) =>
                                  SizedBox(height: 6.h),
                              itemBuilder: (_, int i) {
                                final InvSaleItem it = sale.items[i];
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Expanded(
                                      child: Text(
                                          '${it.qty}${(it.unitName ?? '').isEmpty ? '' : ' ${it.unitName}'} × ${it.name}',
                                          style: ThemeConstants.bodyStyle),
                                    ),
                                    SizedBox(width: 8.w),
                                    Text(_tzs(it.total),
                                        style: ThemeConstants.bodyStyle),
                                  ],
                                );
                              },
                            ),
                          ),
                          Divider(
                              color: ThemeConstants.invBorder, height: 20.h),
                          _row(sw ? 'Jumla ndogo' : 'Subtotal',
                              _tzs(sale.subtotal)),
                          if (sale.discount > 0) ...<Widget>[
                            SizedBox(height: 4.h),
                            _row(sw ? 'Punguzo' : 'Discount',
                                '- ${_tzs(sale.discount)}'),
                          ],
                          if (sale.tax > 0) ...<Widget>[
                            SizedBox(height: 4.h),
                            KeyedSubtree(
                              key: const ValueKey<String>('sale_confirm_vat'),
                              child: _row(
                                  sale.taxIncluded
                                      ? (sw ? 'VAT (imo kwenye bei)' : 'VAT (included in prices)')
                                      : (sw ? 'VAT (inaongezwa)' : 'VAT (added)'),
                                  _tzs(sale.tax)),
                            ),
                          ],
                          SizedBox(height: 8.h),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                sw ? 'JUMLA' : 'TOTAL',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.bold),
                              ),
                              // Shrinks instead of overflowing when the amount is very large.
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    _tzs(sale.total),
                                    key: const ValueKey<String>(
                                        'sale_confirm_total'),
                                    style: TextStyle(
                                        color: ThemeConstants.invAccent,
                                        fontSize: 22.sp,
                                        fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 10.h),
                    _row(sw ? 'Malipo' : 'Payment', _modeLabel),
                    if ((sale.customerName ?? '')
                        .trim()
                        .isNotEmpty) ...<Widget>[
                      SizedBox(height: 4.h),
                      _row(
                          sw ? 'Mteja' : 'Customer', sale.customerName!.trim()),
                    ],
                    if (sale.paymentMode == 'partial') ...<Widget>[
                      SizedBox(height: 4.h),
                      _row(
                          sw ? 'Amelipa sasa' : 'Paid now', _tzs(sale.paidNow)),
                    ],
                    if (sale.balance > 0) ...<Widget>[
                      SizedBox(height: 4.h),
                      _row(sw ? 'Deni litakalobaki' : 'Balance owed',
                          _tzs(sale.balance),
                          valueColor: ThemeConstants.warningAmber),
                    ],
                    if (sale.crateQty != null) ...<Widget>[
                      SizedBox(height: 4.h),
                      _row(
                        sw ? 'Makreti anayodaiwa' : 'Crates owed',
                        '${sale.crateQty} × ${sale.crateTypeName ?? ''}'.trim(),
                        valueColor: ThemeConstants.warningAmber,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: 16.h),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey<String>('sale_confirm_no'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: ThemeConstants.invBorder),
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r)),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(sw ? 'Hapana' : 'No'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: ElevatedButton(
                    key: const ValueKey<String>('sale_confirm_yes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeConstants.invAccent,
                      foregroundColor: Colors.black,
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r)),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(sw ? 'Ndiyo, uza' : 'Yes, sell',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: ThemeConstants.captionStyle),
          SizedBox(width: 12.w),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: ThemeConstants.bodyStyle.copyWith(color: valueColor),
            ),
          ),
        ],
      );
}
