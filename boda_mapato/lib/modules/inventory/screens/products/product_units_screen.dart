import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../models/user_permissions.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_product.dart';
import '../../models/inv_product_unit.dart';
import '../../providers/inventory_provider.dart';
import '../stock/batch_transfer_history_screen.dart';
import '../widgets/inventory_widgets.dart';
import 'add_edit_product_screen.dart';

/// Area 2 — selling units (bottle / pack / crate) and their tiered prices
/// for one product, plus the price-change history.
class ProductUnitsScreen extends StatefulWidget {
  const ProductUnitsScreen({required this.product, super.key});

  final InvProduct product;

  @override
  State<ProductUnitsScreen> createState() => _ProductUnitsScreenState();
}

class _ProductUnitsScreenState extends State<ProductUnitsScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await context.read<InventoryProvider>().fetchUnits(widget.product.id);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InventoryProvider inv = context.watch<InventoryProvider>();
    final UserPermissions perms = context.select<AuthProvider, UserPermissions>((AuthProvider a) => a.permissions);
    final bool canManage = perms.has('inv_manage_products');
    final List<InvProductUnit> units = inv.unitsOf(widget.product.id);

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: ThemeConstants.textPrimary),
        title: AutoSizeText(
          loc.translate('units_and_pricing'),
          maxLines: 1,
          minFontSize: 14,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ThemeConstants.textPrimary,
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: <Widget>[
          if (canManage)
            IconButton(
              tooltip: loc.translate('edit_product'),
              icon: const Icon(Icons.edit_outlined,
                  color: ThemeConstants.textPrimary),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AddEditProductScreen(product: widget.product),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              heroTag: 'product_units_fab',
              backgroundColor: ThemeConstants.primaryOrange,
              onPressed: () => _openUnitSheet(),
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                loc.translate('add_unit'),
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              )
            : RefreshIndicator(
                onRefresh: _load,
                backgroundColor: Colors.white,
                color: ThemeConstants.primaryBlue,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 88.h),
                  itemCount: units.length + 1,
                  separatorBuilder: (_, __) => SizedBox(height: 10.h),
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) {
                      return _ProductHeaderCard(product: widget.product);
                    }
                    final InvProductUnit unit = units[index - 1];
                    return _UnitCard(
                      unit: unit,
                      baseUnitName: widget.product.unit,
                      canManage: canManage,
                      isWholesale: widget.product.isWholesale,
                      productSellingPrice: widget.product.sellingPrice,
                      onEdit: () => _openUnitSheet(unit: unit),
                      onSetPrice: (InvPriceTier tier) =>
                          _openPriceSheet(unit, tier),
                      onHistory: () => _openHistory(unit),
                      onTransferHistory: _openTransferHistory,
                      onDelete: unit.isBase ? null : () => _confirmDelete(unit),
                    );
                  },
                ),
              ),
      ),
    );
  }

  Future<void> _openUnitSheet({InvProductUnit? unit}) async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UnitFormSheet(
        productId: widget.product.id,
        unit: unit,
      ),
    );
    if ((saved ?? false) && mounted) {
      _showSnack(LocalizationService.instance.translate('saved'));
    }
  }

  Future<void> _openPriceSheet(InvProductUnit unit, InvPriceTier tier) async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PriceFormSheet(
        productId: widget.product.id,
        unit: unit,
        tier: tier,
      ),
    );
    if ((saved ?? false) && mounted) {
      _showSnack(LocalizationService.instance.translate('price_saved'));
    }
  }

  Future<void> _openHistory(InvProductUnit unit) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _PriceHistorySheet(
          productId: widget.product.id,
          unit: unit,
        ),
      );

  void _openTransferHistory() => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => BatchTransferHistoryScreen(product: widget.product),
        ),
      );

  Future<void> _confirmDelete(InvProductUnit unit) async {
    final LocalizationService loc = LocalizationService.instance;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(loc.translate('remove_unit'),
            style: ThemeConstants.headingStyle),
        content: Text(
          '${loc.translate('remove_unit_confirm')} "${unit.name}"?',
          style: ThemeConstants.bodyStyle,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              loc.translate('delete'),
              style: const TextStyle(color: ThemeConstants.errorText),
            ),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) {
      return;
    }
    final bool done = await context
        .read<InventoryProvider>()
        .deleteUnit(widget.product.id, unit.id);
    if (mounted) {
      _showSnack(loc.translate(done ? 'deleted' : 'operation_failed'));
    }
  }

  void _showSnack(String message) => ThemeConstants.showInfoSnackBar(
        context,
        message,
      );
}

