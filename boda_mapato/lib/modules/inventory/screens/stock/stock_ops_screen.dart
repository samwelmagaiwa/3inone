import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_batch.dart';
import '../../models/inv_product.dart';
import '../../models/inv_product_unit.dart';
import '../../providers/inventory_provider.dart';
import '../widgets/inv_units_ui.dart';
import '../widgets/inventory_widgets.dart';

/// "Stock In / Out / Transfer" — quick, everyday stock adjustments.
///
/// This is the fast path for small corrections. Receiving a real delivery
/// from a supplier belongs on the Purchasing screen instead, since that one
/// also keeps the supplier invoice and batch cost together.
class StockOpsScreen extends StatefulWidget {
  const StockOpsScreen({super.key});

  @override
  State<StockOpsScreen> createState() => _StockOpsScreenState();
}

class _StockOpsScreenState extends State<StockOpsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inv = context.read<InventoryProvider>();
      inv.fetchBatches();
      inv.fetchStockMovements();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    return Column(
      children: <Widget>[
        SizedBox(height: 8.h),
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: ThemeConstants.primaryOrange,
          tabs: <Widget>[
            Tab(text: loc.translate('stock_in')),
            Tab(text: loc.translate('stock_out')),
            Tab(text: loc.translate('stock_transfer')),
            Tab(text: LocalizationService.instance.translate('stock_history_audit_log')),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const <Widget>[
              _StockInForm(),
              _StockOutForm(),
              _StockTransferForm(),
              _StockHistoryTab(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shared bits: product picker and the note explaining what happens.
class _FormShell extends StatelessWidget {
  const _FormShell({required this.noteKey, required this.children});

  final String noteKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.all(12.w),
      child: Container(
        decoration: ThemeConstants.glassCardDecoration,
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: ThemeConstants.primaryCyan.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.info_outline,
                      color: ThemeConstants.primaryCyan, size: 16),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      loc.translate(noteKey),
                      style: ThemeConstants.captionStyle,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14.h),
            ...children,
          ],
        ),
      ),
    );
  }
}

Widget _productPicker({
  required BuildContext context,
  required List<InvProduct> products,
  required int? value,
  required ValueChanged<int?> onChanged,
}) {
  final LocalizationService loc = LocalizationService.instance;

  return DropdownButtonFormField<int>(
    initialValue: value,
    isExpanded: true,
    dropdownColor: ThemeConstants.primaryBlue,
    style: ThemeConstants.bodyStyle,
    decoration: ThemeConstants.invInputDecoration(loc.translate('product')),
    items: products
        .map(
          (InvProduct p) => DropdownMenuItem<int>(
            value: p.id,
            child: Text(
              '${p.name}  ·  ${p.quantity} ${p.unit}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ThemeConstants.bodyStyle,
            ),
          ),
        )
        .toList(),
    onChanged: onChanged,
  );
}

/// Add stock. A batch number and expiry are optional but recommended — they
/// are what lets the app warn about expiring stock and issue the oldest
/// batch first when a sale is made.
class _StockInForm extends StatefulWidget {
  const _StockInForm();

  @override
  State<_StockInForm> createState() => _StockInFormState();
}

