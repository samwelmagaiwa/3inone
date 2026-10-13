import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../constants/theme_constants.dart';
import '../../models/crates_owed.dart';

/// A short amber note saying how many crates a customer still has to return and
/// the deposit that covers. Draws nothing when they owe none, so it can sit under
/// any customer name without taking space.
class CratesOwedNote extends StatelessWidget {
  const CratesOwedNote({
    super.key,
    required this.owed,
    required this.swahili,
    this.isDepot = true,
  });

  final CratesOwed owed;
  final bool swahili;

  /// A depot says "the depot owes them"; any other business says "we owe them".
  final bool isDepot;

  static String _tzs(double v) => 'TZS ${v.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    if (owed.isNone) return const SizedBox.shrink();

    final List<String> lines = <String>[
      if (owed.held.isNotEmpty)
        swahili
            ? 'Makreti anayodaiwa: ${owed.heldSummary} (dhamana ${_tzs(owed.depositAtRisk)})'
            : 'Crates owed: ${owed.heldSummary} (deposit ${_tzs(owed.depositAtRisk)})',
      if (owed.owedToCustomer.isNotEmpty)
        swahili
            ? '${isDepot ? 'Ghala linamdai makreti' : 'Anatudai makreti'}: ${owed.owedToCustomerSummary}'
            : '${isDepot ? 'Depot owes them' : 'We owe them'}: ${owed.owedToCustomerSummary}',
    ];

    return Container(
      key: const ValueKey<String>('crates_owed_note'),
      width: double.infinity,
      margin: EdgeInsets.only(top: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: ThemeConstants.warningAmber.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: ThemeConstants.warningAmber.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.inventory_2_outlined,
              color: ThemeConstants.warningAmber, size: 16.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              lines.join('\n'),
              style: ThemeConstants.captionStyle.copyWith(
                color: ThemeConstants.warningAmber,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
