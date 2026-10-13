import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_product.dart';
import '../../providers/inventory_provider.dart';
import '../widgets/profit_by_product_table.dart';

/// "Faida kwa Bidhaa": the whole product profit table. The dashboard shows the first few
/// rows of the same table (same columns, same order, same numbering) and points here for
/// the rest.
class ProfitByProductScreen extends StatefulWidget {
  const ProfitByProductScreen({super.key});

  @override
  State<ProfitByProductScreen> createState() => _ProfitByProductScreenState();
}

class _ProfitByProductScreenState extends State<ProfitByProductScreen> {
  final LocalizationService _loc = LocalizationService.instance;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Normally the dashboard has loaded the products already; if this screen is the first
    // thing opened, load them rather than show an empty table.
    WidgetsBinding.instance.addPostFrameCallback((final Duration _) {
      if (mounted && context.read<InventoryProvider>().products.isEmpty) {
        _refresh();
      }
    });
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    await context.read<InventoryProvider>().fetchProducts();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(final BuildContext context) {
    final InventoryProvider inv = context.watch<InventoryProvider>();
    final List<InvProduct> products = rankedForProfit(inv.products);

    return ThemeConstants.buildScaffold(
      title: _loc.translate('profit_margins_title'),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _loc.translate('top_products_sorted'),
                      key: const ValueKey<String>('profit_subtitle'),
                      style: const TextStyle(
                          color: ThemeConstants.textSecondary, fontSize: 13),
                    ),
                  ),
                  if (products.isNotEmpty)
                    Text(
                      '${products.length}',
                      key: const ValueKey<String>('profit_count'),
                      style: const TextStyle(
                          color: ThemeConstants.textSecondary, fontSize: 13),
                    ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Colors.cyanAccent.withValues(alpha: 0.35), width: 1.4),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: products.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: _loading
                              ? const CircularProgressIndicator()
                              : Text(
                                  _loc.translate('no_data'),
                                  style: const TextStyle(color: Colors.white70),
                                ),
                        ),
                      )
                    : ProfitByProductTable(products: products),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