/// Compact summary of the product the units belong to.
class _ProductHeaderCard extends StatelessWidget {
  const _ProductHeaderCard({required this.product});

  final InvProduct product;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    return Container(
      decoration: ThemeConstants.glassCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Row(
        children: <Widget>[
          Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: const Icon(Icons.inventory_2_outlined, color: Colors.white),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AutoSizeText(
                  product.name,
                  maxLines: 1,
                  minFontSize: 12,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.bodyStyle
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2.h),
                AutoSizeText(
                  '${loc.translate('sku')}: ${product.sku}  •  '
                  '${loc.translate('base_unit')}: ${product.unit}',
                  maxLines: 1,
                  minFontSize: 10,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.captionStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One selling unit with its three price tiers.
class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.unit,
    required this.baseUnitName,
    required this.canManage,
    required this.isWholesale,
    required this.onEdit,
    required this.onSetPrice,
    required this.onHistory,
    required this.onTransferHistory,
    this.onDelete,
    this.productSellingPrice,
  });

  final InvProductUnit unit;
  final String baseUnitName;
  final bool canManage;
  final bool isWholesale;
  final double? productSellingPrice;
  final VoidCallback onEdit;
  final ValueChanged<InvPriceTier> onSetPrice;
  final VoidCallback onHistory;
  final VoidCallback onTransferHistory;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    return Container(
      decoration: ThemeConstants.glassCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    Flexible(
                      child: AutoSizeText(
                        unit.name,
                        maxLines: 1,
                        minFontSize: 12,
                        overflow: TextOverflow.ellipsis,
                        style: ThemeConstants.bodyStyle
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (unit.isBase) ...<Widget>[
                      SizedBox(width: 6.w),
                      _Chip(
                        label: loc.translate('base'),
                        color: ThemeConstants.successGreen,
                      ),
                    ],
                    if (!unit.isActive) ...<Widget>[
                      SizedBox(width: 6.w),
                      _Chip(
                        label: loc.translate('inactive'),
                        color: ThemeConstants.errorRed,
                      ),
                    ],
                  ],
                ),
              ),
              if (canManage)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white70),
                  color: ThemeConstants.primaryBlue,
                  onSelected: (String value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                      case 'history':
                        onHistory();
                      case 'transfers':
                        onTransferHistory();
                      case 'delete':
                        onDelete?.call();
                    }
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text(loc.translate('edit'),
                          style: ThemeConstants.bodyStyle),
                    ),
                    PopupMenuItem<String>(
                      value: 'history',
                      child: Text(loc.translate('price_history'),
                          style: ThemeConstants.bodyStyle),
                    ),
                    PopupMenuItem<String>(
                      value: 'transfers',
                      child: Text(loc.translate('batch_transfer_history'),
                          style: ThemeConstants.bodyStyle),
                    ),
                    if (onDelete != null)
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Text(
                          loc.translate('delete'),
                          style:
                              const TextStyle(color: ThemeConstants.errorText),
                        ),
                      ),
                  ],
                )
              else
                IconButton(
                  onPressed: onHistory,
                  icon: const Icon(Icons.history, color: Colors.white70),
                  tooltip: loc.translate('price_history'),
                ),
            ],
          ),
          SizedBox(height: 2.h),
          AutoSizeText(
            unit.isBase
                ? loc.translate('stocking_unit')
                : '1 ${unit.name} = ${unit.factor} $baseUnitName',
            maxLines: 1,
            minFontSize: 10,
            overflow: TextOverflow.ellipsis,
            style: ThemeConstants.captionStyle,
          ),
          if (unit.barcode.isNotEmpty) ...<Widget>[
            SizedBox(height: 2.h),
            AutoSizeText(
              '${loc.translate('barcode')}: ${unit.barcode}',
              maxLines: 1,
              minFontSize: 10,
              overflow: TextOverflow.ellipsis,
              style: ThemeConstants.captionStyle,
            ),
          ],
          SizedBox(height: 10.h),
          Row(
            children: <Widget>[
              Expanded(
                child: _PriceTile(
                  label: loc.translate('retail'),
                  // wholesale mode: retail is inactive — show dash
                  price: isWholesale ? null : unit.priceFor(InvPriceTier.retail),
                  inactive: isWholesale,
                  onTap: (!isWholesale && canManage)
                      ? () => onSetPrice(InvPriceTier.retail)
                      : null,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: _PriceTile(
                  label: loc.translate('wholesale'),
                  // retail mode: wholesale is inactive — show dash
                  price: !isWholesale ? null : (unit.priceFor(InvPriceTier.wholesale) ?? productSellingPrice),
                  inactive: !isWholesale,
                  onTap: (isWholesale && canManage)
                      ? () => onSetPrice(InvPriceTier.wholesale)
                      : null,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: _PriceTile(
                  label: loc.translate('special'),
                  price: null,
                  hint: '${unit.prices.where(
                        (InvProductPrice p) => p.tier == InvPriceTier.special,
                      ).length}',
                  onTap:
                      canManage ? () => onSetPrice(InvPriceTier.special) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceTile extends StatelessWidget {
  const _PriceTile({
    required this.label,
    required this.price,
    this.hint,
    this.onTap,
    this.inactive = false,
  });

  final String label;
  final double? price;
  final String? hint;
  final VoidCallback? onTap;
  final bool inactive;

  @override
  Widget build(BuildContext context) {
    final String value = inactive
        ? '—'
        : price != null
            ? 'TSH ${price!.toStringAsFixed(0)}'
            : (hint != null
                ? '$hint ${LocalizationService.instance.translate('set')}'
                : '—');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Opacity(
        opacity: inactive ? 0.4 : 1.0,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AutoSizeText(
                label,
                maxLines: 1,
                minFontSize: 9,
                overflow: TextOverflow.ellipsis,
                style: ThemeConstants.captionStyle,
              ),
              SizedBox(height: 2.h),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: ThemeConstants.bodyStyle
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
        decoration: BoxDecoration(
          color: color.withOpacity(0.25),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Text(
          label,
          style: TextStyle(color: Colors.white, fontSize: 10.sp),
        ),
      );
}

/// Bottom sheet shell shared by the forms below: keyboard-aware, scrollable,
/// height-capped, so no sheet can overflow on a short screen.
class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: ThemeConstants.primaryBlue,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
            border: Border.all(color: Colors.white24),
          ),
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                AutoSizeText(
                  title,
                  maxLines: 1,
                  minFontSize: 13,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.headingStyle,
                ),
                SizedBox(height: 12.h),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Create or edit a selling unit.
class _UnitFormSheet extends StatefulWidget {
  const _UnitFormSheet({required this.productId, this.unit});

  final int productId;
  final InvProductUnit? unit;

  @override
  State<_UnitFormSheet> createState() => _UnitFormSheetState();
}

class _UnitFormSheetState extends State<_UnitFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.unit?.name ?? '');
  late final TextEditingController _factor =
      TextEditingController(text: '${widget.unit?.factor ?? 1}');
  late final TextEditingController _barcode =
      TextEditingController(text: widget.unit?.barcode ?? '');
  final TextEditingController _retail = TextEditingController();
  final TextEditingController _wholesale = TextEditingController();
  bool _saving = false;

  bool get _isEdit => widget.unit != null;
  bool get _isBase => widget.unit?.isBase ?? false;

  @override
  void dispose() {
    _name.dispose();
    _factor.dispose();
    _barcode.dispose();
    _retail.dispose();
    _wholesale.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);

    final InventoryProvider inv = context.read<InventoryProvider>();
    final bool ok = _isEdit
        ? await inv.updateUnit(
            widget.productId,
            widget.unit!.id,
            name: _name.text.trim(),
            factor: _isBase ? null : int.tryParse(_factor.text.trim()),
            barcode: _barcode.text.trim(),
          )
        : await inv.createUnit(
            widget.productId,
            name: _name.text.trim(),
            factor: int.tryParse(_factor.text.trim()) ?? 1,
            barcode: _barcode.text.trim(),
            retailPrice: double.tryParse(_retail.text.trim()),
            wholesalePrice: double.tryParse(_wholesale.text.trim()),
          );

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      ThemeConstants.showErrorSnackBar(
        context,
        LocalizationService.instance.translate('operation_failed'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    return _SheetShell(
      title: loc.translate(_isEdit ? 'edit_unit' : 'add_unit'),
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Field(
                controller: _name,
                label: loc.translate('unit_name'),
                hint: 'bottle, pack, crate',
                validator: (String? v) => (v == null || v.trim().isEmpty)
                    ? loc.translate('field_required')
                    : null,
              ),
              if (!_isBase) ...<Widget>[
                SizedBox(height: 10.h),
                _Field(
                  controller: _factor,
                  label: loc.translate('units_per_base'),
                  hint: 'e.g. 24',
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (String? v) {
                    final int? n = int.tryParse((v ?? '').trim());
                    return (n == null || n < 1)
                        ? loc.translate('enter_valid_number')
                        : null;
                  },
                ),
              ],
              SizedBox(height: 10.h),
              _Field(
                controller: _barcode,
                label: loc.translate('barcode'),
                hint: 'e.g. 6001234567890',
                isOptional: true,
              ),
              if (!_isEdit) ...<Widget>[
                SizedBox(height: 10.h),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _Field(
                        controller: _retail,
                        label: loc.translate('retail'),
                        hint: 'e.g. 1500',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        isOptional: true,
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: _Field(
                        controller: _wholesale,
                        label: loc.translate('wholesale'),
                        hint: 'e.g. 1300',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        isOptional: true,
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: 16.h),
              _SaveButton(saving: _saving, onPressed: _save),
            ],
          ),
        ),
      ],
    );
  }
}

/// Set one tier's price, with an optional reason for the log.
class _PriceFormSheet extends StatefulWidget {
  const _PriceFormSheet({
    required this.productId,
    required this.unit,
    required this.tier,
  });

  final int productId;
  final InvProductUnit unit;
  final InvPriceTier tier;

  @override
  State<_PriceFormSheet> createState() => _PriceFormSheetState();
}

class _PriceFormSheetState extends State<_PriceFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _price = TextEditingController(
    text: widget.tier == InvPriceTier.special
        ? ''
        : (widget.unit.priceFor(widget.tier)?.toStringAsFixed(0) ?? ''),
  );
  final TextEditingController _reason = TextEditingController();
  int? _customerId;
  bool _saving = false;

  bool get _isSpecial => widget.tier == InvPriceTier.special;

  @override
  void dispose() {
    _price.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_isSpecial && _customerId == null) {
      ThemeConstants.showWarningSnackBar(
        context,
        LocalizationService.instance.translate('select_customer'),
      );
      return;
    }

    setState(() => _saving = true);
    final bool ok = await context.read<InventoryProvider>().setUnitPrice(
          widget.productId,
          widget.unit.id,
          tier: widget.tier,
          price: parseAmount(_price.text),
          customerId: _isSpecial ? _customerId : null,
          reason: _reason.text.trim(),
        );

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      ThemeConstants.showErrorSnackBar(
        context,
        LocalizationService.instance.translate('operation_failed'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InventoryProvider inv = context.watch<InventoryProvider>();

    return _SheetShell(
      title: '${loc.translate(widget.tier.name)} — ${widget.unit.name}',
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_isSpecial) ...<Widget>[
                DropdownButtonFormField<int>(
                  initialValue: _customerId,
                  isExpanded: true,
                  dropdownColor: ThemeConstants.primaryBlue,
                  style: ThemeConstants.bodyStyle,
                  decoration: ThemeConstants.invInputDecoration(
                    loc.translate('customer'),
                  ),
                  items: inv.customers
                      .map(
                        (c) => DropdownMenuItem<int>(
                          value: c.id,
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ThemeConstants.bodyStyle,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (int? v) => setState(() => _customerId = v),
                ),
                SizedBox(height: 10.h),
              ],
              _Field(
                controller: _price,
                label: '${loc.translate('price')} (TSH)',
                hint: 'e.g. 1,500',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [ThousandsFormatter()],
                validator: (String? v) {
                  final double n = parseAmount(v);
                  return n <= 0 ? loc.translate('field_required') : null;
                },
              ),
              SizedBox(height: 10.h),
              _Field(
                controller: _reason,
                label: loc.translate('reason'),
                hint: 'e.g. Supplier increased their price',
                isOptional: true,
              ),
              SizedBox(height: 8.h),
              Text(
                loc.translate('price_change_logged_note'),
                style: ThemeConstants.captionStyle,
              ),
              SizedBox(height: 16.h),
              _SaveButton(saving: _saving, onPressed: _save),
            ],
          ),
        ),
      ],
    );
  }
}

