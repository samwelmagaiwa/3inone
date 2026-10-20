import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../services/localization_service.dart';
import '../orders/orders_screen.dart';
import '../sales/returns_screen.dart';
import '../sales/sales_screen.dart';
import '../salon/salon_mode.dart';
import '../widgets/inventory_widgets.dart';

class SalesHubScreen extends StatelessWidget {
  const SalesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    // "Past orders" are purchase orders (suppliers, warehouses): a salon has none.
    final bool salon = isSalonMode(context);
    return InvTabScaffold(
      key: ValueKey<bool>(salon),
      title: '',
      tabs: [
        loc.translate('sales'),
        loc.translate('returns_and_parked'),
        if (!salon) loc.translate('past_orders'),
      ],
      views: [
        const SalesScreen(),
        const ReturnsScreen(),
        if (!salon) const InventoryOrdersScreen(),
      ],
    );
  }
}
