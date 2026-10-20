import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../models/user_permissions.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_product.dart';
import '../../providers/inventory_provider.dart';
import '../widgets/inv_units_ui.dart';
import '../widgets/inventory_widgets.dart';
import 'add_edit_product_screen.dart';
import 'business_kind_chooser.dart';
import '../../providers/depot_provider.dart';
import '../scanning/barcode_scanner_screen.dart';
import 'product_units_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  int _page = 0;
  final int _pageSize = 8;
  String _query = '';

  Future<void> _scanToSearch(BuildContext context) async {
    final loc = LocalizationService.instance;
    final String? code =
        await scanBarcode(context, title: loc.translate('scan_barcode'));
    if (code == null || code.isEmpty || !context.mounted) return;

    final result = await context.read<DepotProvider>().resolveBarcode(code);
    if (result == null) {
      if (context.mounted) {
        ThemeConstants.showErrorSnackBar(
            context, loc.translate('barcode_not_found'));
      }
      return;
    }
    setState(() {
      _query = result.productName.isNotEmpty ? result.productName : code;
      _page = 0;
    });
  }

  /// Opens the product page. The owner is asked first what kind of business this is (the page is laid out by
  /// the answer); staff cannot change it, and an older server does not know kinds, so for them the page
  /// just opens.
  Future<void> _addProduct(BuildContext context) async {
    final DepotProvider depot = context.read<DepotProvider>();
    final bool owner = context.read<AuthProvider>().user?.isBusinessOwner ?? false;
    if (owner) {
      // Landing straight on this screen, the settings may not have been read yet.
      if (depot.settings.isEmpty) await depot.fetchSettings();
      if (!context.mounted) return;
      if (depot.settings.containsKey('inventory_type')) {
        final bool picked = await chooseBusinessKind(
          context,
          current: depot.capabilities.inventoryType,
          onChange: depot.changeBusinessKind,
          sw: LocalizationService.instance.isSwahili,
        );
        if (!picked || !context.mounted) return;
        // The product page reads the kind through the inventory provider: have the new one before it opens.
        await context.read<InventoryProvider>().fetchCapabilities();
        if (!context.mounted) return;
      }
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const AddEditProductScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final inv = context.watch<InventoryProvider>();
    final perms = context.select<AuthProvider, UserPermissions>((AuthProvider a) => a.permissions);
    final canManage = perms.has('inv_manage_products');
    // Add-product is also open to the create-only grant (sales_officer, or any
    // account an admin toggled "Add New Products" on for); the edit/delete
    // menu below stays canManage-only.
    final canCreate = canManage || perms.has('inv_create_products');
    final filtered = inv.products.where((p) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          p.barcode.toLowerCase().contains(q);
    }).toList();
    final start = _page * _pageSize;
    final end = (start + _pageSize) > filtered.length
        ? filtered.length
        : (start + _pageSize);
    final slice =
        start < filtered.length ? filtered.sublist(start, end) : <InvProduct>[];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() {
                      _query = v;
                      _page = 0;
                    }),
                    decoration: ThemeConstants.invInputDecoration(
                            loc.translate('search_products'))
                        .copyWith(
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white70),
                    ),
                    style: ThemeConstants.bodyStyle,
                  ),
                ),
                SizedBox(width: 8.w),
                IconButton(
                  tooltip: loc.translate('scan_barcode'),
                  onPressed: () => _scanToSearch(context),
                  icon:
                      const Icon(Icons.qr_code_scanner, color: Colors.white70),
                ),
                SizedBox(width: 4.w),
                if (canCreate)
                  ElevatedButton.icon(
                    onPressed: () => _addProduct(context),
                    icon: Icon(Icons.add, size: 18.sp),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        loc.translate('add_product'),
                        maxLines: 1,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 16.h),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    ListView.separated(
                      itemCount: slice.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      separatorBuilder: (_, __) => SizedBox(height: 8.h),
                      itemBuilder: (context, index) {
                        final p = slice[index];
                        // A service has no shelf: it is never "low".
                        final isLow = !p.isService && p.quantity < p.minStock;
                        return InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              // its selling units are for goods; a service is edited instead
                              builder: (_) => p.isService && canManage ? AddEditProductScreen(product: p) : ProductUnitsScreen(product: p),
                            ),
                          ),
                          borderRadius: BorderRadius.circular(20.r),
                          child: Container(
                            decoration: ThemeConstants.glassCardDecoration,
                            padding: EdgeInsets.all(12.w),
                            child: Row(
                              children: [
                                Icon(p.isService ? Icons.content_cut_rounded : Icons.inventory_2_outlined,
                                    color: Colors.white70, size: 22.sp),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AutoSizeText(p.name,
                                          style: ThemeConstants.bodyStyle,
                                          maxLines: 1),
                                      SizedBox(height: 4.h),
                                      AutoSizeText(
                                          p.isService
                                              ? '${loc.isSwahili ? 'Huduma' : 'Service'} • TSH ${p.sellingPrice.toStringAsFixed(0)}${p.durationMinutes == null ? '' : ' • ${p.durationMinutes} min'}'
                                              : '${loc.translate('sku')}: ${p.sku} • ${loc.translate('quantity')}: ${stockLabel(p, inv.unitsOf(p.id), inv.capabilities)}',
                                          style: ThemeConstants.captionStyle,
                                          maxLines: 1,
                                          minFontSize: 10),
                                    ],
                                  ),
                                ),
                                if (isLow)
                                  Flexible(
                                    child: InvBadge(
                                      label: loc.translate('low_stock'),
                                      color: Colors.orange.shade600,
                                    ),
                                  ),
                                SizedBox(width: 4.w),
                                if (canManage)
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert,
                                        color: Colors.white54, size: 20),
                                    color: ThemeConstants.primaryBlue,
                                    onSelected: (action) async {
                                      if (action == 'edit') {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AddEditProductScreen(product: p),
                                          ),
                                        );
                                      } else if (action == 'delete') {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (dCtx) => AlertDialog(
                                            backgroundColor:
                                                ThemeConstants.primaryBlue,
                                            title: Text(
                                                loc.translate('confirm_delete'),
                                                style: ThemeConstants.bodyStyle
                                                    .copyWith(
                                                        fontWeight:
                                                            FontWeight.bold)),
                                            content: Text(
                                                '${loc.translate('delete')} "${p.name}"?',
                                                style:
                                                    ThemeConstants.captionStyle),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(dCtx, false),
                                                child: Text(
                                                    loc.translate('cancel'),
                                                    style: const TextStyle(
                                                        color: Colors.white70)),
                                              ),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        ThemeConstants.errorRed),
                                                onPressed: () =>
                                                    Navigator.pop(dCtx, true),
                                                child: Text(
                                                    loc.translate('delete')),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok == true && context.mounted) {
                                          final inv = context.read<InventoryProvider>();
                                          final err = await inv.deleteProduct(p.id);
                                          if (!context.mounted) return;
                                          if (err == null) {
                                            ThemeConstants.showSuccessSnackBar(
                                                context, loc.translate('deleted'));
                                          } else if (err.toLowerCase().contains('sales history')) {
                                            // Product has sales — offer to archive instead
                                            final archive = await showDialog<bool>(
                                              context: context,
                                              builder: (dCtx) => AlertDialog(
                                                backgroundColor: ThemeConstants.primaryBlue,
                                                title: Text(LocalizationService.instance.translate('inv_cannot_delete'),
                                                    style: ThemeConstants.bodyStyle.copyWith(
                                                        fontWeight: FontWeight.bold)),
                                                content: Text(
                                                  '${LocalizationService.instance.translateWith('inv_has_sales_history', <Object?>[p.name])}\n\n'
            '${LocalizationService.instance.translate('inv_archive_instead')}',
                                                  style: ThemeConstants.captionStyle,
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(dCtx, false),
                                                    child: Text(LocalizationService.instance.translate('cancel_2'),
                  style: const TextStyle(color: Colors.white70)),
                                                  ),
                                                  ElevatedButton(
                                                    style: ElevatedButton.styleFrom(
                                                        backgroundColor: Colors.orange),
                                                    onPressed: () => Navigator.pop(dCtx, true),
                                                    child: Text(LocalizationService.instance.translate('inv_archive')),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (archive == true && context.mounted) {
                                              final err2 = await inv.deleteProduct(p.id, force: true);
                                              if (context.mounted) {
                                                if (err2 == null) {
                                                  ThemeConstants.showSuccessSnackBar(
                                                      context, LocalizationService.instance.translate('inv_product_archived'));
                                                } else {
                                                  ThemeConstants.showErrorSnackBar(context, err2);
                                                }
                                              }
                                            }
                                          } else {
                                            ThemeConstants.showErrorSnackBar(context, err);
                                          }
                                        }
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Row(children: [
                                          const Icon(Icons.edit_outlined,
                                              color: Colors.white70, size: 18),
                                          SizedBox(width: 8.w),
                                          Text(loc.translate('edit'),
                                              style: ThemeConstants.captionStyle),
                                        ]),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(children: [
                                          Icon(Icons.delete_outline,
                                              color: ThemeConstants.errorRed,
                                              size: 18),
                                          SizedBox(width: 8.w),
                                          Text(loc.translate('delete'),
                                              style: ThemeConstants.captionStyle
                                                  .copyWith(
                                                      color: ThemeConstants
                                                          .errorRed)),
                                        ]),
                                      ),
                                    ],
                                  )
                                else
                                  Icon(Icons.chevron_right,
                                    color: Colors.white38, size: 20.sp),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            '${filtered.isEmpty ? 0 : (start + 1)}-$end / ${filtered.length}',
                            style: ThemeConstants.captionStyle),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _page > 0
                                  ? () => setState(() => _page -= 1)
                                  : null,
                              icon: const Icon(Icons.chevron_left,
                                  color: Colors.white70),
                            ),
                            IconButton(
                              onPressed: end < filtered.length
                                  ? () => setState(() => _page += 1)
                                  : null,
                              icon: const Icon(Icons.chevron_right,
                                  color: Colors.white70),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
