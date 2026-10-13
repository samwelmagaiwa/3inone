import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_depot_models.dart';
import '../../models/inv_product.dart';
import '../../providers/depot_provider.dart';
import '../../providers/inventory_provider.dart';
import '../scanning/barcode_scanner_screen.dart';
import '../widgets/inventory_widgets.dart';

/// Area 4 — suppliers, purchase orders, goods receiving and supplier balances.
class PurchasingScreen extends StatefulWidget {
  const PurchasingScreen({super.key});

  @override
  State<PurchasingScreen> createState() => _PurchasingScreenState();
}

class _PurchasingScreenState extends State<PurchasingScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Draw whatever is already cached; only show a spinner on a cold start.
    _loading = context.read<DepotProvider>().suppliers.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final DepotProvider depot = context.read<DepotProvider>();
    await Future.wait<void>(<Future<void>>[
      depot.fetchSuppliers(),
      depot.fetchPurchaseOrders(),
      depot.fetchSupplierInvoices(),
    ]);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    if (_loading) {
      return const Scaffold(
        backgroundColor: ThemeConstants.primaryBlue,
        body: Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }

    return InvTabScaffold(
      title: '',
      tabs: <String>[
        loc.translate('suppliers'),
        loc.translate('purchase_orders'),
        loc.translate('supplier_invoices'),
      ],
      views: <Widget>[
        _SuppliersTab(onRefresh: _load),
        _PurchaseOrdersTab(onRefresh: _load),
        _SupplierInvoicesTab(onRefresh: _load),
      ],
    );
  }
}

// ------------------------------------------------------------------ suppliers

