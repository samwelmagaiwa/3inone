import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/user_permissions.dart';
import '../../../../services/localization_service.dart';
import '../brands/brands_screen.dart';
import '../categories/categories_screen.dart';
import '../products/products_screen.dart';
import '../widgets/inventory_widgets.dart';
import '../salon/salon_mode.dart';

class ProductsHubScreen extends StatelessWidget {
  const ProductsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return InvTabScaffold(
      title: '',
      tabs: [
        isSalonMode(context) ? (loc.isSwahili ? 'Huduma na Bidhaa' : 'Services & Goods') : loc.translate('products'),
        loc.translate('categories'),
        loc.translate('brands'),
      ],
      views: const [
        ProductsScreen(),
        InventoryCategoriesScreen(),
        BrandsScreen(),
      ],
      // Categories and Brands are management screens — only users who can
      // manage the product catalogue should see them as tabs.
      tabPermissions: [
        null, // Products — visible to anyone who can see the hub
        (UserPermissions p) => p.has('inv_manage_products'),
        (UserPermissions p) => p.has('inv_manage_products'),
      ],
    );
  }
}