/// Read-only price change log for one unit.
class _PriceHistorySheet extends StatefulWidget {
  const _PriceHistorySheet({required this.productId, required this.unit});

  final int productId;
  final InvProductUnit unit;

  @override
  State<_PriceHistorySheet> createState() => _PriceHistorySheetState();
}

class _PriceHistorySheetState extends State<_PriceHistorySheet> {
  late Future<List<InvPriceChange>> _future;

  @override
  void initState() {
    super.initState();
    _future = context
        .read<InventoryProvider>()
        .fetchPriceHistory(widget.productId, widget.unit.id);
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    return _SheetShell(
      title: '${loc.translate('price_history')} — ${widget.unit.name}',
      children: <Widget>[
        FutureBuilder<List<InvPriceChange>>(
          future: _future,
          builder: (
            BuildContext context,
            AsyncSnapshot<List<InvPriceChange>> snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 24.h),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white70),
                ),
              );
            }
            final List<InvPriceChange> rows =
                snapshot.data ?? const <InvPriceChange>[];
            if (rows.isEmpty) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 24.h),
                child: Text(
                  loc.translate('no_data'),
                  style: ThemeConstants.captionStyle,
                ),
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (_, __) => SizedBox(height: 8.h),
              itemBuilder: (_, int i) => _HistoryRow(change: rows[i]),
            );
          },
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.change});

  final InvPriceChange change;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final double? percent = change.changePercent;
    final bool up = (percent ?? 0) >= 0;
    final DateTime at = change.createdAt;
    final String stamp = '${at.day}/${at.month}/${at.year}';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AutoSizeText(
                  change.oldPrice == null
                      ? 'TSH ${change.newPrice.toStringAsFixed(0)}'
                      : 'TSH ${change.oldPrice!.toStringAsFixed(0)}  →  '
                          'TSH ${change.newPrice.toStringAsFixed(0)}',
                  maxLines: 1,
                  minFontSize: 10,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.bodyStyle
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 2.h),
                AutoSizeText(
                  <String>[
                    loc.translate(change.tier.name),
                    stamp,
                    if (change.changedByName.isNotEmpty) change.changedByName,
                    if (change.reason.isNotEmpty) change.reason,
                  ].join('  •  '),
                  maxLines: 2,
                  minFontSize: 9,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.captionStyle,
                ),
              ],
            ),
          ),
          if (percent != null) ...<Widget>[
            SizedBox(width: 8.w),
            Text(
              '${up ? '+' : ''}${percent.toStringAsFixed(1)}%',
              style: TextStyle(
                color:
                    up ? ThemeConstants.successGreen : ThemeConstants.errorText,
                fontWeight: FontWeight.w700,
                fontSize: 12.sp,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.isOptional = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final bool isOptional;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        style: ThemeConstants.bodyStyle,
        decoration: ThemeConstants.invInputDecoration(
          isOptional
              ? '$label (${LocalizationService.instance.translate('optional')})'
              : label,
        ).copyWith(hintText: hint),
      );
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saving, required this.onPressed});

  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 46.h,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: ThemeConstants.primaryOrange,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14.r),
            ),
          ),
          onPressed: saving ? null : onPressed,
          child: saving
              ? SizedBox(
                  width: 20.w,
                  height: 20.w,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  LocalizationService.instance.translate('save'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      );
}