class _SuppliersTab extends StatelessWidget {
  const _SuppliersTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final List<InvSupplier> rows = context.watch<DepotProvider>().suppliers;

    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: onRefresh,
          backgroundColor: Colors.white,
          color: ThemeConstants.primaryBlue,
          child: rows.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: <Widget>[
                    SizedBox(height: 60.h),
                    InvEmptyState(
                      icon: Icons.local_shipping_outlined,
                      message: loc.translate('no_suppliers'),
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 88.h),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => SizedBox(height: 8.h),
                  itemBuilder: (_, int i) => _SupplierCard(supplier: rows[i]),
                ),
        ),
        Positioned(
          right: 12.w,
          bottom: 12.h,
          child: FloatingActionButton.extended(
            heroTag: 'supplier_fab',
            backgroundColor: ThemeConstants.primaryOrange,
            onPressed: () => showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const _SupplierFormSheet(),
            ),
            icon: const Icon(Icons.add, color: Colors.white),
            label: Text(
              loc.translate('add_supplier'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.supplier});

  final InvSupplier supplier;

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
                child: AutoSizeText(
                  supplier.name,
                  maxLines: 1,
                  minFontSize: 11,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.bodyStyle
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(width: 8.w),
              if (supplier.owesMoney)
                InvBadge(
                  label: 'TSH ${supplier.balance.toStringAsFixed(0)}',
                  color: ThemeConstants.warningAmber,
                )
              else
                InvBadge(
                  label: loc.translate('settled'),
                  color: ThemeConstants.successGreen,
                ),
            ],
          ),
          SizedBox(height: 4.h),
          InvKeyValueWrap(entries: <String, String>{
            if (supplier.phone.isNotEmpty)
              loc.translate('phone'): supplier.phone,
            if (supplier.contactPerson.isNotEmpty)
              loc.translate('contact'): supplier.contactPerson,
            loc.translate('payment_terms'): '${supplier.paymentTermsDays}d',
          }),
          SizedBox(height: 8.h),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  onPressed: () => showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _SupplierFormSheet(supplier: supplier),
                  ),
                  icon: Icon(Icons.edit_outlined,
                      size: 16.sp, color: Colors.white70),
                  label: AutoSizeText(
                    loc.translate('edit'),
                    maxLines: 1,
                    minFontSize: 9,
                    style: ThemeConstants.captionStyle,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeConstants.primaryOrange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  onPressed: () => showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _PaySupplierSheet(supplier: supplier),
                  ),
                  icon: Icon(Icons.payments_outlined,
                      size: 16.sp, color: Colors.white),
                  label: AutoSizeText(
                    loc.translate('pay'),
                    maxLines: 1,
                    minFontSize: 9,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupplierFormSheet extends StatefulWidget {
  const _SupplierFormSheet({this.supplier});

  final InvSupplier? supplier;

  @override
  State<_SupplierFormSheet> createState() => _SupplierFormSheetState();
}

class _SupplierFormSheetState extends State<_SupplierFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.supplier?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.supplier?.phone ?? '');
  late final TextEditingController _contact =
      TextEditingController(text: widget.supplier?.contactPerson ?? '');
  late final TextEditingController _terms =
      TextEditingController(text: '${widget.supplier?.paymentTermsDays ?? 0}');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _contact.dispose();
    _terms.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);

    final bool ok = await context.read<DepotProvider>().saveSupplier(
          id: widget.supplier?.id,
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          contactPerson: _contact.text.trim(),
          paymentTermsDays: int.tryParse(_terms.text.trim()) ?? 0,
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

    return InvSheetShell(
      title: loc.translate(
        widget.supplier == null ? 'add_supplier' : 'edit_supplier',
      ),
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              InvTextField(
                controller: _name,
                label: loc.translate('name'),
                hint: LocalizationService.instance.translate('e_g_coca_cola_kwanza_ltd'),
                validator: (String? v) => (v == null || v.trim().isEmpty)
                    ? loc.translate('field_required')
                    : null,
              ),
              SizedBox(height: 10.h),
              InvTextField(
                controller: _phone,
                label: loc.translate('phone'),
                hint: 'e.g. 0700 000 000',
                keyboardType: TextInputType.phone,
                isOptional: true,
              ),
              SizedBox(height: 10.h),
              InvTextField(
                controller: _contact,
                label: loc.translate('contact_person'),
                hint: LocalizationService.instance.translate('e_g_juma_mwalimu'),
                isOptional: true,
              ),
              SizedBox(height: 10.h),
              InvTextField(
                controller: _terms,
                label: loc.translate('payment_terms_days'),
                hint: 'e.g. 30',
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
              SizedBox(height: 16.h),
              InvPrimaryButton(busy: _saving, onPressed: _save),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaySupplierSheet extends StatefulWidget {
  const _PaySupplierSheet({required this.supplier});

  final InvSupplier supplier;

  @override
  State<_PaySupplierSheet> createState() => _PaySupplierSheetState();
}

class _PaySupplierSheetState extends State<_PaySupplierSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  String _method = 'cash';
  int? _invoiceId;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _saving = true);

    final bool ok = await context.read<DepotProvider>().paySupplier(
          supplierId: widget.supplier.id,
          amount: double.parse(_amount.text.trim()),
          method: _method,
          invoiceId: _invoiceId,
          reference: _reference.text.trim(),
        );

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context, true);
      ThemeConstants.showSuccessSnackBar(
        context,
        LocalizationService.instance.translate('payment_recorded'),
      );
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
    final List<InvSupplierInvoice> invoices = context
        .watch<DepotProvider>()
        .supplierInvoices
        .where((InvSupplierInvoice i) =>
            i.supplierId == widget.supplier.id && i.balance > 0)
        .toList();

    return InvSheetShell(
      title: '${loc.translate('pay')} — ${widget.supplier.name}',
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              InvKeyValueWrap(entries: <String, String>{
                loc.translate('balance'):
                    'TSH ${widget.supplier.balance.toStringAsFixed(0)}',
              }),
              SizedBox(height: 10.h),
              if (invoices.isNotEmpty) ...<Widget>[
                DropdownButtonFormField<int>(
                  initialValue: _invoiceId,
                  isExpanded: true,
                  dropdownColor: ThemeConstants.primaryBlue,
                  style: ThemeConstants.bodyStyle,
                  decoration: ThemeConstants.invInputDecoration(
                    '${loc.translate('invoice')} (${loc.translate('optional')})',
                  ),
                  items: invoices
                      .map((InvSupplierInvoice i) => DropdownMenuItem<int>(
                            value: i.id,
                            child: Text(
                              '${i.number} — ${i.balance.toStringAsFixed(0)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ThemeConstants.bodyStyle,
                            ),
                          ))
                      .toList(),
                  onChanged: (int? v) => setState(() => _invoiceId = v),
                ),
                SizedBox(height: 10.h),
              ],
              InvTextField(
                controller: _amount,
                label: '${loc.translate('amount')} (TSH)',
                hint: 'e.g. 500,000',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (String? v) {
                  final double? n = double.tryParse((v ?? '').trim());
                  return (n == null || n <= 0)
                      ? loc.translate('enter_valid_number')
                      : null;
                },
              ),
              SizedBox(height: 10.h),
              _MethodDropdown(
                value: _method,
                onChanged: (String v) => setState(() => _method = v),
              ),
              SizedBox(height: 10.h),
              InvTextField(
                controller: _reference,
                label: loc.translate('reference'),
                hint: LocalizationService.instance.translate('e_g_bank_slip_or_m'),
                isOptional: true,
              ),
              SizedBox(height: 16.h),
              InvPrimaryButton(busy: _saving, onPressed: _save),
            ],
          ),
        ),
      ],
    );
  }
}

