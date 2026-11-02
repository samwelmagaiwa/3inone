import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_customer_debt.dart';

/// What a customer owes, in three parts a shop owner reads it in: the OLD debt (from before the app), the NEW debt (credit sales since)
/// and the TOTAL of both, each with what was owed, what was paid and what is left. With [thisSale] (a sale about to go on credit) it
/// also says what that adds and what the whole account becomes.
class CustomerDebtCard extends StatelessWidget {
  const CustomerDebtCard({super.key, required this.summary, this.thisSale = 0});

  final CustomerDebtSummary summary;

  /// The part of the sale being made that will be owed (0 for none).
  final double thisSale;

  static String _tsh(final double v) => 'TSH ${v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (final Match m) => ',')}';

  @override
  Widget build(final BuildContext context) {
    final LocalizationService loc = LocalizationService.instance;
    final CustomerDebtSummary after = summary.withSale(thisSale);

    return Container(
      key: const ValueKey<String>('customer_debt_card'),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: ThemeConstants.invFill,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: ThemeConstants.invBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (summary.hasOld) ...<Widget>[
            _part(loc.translate('cd_old_title'), const ValueKey<String>('debt_old'), summary.oldOriginal, summary.oldPaid, summary.oldLeft),
            _line(),
          ],
          if (summary.newBilled > 0 || thisSale > 0) ...<Widget>[
            _part(loc.translate('cd_new_title'), const ValueKey<String>('debt_new'), summary.newBilled, summary.newPaid, summary.newLeft),
            if (thisSale > 0) _row(loc.translate('cd_this_sale'), _tsh(thisSale), color: ThemeConstants.warningAmber, key: const ValueKey<String>('debt_this_sale')),
            _line(),
          ],
          Text(loc.translate('cd_total_title').toUpperCase(), style: ThemeConstants.captionStyle.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1)),
          SizedBox(height: 4.h),
          _row(loc.translate('cd_owed'), _tsh(after.totalOwed), key: const ValueKey<String>('debt_total_owed')),
          _row(loc.translate('cd_paid_all'), _tsh(after.totalPaid), color: ThemeConstants.successGreen, key: const ValueKey<String>('debt_total_paid')),
          _row(
            thisSale > 0 ? loc.translate('cd_balance_after') : loc.translate('cd_balance'),
            _tsh(after.totalLeft),
            color: after.totalLeft > 0 ? ThemeConstants.warningAmber : ThemeConstants.successGreen,
            bold: true,
            key: const ValueKey<String>('debt_total_left'),
          ),
        ],
      ),
    );
  }

  Widget _line() => Padding(padding: EdgeInsets.symmetric(vertical: 8.h), child: const Divider(height: 1, color: ThemeConstants.invBorder));

  Widget _part(final String title, final Key key, final double owed, final double paid, final double left) {
    final LocalizationService loc = LocalizationService.instance;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title.toUpperCase(), style: ThemeConstants.captionStyle.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1)),
        SizedBox(height: 4.h),
        _row(loc.translate('cd_owed'), _tsh(owed)),
        _row(loc.translate('cd_paid'), _tsh(paid), color: ThemeConstants.successGreen),
        _row(loc.translate('cd_left'), _tsh(left), color: left > 0 ? ThemeConstants.warningAmber : Colors.white70, bold: true),
      ],
    );
  }

  Widget _row(final String label, final String value, {final Color? color, final bool bold = false, final Key? key}) {
    return Padding(
      key: key,
      padding: EdgeInsets.symmetric(vertical: 2.h),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: ThemeConstants.captionStyle.copyWith(color: Colors.white70))),
          Text(value, style: ThemeConstants.bodyStyle.copyWith(color: color ?? Colors.white, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }
}