class _StockInFormState extends State<_StockInForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _qty = TextEditingController();
  final TextEditingController _ref = TextEditingController();
  final TextEditingController _batchNumber = TextEditingController();
  int? _productId;
  // What the quantity is counted in when it is not the product's smallest unit (kg for a product kept in grams,
  // a carton for one kept in pieces). null = the smallest unit itself.
  int? _unitId;
  DateTime? _expiry;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _qty.addListener(_onQtyChanged);
  }

  /// How many of the smallest unit the chosen way of counting holds (1 for the smallest unit itself).
  int _factorOf(List<InvProductUnit> units) {
    if (_unitId == null) return 1;
    for (final InvProductUnit u in units) {
      if (u.id == _unitId && !u.isBase && u.factor > 1) return u.factor;
    }
    return 1;
  }

  void _onQtyChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _qty.removeListener(_onQtyChanged);
    _qty.dispose();
    _ref.dispose();
    _batchNumber.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final LocalizationService loc = LocalizationService.instance;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_productId == null) {
      ThemeConstants.showWarningSnackBar(
          context, loc.translate('select_product'));
      return;
    }

    setState(() => _saving = true);
    final InventoryProvider inv = context.read<InventoryProvider>();
    // Stock is always a whole number of the smallest unit: 5 kg of a product kept in grams is 5,000.
    final int received = int.parse(_qty.text.trim()) * _factorOf(inv.unitsOf(_productId!));
    final bool ok = await inv.stockIn(
          _productId!,
          received,
          reference: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
          batchNumber: _batchNumber.text.trim().isEmpty
              ? null
              : _batchNumber.text.trim(),
          expiryDate: _expiry,
        );

    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _qty.clear();
      _ref.clear();
      _batchNumber.clear();
      setState(() {
        _expiry = null;
        _productId = null;
        _unitId = null;
      });
      ThemeConstants.showSuccessSnackBar(
          context, loc.translate('stock_updated'));
    } else {
      ThemeConstants.showErrorSnackBar(
          context, loc.translate('operation_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InventoryProvider inv = context.watch<InventoryProvider>();
    final List<InvProduct> products = inv.products;

    InvProduct? selectedProduct;
    if (_productId != null) {
      final matches = products.where((p) => p.id == _productId);
      if (matches.isNotEmpty) selectedProduct = matches.first;
    }

    // Goods by weight or volume, and every business that is not a depot, can receive stock in a bigger unit
    // (kg, carton). A depot keeps counting in the one unit it always did.
    final List<InvProductUnit> units = selectedProduct == null ? const <InvProductUnit>[] : inv.unitsOf(selectedProduct.id);
    final bool canPickUnit = selectedProduct != null &&
        (selectedProduct.isWeighed || !inv.capabilities.isDepot) &&
        units.any((InvProductUnit u) => u.isActive && !u.isBase && u.factor > 1);
    final int factor = canPickUnit ? _factorOf(units) : 1;

    final int currentStock = selectedProduct?.quantity ?? 0;
    final int addedQty = (int.tryParse(_qty.text.trim()) ?? 0) * factor;
    final int newTotalStock = currentStock + addedQty;
    String show(int n) {
      final InvProduct? sp = selectedProduct;
      if (sp == null) return '$n';
      if (!(sp.isWeighed || !inv.capabilities.isDepot)) return '$n ${sp.unit}';
      return stockLabelOf(n, baseUnit: sp.unit, weighed: sp.isWeighed, units: units, caps: inv.capabilities);
    }

    return _FormShell(
      noteKey: 'stock_in_note',
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _productPicker(
                context: context,
                products: products,
                value: _productId,
                onChanged: (int? v) => setState(() {
                  _productId = v;
                  _unitId = null;
                }),
              ),
              if (selectedProduct != null) ...<Widget>[
                SizedBox(height: 10.h),
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: ThemeConstants.primaryCyan.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: ThemeConstants.primaryCyan.withOpacity(0.4),
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            LocalizationService.instance.translate('current_stock'),
                            style: ThemeConstants.captionStyle,
                          ),
                          Flexible(
                            child: Text(
                              show(currentStock),
                              textAlign: TextAlign.end,
                              style: ThemeConstants.bodyStyle
                                  .copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      if (addedQty > 0) ...<Widget>[
                        SizedBox(height: 4.h),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              LocalizationService.instance.translate('stock_being_added'),
                              style: ThemeConstants.captionStyle.copyWith(
                                color: ThemeConstants.successGreen,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                '+${show(addedQty)}',
                                textAlign: TextAlign.end,
                                style: ThemeConstants.bodyStyle.copyWith(
                                  color: ThemeConstants.successGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Divider(
                          color: Colors.white24,
                          height: 12.h,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                LocalizationService.instance.translate('new_total_after_this'),
                                style: ThemeConstants.bodyStyle.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Flexible(
                              child: Text(
                                show(newTotalStock),
                                textAlign: TextAlign.end,
                                style: ThemeConstants.bodyStyle.copyWith(
                                  color: ThemeConstants.primaryOrange,
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (canPickUnit) ...<Widget>[
                SizedBox(height: 10.h),
                Align(
                  alignment: Alignment.centerLeft,
                  child: UnitChips(
                    units: units.where((InvProductUnit u) => u.isActive).toList(),
                    selectedUnitId: _unitId,
                    baseLabel: selectedProduct?.unit ?? '',
                    onSelected: (InvProductUnit u) => setState(() => _unitId = u.isBase ? null : u.id),
                  ),
                ),
              ],
              SizedBox(height: 10.h),
              InvTextField(
                controller: _qty,
                label: loc.translate('quantity_received'),
                hint: 'e.g. 100',
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
              SizedBox(height: 10.h),
              InvTextField(
                controller: _batchNumber,
                label: loc.translate('batch_number'),
                hint: loc.translate('batch_number_auto_hint'),
                isOptional: true,
              ),
              SizedBox(height: 10.h),
              InvDateField(
                label: loc.translate('expiry_date'),
                value: _expiry,
                onChanged: (DateTime? d) => setState(() => _expiry = d),
              ),
              SizedBox(height: 10.h),
              InvTextField(
                controller: _ref,
                label: loc.translate('reference'),
                hint: LocalizationService.instance.translate('e_g_delivery_note_number'),
                isOptional: true,
              ),
              SizedBox(height: 16.h),
              InvPrimaryButton(
                busy: _saving,
                label: loc.translate('add_stock'),
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Remove stock without a sale — for example a sample given away or a count
/// correction. Damaged or expired goods belong on the Write-offs screen
/// instead, since those need a manager's approval.
class _StockOutForm extends StatefulWidget {
  const _StockOutForm();

  @override
  State<_StockOutForm> createState() => _StockOutFormState();
}

class _StockOutFormState extends State<_StockOutForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _qty = TextEditingController();
  final TextEditingController _ref = TextEditingController();
  int? _productId;
  int? _batchId;
  String? _reason;
  bool _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    _ref.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final LocalizationService loc = LocalizationService.instance;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_productId == null) {
      ThemeConstants.showWarningSnackBar(
          context, loc.translate('select_product'));
      return;
    }
    if (_reason == null) {
      ThemeConstants.showWarningSnackBar(
          context, loc.translate('select_reason'));
      return;
    }

    setState(() => _saving = true);
    final bool ok = await context.read<InventoryProvider>().stockOut(
          _productId!,
          int.parse(_qty.text.trim()),
          reason: _reason,
          reference: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
          batchId: _batchId,
        );

    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _qty.clear();
      _ref.clear();
      setState(() {
        _batchId = null;
        _productId = null;
        _reason = null;
      });
      ThemeConstants.showSuccessSnackBar(
          context, loc.translate('stock_updated'));
    } else {
      ThemeConstants.showErrorSnackBar(
          context, loc.translate('cannot_negative_stock'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InventoryProvider inv = context.watch<InventoryProvider>();
    final List<InvBatch> batches =
        _productId == null ? const <InvBatch>[] : inv.batchesOf(_productId!);

    return _FormShell(
      noteKey: 'stock_out_note',
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _productPicker(
                context: context,
                products: inv.products,
                value: _productId,
                onChanged: (int? v) => setState(() {
                  _productId = v;
                  _batchId = null;
                }),
              ),
              if (batches.isNotEmpty) ...<Widget>[
                SizedBox(height: 10.h),
                DropdownButtonFormField<int>(
                  initialValue: _batchId,
                  isExpanded: true,
                  dropdownColor: ThemeConstants.primaryBlue,
                  style: ThemeConstants.bodyStyle,
                  decoration: ThemeConstants.invInputDecoration(
                    '${loc.translate('batch')} '
                    '(${loc.translate('optional')} — ${loc.translate('oldest_first_note')})',
                  ),
                  items: batches
                      .map(
                        (InvBatch b) => DropdownMenuItem<int>(
                          value: b.id,
                          child: Text(
                            '${b.batchNumber} — ${b.quantity} ${loc.translate('left')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ThemeConstants.bodyStyle,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (int? v) => setState(() => _batchId = v),
                ),
              ],
              SizedBox(height: 10.h),
              InvTextField(
                controller: _qty,
                label: loc.translate('quantity'),
                hint: 'e.g. 5',
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
              SizedBox(height: 10.h),
              DropdownButtonFormField<String>(
                initialValue: _reason,
                isExpanded: true,
                dropdownColor: ThemeConstants.primaryBlue,
                style: ThemeConstants.bodyStyle,
                decoration:
                    ThemeConstants.invInputDecoration(loc.translate('reason')),
                items: <String, String>{
                  'sample': loc.translate('reason_sample'),
                  'gift': loc.translate('reason_gift'),
                  'correction': loc.translate('reason_correction'),
                }
                    .entries
                    .map((MapEntry<String, String> e) => DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(e.value, style: ThemeConstants.bodyStyle),
                        ))
                    .toList(),
                onChanged: (String? v) => setState(() => _reason = v),
                validator: (String? v) =>
                    v == null ? loc.translate('select_reason') : null,
              ),
              SizedBox(height: 10.h),
              InvTextField(
                controller: _ref,
                label: loc.translate('note_optional'),
                hint: LocalizationService.instance.translate('e_g_given_to_which_customer'),
                isOptional: true,
              ),
              SizedBox(height: 16.h),
              InvPrimaryButton(
                busy: _saving,
                label: loc.translate('remove_stock'),
                color: ThemeConstants.errorRed,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Move stock from one batch into a new or existing one for the same
/// product — for example after repacking, relabelling, or splitting a
/// delivery. The total quantity of the product does not change.
class _StockTransferForm extends StatefulWidget {
  const _StockTransferForm();

  @override
  State<_StockTransferForm> createState() => _StockTransferFormState();
}

/// Sentinel for "create a new batch (auto-numbered)" in the destination
/// dropdown — an actual batch number is never blank, so this can't collide.
const String _kNewBatchOption = '__new__';

class _StockTransferFormState extends State<_StockTransferForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _qty = TextEditingController();
  int? _productId;
  int? _sourceBatchId;
  String _destBatchChoice = _kNewBatchOption;
  DateTime? _destExpiry;
  bool _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final LocalizationService loc = LocalizationService.instance;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_productId == null || _sourceBatchId == null) {
      ThemeConstants.showWarningSnackBar(
          context, loc.translate('select_product_and_batch'));
      return;
    }

    setState(() => _saving = true);
    final InventoryProvider inv = context.read<InventoryProvider>();
    final int qty = int.parse(_qty.text.trim());
    final bool toNewBatch = _destBatchChoice == _kNewBatchOption;
    final List<InvBatch> sourceBatches = inv.batchesOf(_productId!);
    final String sourceBatchNumber = sourceBatches
        .firstWhere((InvBatch b) => b.id == _sourceBatchId,
            orElse: () => sourceBatches.first)
        .batchNumber;

    final bool outOk = await inv.stockOut(
      _productId!,
      qty,
      batchId: _sourceBatchId,
      reference: toNewBatch
          ? 'Transfer to a new batch'
          : 'Transfer to $_destBatchChoice',
    );
    final bool inOk = outOk
        ? await inv.stockIn(
            _productId!,
            qty,
            batchNumber: toNewBatch ? null : _destBatchChoice,
            expiryDate: toNewBatch ? _destExpiry : null,
            reference: 'Transfer from $sourceBatchNumber',
          )
        : false;

    if (!mounted) return;
    setState(() => _saving = false);
    if (inOk) {
      _qty.clear();
      setState(() {
        _sourceBatchId = null;
        _productId = null;
        _destBatchChoice = _kNewBatchOption;
        _destExpiry = null;
      });
      ThemeConstants.showSuccessSnackBar(
          context, loc.translate('stock_updated'));
    } else {
      ThemeConstants.showErrorSnackBar(
          context, loc.translate('operation_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InventoryProvider inv = context.watch<InventoryProvider>();
    final List<InvBatch> batches =
        _productId == null ? const <InvBatch>[] : inv.batchesOf(_productId!);

    return _FormShell(
      noteKey: 'stock_transfer_note',
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _productPicker(
                context: context,
                products: inv.products,
                value: _productId,
                onChanged: (int? v) => setState(() {
                  _productId = v;
                  _sourceBatchId = null;
                }),
              ),
              SizedBox(height: 10.h),
              DropdownButtonFormField<int>(
                initialValue: _sourceBatchId,
                isExpanded: true,
                dropdownColor: ThemeConstants.primaryBlue,
                style: ThemeConstants.bodyStyle,
                decoration: ThemeConstants.invInputDecoration(
                    loc.translate('from_batch')),
                items: batches
                    .map(
                      (InvBatch b) => DropdownMenuItem<int>(
                        value: b.id,
                        child: Text(
                          '${b.batchNumber} — ${b.quantity} ${loc.translate('left')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ThemeConstants.bodyStyle,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: batches.isEmpty
                    ? null
                    : (int? v) => setState(() => _sourceBatchId = v),
              ),
              SizedBox(height: 10.h),
              InvTextField(
                controller: _qty,
                label: loc.translate('quantity'),
                hint: 'e.g. 20',
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
              SizedBox(height: 10.h),
              DropdownButtonFormField<String>(
                initialValue: _destBatchChoice,
                isExpanded: true,
                dropdownColor: ThemeConstants.primaryBlue,
                style: ThemeConstants.bodyStyle,
                decoration:
                    ThemeConstants.invInputDecoration(loc.translate('to_batch')),
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                    value: _kNewBatchOption,
                    child: Text(
                      loc.translate('new_batch_auto'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ThemeConstants.bodyStyle,
                    ),
                  ),
                  ...batches
                      .where((InvBatch b) => b.id != _sourceBatchId)
                      .map(
                        (InvBatch b) => DropdownMenuItem<String>(
                          value: b.batchNumber,
                          child: Text(
                            '${b.batchNumber} — ${b.quantity} ${loc.translate('left')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ThemeConstants.bodyStyle,
                          ),
                        ),
                      ),
                ],
                onChanged: (String? v) =>
                    setState(() => _destBatchChoice = v ?? _kNewBatchOption),
              ),
              if (_destBatchChoice == _kNewBatchOption) ...<Widget>[
                SizedBox(height: 10.h),
                InvDateField(
                  label: loc.translate('expiry_date'),
                  value: _destExpiry,
                  onChanged: (DateTime? d) => setState(() => _destExpiry = d),
                ),
              ],
              SizedBox(height: 16.h),
              InvPrimaryButton(
                busy: _saving,
                label: loc.translate('move_stock'),
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StockHistoryTab extends StatefulWidget {
  const _StockHistoryTab();

  @override
  State<_StockHistoryTab> createState() => _StockHistoryTabState();
}

class _StockHistoryTabState extends State<_StockHistoryTab> {
  int? _selectedProductId;

  Future<void> _refresh() async {
    await context
        .read<InventoryProvider>()
        .fetchStockMovements(productId: _selectedProductId);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final inv = context.watch<InventoryProvider>();
    final products = inv.products;
    final movements = inv.stockMovements;

    return Padding(
      padding: EdgeInsets.all(12.w),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _selectedProductId,
                  isExpanded: true,
                  dropdownColor: ThemeConstants.primaryBlue,
                  style: ThemeConstants.bodyStyle,
                  decoration: ThemeConstants.invInputDecoration(loc.translate('filter_by_product')),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text(loc.translate('all_products'), style: ThemeConstants.bodyStyle),
                    ),
                    ...products.map(
                      (p) => DropdownMenuItem<int?>(
                        value: p.id,
                        child: Text('${p.name} (${p.sku})', style: ThemeConstants.bodyStyle),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _selectedProductId = v);
                    inv.fetchStockMovements(productId: v);
                  },
                ),
              ),
              SizedBox(width: 8.w),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                onPressed: _refresh,
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              backgroundColor: Colors.white,
              color: ThemeConstants.primaryBlue,
              child: movements.isEmpty
                  ? InvEmptyState(
                      icon: Icons.history,
                      message: LocalizationService.instance.translate('no_stock_in_or_out_records'),
                    )
                  : ListView.separated(
                      itemCount: movements.length,
                      separatorBuilder: (_, __) => SizedBox(height: 8.h),
                      itemBuilder: (context, index) {
                        final m = movements[index];
                        final isStockIn = m.isStockIn;
                        final dateStr =
                            '${m.createdAt.year}-${m.createdAt.month.toString().padLeft(2, '0')}-${m.createdAt.day.toString().padLeft(2, '0')} ${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}';

                        return Container(
                          decoration: ThemeConstants.glassCardDecoration,
                          padding: EdgeInsets.all(12.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isStockIn
                                        ? Icons.add_circle_outline
                                        : Icons.remove_circle_outline,
                                    color: isStockIn
                                        ? ThemeConstants.successGreen
                                        : ThemeConstants.errorRed,
                                    size: 20.sp,
                                  ),
                                  SizedBox(width: 8.w),
                                  Expanded(
                                    child: Text(
                                      m.productName.isNotEmpty
                                          ? m.productName
                                          : LocalizationService.instance.translateWith('product_2', <Object?>[m.productId]),
                                      style: ThemeConstants.bodyStyle
                                          .copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  InvBadge(
                                    label: isStockIn ? LocalizationService.instance.translate('stock_in_2') : LocalizationService.instance.translate('stock_out_2'),
                                    color: isStockIn
                                        ? ThemeConstants.successGreen
                                        : ThemeConstants.errorRed,
                                  ),
                                ],
                              ),
                              SizedBox(height: 6.h),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    LocalizationService.instance.translateWith('was', <Object?>[m.previousQuantity]),
                                    style: ThemeConstants.captionStyle,
                                  ),
                                  Text(
                                    isStockIn
                                        ? LocalizationService.instance.translateWith('added', <Object?>[m.quantity])
                                        : LocalizationService.instance.translateWith('removed', <Object?>[m.quantity]),
                                    style: ThemeConstants.captionStyle.copyWith(
                                      color: isStockIn
                                          ? ThemeConstants.successGreen
                                          : ThemeConstants.errorText,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    LocalizationService.instance.translateWith('now_2', <Object?>[m.newQuantity]),
                                    style: ThemeConstants.captionStyle.copyWith(
                                      color: ThemeConstants.primaryOrange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              if (m.reference.isNotEmpty) ...[
                                SizedBox(height: 4.h),
                                Text(
                                  '📝 ${m.reference}',
                                  style: ThemeConstants.captionStyle.copyWith(
                                    color: Colors.white70,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                              SizedBox(height: 4.h),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '📅 $dateStr',
                                    style: ThemeConstants.captionStyle
                                        .copyWith(fontSize: 10.sp),
                                  ),
                                  if (m.userName.isNotEmpty)
                                    Text(
                                      '👤 ${m.userName}',
                                      style: ThemeConstants.captionStyle
                                          .copyWith(fontSize: 10.sp),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