/// Cash / mobile money / bank / cheque — shared by every payment form.
class _MethodDropdown extends StatelessWidget {
  const _MethodDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: ThemeConstants.primaryBlue,
      style: ThemeConstants.bodyStyle,
      decoration: ThemeConstants.invInputDecoration(loc.translate('method')),
      items: const <String>['cash', 'mobile_money', 'bank_transfer', 'cheque']
          .map((String m) => DropdownMenuItem<String>(
                value: m,
                child: Text(
                  loc.translate(m),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.bodyStyle,
                ),
              ))
          .toList(),
      onChanged: (String? v) => onChanged(v ?? 'cash'),
    );
  }
}

// ------------------------------------------------------------ purchase orders

class _PurchaseOrdersTab extends StatelessWidget {
  const _PurchaseOrdersTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final List<InvPurchaseOrder> rows =
        context.watch<DepotProvider>().purchaseOrders;

    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: onRefresh,
          backgroundColor: Colors.white,
          color: ThemeConstants.primaryBlue,
          child: rows.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: <Widget>[
                    SizedBox(height: 60.h),
                    InvEmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: loc.translate('no_purchase_orders'),
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 88.h),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => SizedBox(height: 8.h),
                  itemBuilder: (_, int i) => _PurchaseOrderCard(order: rows[i]),
                ),
        ),
        Positioned(
          right: 12.w,
          bottom: 12.h,
          child: FloatingActionButton.extended(
            heroTag: 'grn_fab',
            backgroundColor: ThemeConstants.primaryOrange,
            onPressed: () => showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const ReceiveGoodsSheet(),
            ),
            icon: const Icon(Icons.inbox_outlined, color: Colors.white),
            label: Text(
              loc.translate('receive_goods'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _PurchaseOrderCard extends StatelessWidget {
  const _PurchaseOrderCard({required this.order});

  final InvPurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final (Color color, String label) = switch (order.status) {
      'received' => (ThemeConstants.successGreen, loc.translate('received')),
      'partial' => (ThemeConstants.warningAmber, loc.translate('partial')),
      'cancelled' => (ThemeConstants.errorRed, loc.translate('cancelled')),
      'sent' => (ThemeConstants.primaryCyan, loc.translate('sent')),
      _ => (Colors.white38, loc.translate('draft')),
    };

    return Container(
      decoration: ThemeConstants.glassCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: AutoSizeText(
                  order.number,
                  maxLines: 1,
                  minFontSize: 11,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.bodyStyle
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(width: 8.w),
              InvBadge(label: label, color: color),
            ],
          ),
          SizedBox(height: 4.h),
          InvKeyValueWrap(entries: <String, String>{
            loc.translate('supplier'): order.supplierName,
            loc.translate('total'): 'TSH ${order.total.toStringAsFixed(0)}',
          }),
        ],
      ),
    );
  }
}

