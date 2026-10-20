import 'package:flutter/material.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/responsive_helper.dart';
import '../../models/inv_product.dart';
import '../salon/salon_mode.dart';
import 'inventory_widgets.dart' show formatAmount;

/// How many products the dashboard lists before pointing to the full screen.
const int kProfitDashboardRows = 8;

/// Products in the order the profit table lists them. The dashboard and the full
/// "Faida kwa Bidhaa" screen both use this, so a product has the same rank in both.
List<InvProduct> rankedForProfit(final Iterable<InvProduct> products) =>
    <InvProduct>[...products]
      ..sort((final InvProduct a, final InvProduct b) =>
          b.quantity.compareTo(a.quantity));

/// "Faida kwa Bidhaa": rank, product, quantity, cost and expected profit.
///
/// The ONE place this table is drawn: the dashboard shows the first [limit] rows, the
/// full screen shows them all, with identical columns, colours and numbering.
class ProfitByProductTable extends StatelessWidget {
  const ProfitByProductTable({super.key, required this.products, this.limit});

  /// Already ranked, best first -- see [rankedForProfit].
  final List<InvProduct> products;

  /// Show only this many rows; null shows every product.
  final int? limit;

  static const Color _textPrimary = ThemeConstants.textPrimary;
  static const Color _textSecondary = ThemeConstants.textSecondary;

  @override
  Widget build(final BuildContext context) {
    // The text sizes below come from ResponsiveHelper, which needs the screen size first.
    // Do it here so this table works on whatever screen shows it, not only after the
    // dashboard has happened to initialise it.
    ResponsiveHelper.init(context);
    final LocalizationService loc = LocalizationService.instance;
    final List<InvProduct> shown =
        limit == null ? products : products.take(limit!).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(loc, isSalonMode(context)),
        for (int i = 0; i < shown.length; i++) _row(i + 1, shown[i]),
      ],
    );
  }

  Widget _header(final LocalizationService loc, final bool salon) {
    TextStyle style() => TextStyle(
          color: _textSecondary,
          fontSize: ResponsiveHelper.bodyS,
          fontWeight: FontWeight.w600,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 30,
            child: Text(loc.translate('rank'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style()),
          ),
          const SizedBox(width: 6),
          Expanded(flex: 4, child: Text(salon ? (loc.isSwahili ? 'Huduma / Bidhaa' : 'Service / Goods') : loc.translate('product'), style: style())),
          Expanded(
              flex: 2,
              child: Text(loc.translate('qty'),
                  textAlign: TextAlign.center, style: style())),
          Expanded(
              flex: 3,
              child: Text(loc.translate('cost'),
                  textAlign: TextAlign.end, style: style())),
          Expanded(
              flex: 3,
              child: Text(loc.translate('profit'),
                  textAlign: TextAlign.end, style: style())),
        ],
      ),
    );
  }

  Widget _row(final int rank, final InvProduct p) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 30,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: rank == 1
                      ? Colors.amber.shade300
                      : rank == 2
                          ? Colors.grey.shade300
                          : rank == 3
                              ? Colors.brown.shade300
                              : _textSecondary,
                  fontSize: ResponsiveHelper.bodyS,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    p.name,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: ResponsiveHelper.bodyS,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    p.unit.toUpperCase(),
                    style: const TextStyle(color: _textSecondary, fontSize: 10),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${p.quantity}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: ResponsiveHelper.bodyS,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                formatAmount(p.totalCostPrice),
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: Colors.amber.shade300,
                  fontSize: ResponsiveHelper.bodyS,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                formatAmount(p.totalExpectedProfit),
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: Colors.greenAccent.shade400,
                  fontSize: ResponsiveHelper.bodyS,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

/// The button under the dashboard's first [kProfitDashboardRows] products.
///
/// A quiet, full-width button: arrow and label in the app's cyan accent, a faint accent outline and no
/// fill, so it reads as "go on to the full list" without competing with the table above it.
///
/// Live only when there is more to see; otherwise it stays in place but muted and does
/// nothing, so the layout does not jump as products are added or removed.
class ProfitSeeAllButton extends StatelessWidget {
  const ProfitSeeAllButton({
    super.key,
    required this.total,
    required this.onPressed,
    this.limit = kProfitDashboardRows,
  });

  /// How many products there are in all.
  final int total;
  final int limit;
  final VoidCallback onPressed;

  bool get isActive => total > limit;

  @override
  Widget build(final BuildContext context) {
    final LocalizationService loc = LocalizationService.instance;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      // Across the whole card (the label is centred), not just as wide as its text.
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const ValueKey<String>('profit_see_all'),
          // null = disabled: Flutter then ignores taps and applies the muted style below.
          onPressed: isActive ? onPressed : null,
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: Text(
            '${isSalonMode(context) ? (loc.isSwahili ? 'Ona huduma na bidhaa zote' : 'See all services and goods') : loc.translate('see_all_products')} ($total)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: ThemeConstants.invAccent,
            disabledForegroundColor: Colors.white.withValues(alpha: 0.28),
            backgroundColor: Colors.transparent,
            side: BorderSide(
              color: isActive
                  ? ThemeConstants.invAccent.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.12),
            ),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ),
    );
  }
}
