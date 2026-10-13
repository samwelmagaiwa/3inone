import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/user_permissions.dart';
import '../../../../services/localization_service.dart';
import '../../providers/inventory_provider.dart';
import '../crates/crates_screen.dart';
import '../expenses/expenses_screen.dart';
import '../purchasing/purchasing_screen.dart';
import '../widgets/inventory_widgets.dart';

class SupplyChainHubScreen extends StatelessWidget {
  const SupplyChainHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    // Crates and empties are for businesses that sell returnable packaging (a depot); a shop or a wholesaler
    // of dry goods never sees them.
    final bool crates = context.select<InventoryProvider, bool>((InventoryProvider p) => p.capabilities.useCrates);
    return InvTabScaffold(
      title: '',
      tabs: [
        loc.translate('purchasing'),
        if (crates) loc.translate('crates_and_empties'),
        loc.translate('warehouse_expenses'),
      ],
      views: [
        const PurchasingScreen(),
        if (crates) const CratesScreen(),
        const ExpensesScreen(),
      ],
      // Purchasing — only users who can view purchasing orders.
      // Crates & Empties — anyone who tracks crate deposits (sales_officer included).
      // Warehouse Expenses — only users who can view the expense ledger.
      tabPermissions: [
        (UserPermissions p) => p.has('inv_view_purchasing'),
        if (crates) null,
        (UserPermissions p) =>
            p.has('inv_view_expenses') || p.has('inv_manage_expenses'),
      ],
    );
  }
}