/// Receive goods against a supplier, capturing batch, expiry and cost.
class ReceiveGoodsSheet extends StatefulWidget {
  const ReceiveGoodsSheet({super.key});

  @override
  State<ReceiveGoodsSheet> createState() => _ReceiveGoodsSheetState();
}

class _ReceiveGoodsSheetState extends State<ReceiveGoodsSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _batch = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _cost = TextEditingController();
  final TextEditingController _invoiceNumber = TextEditingController();
  int? _supplierId;
  int? _productId;
  DateTime? _expiry;
  bool _saving = false;

  @override
  void dispose() {
    _batch.dispose();
    _quantity.dispose();
    _cost.dispose();
    _invoiceNumber.dispose();
    super.dispose();
  }

  Future<void> _scanForProduct(List<InvProduct> products) async {
    final loc = LocalizationService.instance;
    final String? code =
        await scanBarcode(context, title: loc.translate('scan_barcode'));
    if (code == null || code.isEmpty || !mounted) return;

    final result = await context.read<DepotProvider>().resolveBarcode(code);
    if (result?.productId == null) {
      if (mounted) {
        ThemeConstants.showErrorSnackBar(
            context, loc.translate('barcode_not_found'));
      }
      return;
    }

    final matches = products.where((p) => p.id == result!.productId).toList();
    if (matches.isEmpty) {
      if (mounted) {
        ThemeConstants.showErrorSnackBar(
            context, loc.translate('barcode_not_found'));
      }
      return;
    }
    setState(() => _productId = matches.first.id);
  }

  Future<void> _save() async {
    final LocalizationService loc = LocalizationService.instance;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_supplierId == null || _productId == null) {
      ThemeConstants.showWarningSnackBar(
          context, loc.translate('select_supplier_and_product'));
      return;
    }

    setState(() => _saving = true);
    final bool ok = await context.read<DepotProvider>().receiveGoods(
      supplierId: _supplierId!,
      invoiceNumber: _invoiceNumber.text.trim(),
      lines: <Map<String, dynamic>>[
        <String, dynamic>{
          'product_id': _productId,
          'quantity': int.parse(_quantity.text.trim()),
          'unit_cost': double.tryParse(_cost.text.trim()) ?? 0,
          if (_batch.text.trim().isNotEmpty) 'batch_number': _batch.text.trim(),
          if (_expiry != null)
            'expiry_date': _expiry!.toIso8601String().split('T').first,
        },
      ],
    );

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (ok) {
      await context.read<InventoryProvider>().fetchProducts();
      if (mounted) {
        Navigator.pop(context, true);
        ThemeConstants.showSuccessSnackBar(
          context,
          LocalizationService.instance.translate('goods_received'),
        );
      }
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
    final DepotProvider depot = context.watch<DepotProvider>();
    final List<InvProduct> products =
        context.watch<InventoryProvider>().products;

    return InvSheetShell(
      title: loc.translate('receive_goods'),
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DropdownButtonFormField<int>(
                initialValue: _supplierId,
                isExpanded: true,
                dropdownColor: ThemeConstants.primaryBlue,
                style: ThemeConstants.bodyStyle,
                decoration: ThemeConstants.invInputDecoration(
                    loc.translate('supplier')),
                items: depot.suppliers
                    .map((InvSupplier s) => DropdownMenuItem<int>(
                          value: s.id,
                          child: Text(
                            s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ThemeConstants.bodyStyle,
                          ),
                        ))
                    .toList(),
                onChanged: (int? v) => setState(() => _supplierId = v),
              ),
              SizedBox(height: 10.h),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _productId,
                      isExpanded: true,
                      dropdownColor: ThemeConstants.primaryBlue,
                      style: ThemeConstants.bodyStyle,
                      decoration: ThemeConstants.invInputDecoration(
                          loc.translate('product')),
                      items: products
                          .map((InvProduct p) => DropdownMenuItem<int>(
                                value: p.id,
                                child: Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ThemeConstants.bodyStyle,
                                ),
                              ))
                          .toList(),
                      onChanged: (int? v) => setState(() => _productId = v),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  IconButton(
                    tooltip: loc.translate('scan_barcode'),
                    onPressed: () => _scanForProduct(products),
                    icon: const Icon(Icons.qr_code_scanner,
                        color: Colors.white70),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              InvTextField(
                controller: _batch,
                label: loc.translate('batch_number'),
                hint: loc.translate('batch_number_auto_hint'),
                isOptional: true,
              ),
              SizedBox(height: 10.h),
              Row(
                children: <Widget>[
                  Expanded(
                    child: InvTextField(
                      controller: _quantity,
                      label: loc.translate('quantity'),
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
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: InvTextField(
                      controller: _cost,
                      label: loc.translate('buying_cost'),
                      hint: 'e.g. 12,000',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      isOptional: true,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              InvDateField(
                label: loc.translate('expiry_date'),
                value: _expiry,
                onChanged: (DateTime? d) => setState(() => _expiry = d),
              ),
              SizedBox(height: 10.h),
              InvTextField(
                controller: _invoiceNumber,
                label: loc.translate('supplier_invoice_number'),
                hint: LocalizationService.instance.translate('e_g_inv_00123'),
                isOptional: true,
              ),
              SizedBox(height: 16.h),
              InvPrimaryButton(busy: _saving, onPressed: _save),
            ],
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------- supplier invoices

class _SupplierInvoicesTab extends StatelessWidget {
  const _SupplierInvoicesTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final List<InvSupplierInvoice> rows =
        context.watch<DepotProvider>().supplierInvoices;

    return RefreshIndicator(
      onRefresh: onRefresh,
      backgroundColor: Colors.white,
      color: ThemeConstants.primaryBlue,
      child: rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: <Widget>[
                SizedBox(height: 60.h),
                InvEmptyState(
                  icon: Icons.description_outlined,
                  message: loc.translate('no_supplier_invoices'),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
              itemCount: rows.length,
              separatorBuilder: (_, __) => SizedBox(height: 8.h),
              itemBuilder: (_, int i) {
                final InvSupplierInvoice inv = rows[i];
                final bool settled = inv.balance <= 0;

                return Container(
                  decoration: ThemeConstants.glassCardDecoration,
                  padding: EdgeInsets.all(12.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: AutoSizeText(
                              inv.number,
                              maxLines: 1,
                              minFontSize: 11,
                              overflow: TextOverflow.ellipsis,
                              style: ThemeConstants.bodyStyle
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          InvBadge(
                            label: settled
                                ? loc.translate('paid')
                                : 'TSH ${inv.balance.toStringAsFixed(0)}',
                            color: settled
                                ? ThemeConstants.successGreen
                                : ThemeConstants.warningAmber,
                          ),
                        ],
                      ),
                      SizedBox(height: 4.h),
                      InvKeyValueWrap(entries: <String, String>{
                        loc.translate('supplier'): inv.supplierName,
                        loc.translate('amount'):
                            'TSH ${inv.amount.toStringAsFixed(0)}',
                        loc.translate('paid'):
                            'TSH ${inv.paidAmount.toStringAsFixed(0)}',
                      }),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
