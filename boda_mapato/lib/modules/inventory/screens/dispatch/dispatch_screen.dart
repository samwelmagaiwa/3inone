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

/// Area 9 — loading a vehicle, the route, and reconciling on return.
class DispatchScreen extends StatefulWidget {
  const DispatchScreen({super.key});

  @override
  State<DispatchScreen> createState() => _DispatchScreenState();
}

class _DispatchScreenState extends State<DispatchScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Draw whatever is already cached; only show a spinner on a cold start.
    _loading = context.read<DepotProvider>().dispatches.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await context.read<DepotProvider>().fetchDispatches();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final List<InvDispatch> rows = context.watch<DepotProvider>().dispatches;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dispatch_fab',
        backgroundColor: ThemeConstants.primaryOrange,
        onPressed: () async {
          final bool? saved = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const _LoadVehicleSheet(),
          );
          if ((saved ?? false) && mounted) {
            await _load();
          }
        },
        icon: const Icon(Icons.local_shipping_outlined, color: Colors.white),
        label: Text(
          loc.translate('load_vehicle'),
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              )
            : RefreshIndicator(
                onRefresh: _load,
                backgroundColor: Colors.white,
                color: ThemeConstants.primaryBlue,
                child: rows.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: <Widget>[
                          SizedBox(height: 70.h),
                          InvEmptyState(
                            icon: Icons.local_shipping_outlined,
                            message: loc.translate('no_dispatches'),
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
                        itemBuilder: (_, int i) => _DispatchCard(
                          dispatch: rows[i],
                          onOpen: () => _openDetail(rows[i].id),
                        ),
                      ),
              ),
      ),
    );
  }

  Future<void> _openDetail(int id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DispatchDetailScreen(dispatchId: id),
      ),
    );
    await _load();
  }
}

class _DispatchCard extends StatelessWidget {
  const _DispatchCard({required this.dispatch, required this.onOpen});

  final InvDispatch dispatch;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final (Color color, String label) = switch (dispatch.status) {
      'reconciled' => (
          ThemeConstants.successGreen,
          loc.translate('reconciled')
        ),
      'cancelled' => (ThemeConstants.errorRed, loc.translate('cancelled')),
      'on_route' => (ThemeConstants.primaryCyan, loc.translate('on_route')),
      _ => (ThemeConstants.warningAmber, loc.translate('loading')),
    };

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(20.r),
      child: Container(
        decoration: ThemeConstants.glassCardDecoration,
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: AutoSizeText(
                    dispatch.reference,
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
            SizedBox(height: 6.h),
            InvKeyValueWrap(entries: <String, String>{
              if (dispatch.vehicle.isNotEmpty)
                loc.translate('vehicle'): dispatch.vehicle,
              if (dispatch.route.isNotEmpty)
                loc.translate('route'): dispatch.route,
              loc.translate('date'): dispatch.dispatchDate,
              loc.translate('loaded'): '${dispatch.totalLoaded}',
              if (dispatch.isReconciled)
                loc.translate('cash'):
                    'TSH ${dispatch.cashReturned.toStringAsFixed(0)}',
            }),
          ],
        ),
      ),
    );
  }
}

class _LoadVehicleSheet extends StatefulWidget {
  const _LoadVehicleSheet();

  @override
  State<_LoadVehicleSheet> createState() => _LoadVehicleSheetState();
}

class _LoadVehicleSheetState extends State<_LoadVehicleSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _vehicle = TextEditingController();
  final TextEditingController _route = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _price = TextEditingController();
  int? _productId;
  bool _saving = false;

  @override
  void dispose() {
    _vehicle.dispose();
    _route.dispose();
    _quantity.dispose();
    _price.dispose();
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
    if (_productId == null) {
      ThemeConstants.showWarningSnackBar(
          context, loc.translate('select_product'));
      return;
    }

    setState(() => _saving = true);
    final bool ok = await context.read<DepotProvider>().createDispatch(
      vehicle: _vehicle.text.trim(),
      route: _route.text.trim(),
      lines: <Map<String, dynamic>>[
        <String, dynamic>{
          'product_id': _productId,
          'quantity': int.parse(_quantity.text.trim()),
          'unit_price': double.tryParse(_price.text.replaceAll(',', '').trim()) ?? 0,
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
      }
    } else {
      ThemeConstants.showErrorSnackBar(
          context, loc.translate('insufficient_stock_or_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final List<InvProduct> products =
        context.watch<InventoryProvider>().products;

    return InvSheetShell(
      title: loc.translate('load_vehicle'),
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: InvTextField(
                      controller: _vehicle,
                      label: loc.translate('vehicle'),
                      hint: 'e.g. T 123 ABC',
                      isOptional: true,
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: InvTextField(
                      controller: _route,
                      label: loc.translate('route'),
                      hint: 'e.g. Kariakoo - Buguruni',
                      isOptional: true,
                    ),
                  ),
                ],
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
                                  '${p.name}  (${p.quantity})',
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
              Row(
                children: <Widget>[
                  Expanded(
                    child: InvTextField(
                      controller: _quantity,
                      label: loc.translate('quantity'),
                      hint: 'e.g. 50',
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
                      controller: _price,
                      label: loc.translate('unit_price'),
                      hint: 'e.g. 15,000',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[ThousandsFormatter()],
                      isOptional: true,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Text(
                loc.translateForKind('load_removes_stock_note', isDepot: context.watch<DepotProvider>().capabilities.isDepot),
                style: ThemeConstants.captionStyle,
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

/// One dispatch: what went out, what came back, and the cash.
class DispatchDetailScreen extends StatefulWidget {
  const DispatchDetailScreen({required this.dispatchId, super.key});

  final int dispatchId;

  @override
  State<DispatchDetailScreen> createState() => _DispatchDetailScreenState();
}

class _DispatchDetailScreenState extends State<DispatchDetailScreen> {
  InvDispatch? _dispatch;
  bool _loading = true;
  bool _busy = false;
  final Map<int, TextEditingController> _returned =
      <int, TextEditingController>{};
  final TextEditingController _cash = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final TextEditingController c in _returned.values) {
      c.dispose();
    }
    _cash.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final InvDispatch? d =
        await context.read<DepotProvider>().fetchDispatch(widget.dispatchId);
    if (!mounted) {
      return;
    }
    setState(() {
      _dispatch = d;
      _loading = false;
      for (final InvDispatchLine l in d?.lines ?? const <InvDispatchLine>[]) {
        _returned.putIfAbsent(
          l.id,
          () => TextEditingController(text: '${l.returnedQuantity}'),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InvDispatch? d = _dispatch;
    final bool canReconcile = d != null && !d.isReconciled;

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: ThemeConstants.textPrimary),
        title: AutoSizeText(
          d?.reference ?? loc.translate('dispatch'),
          maxLines: 1,
          minFontSize: 13,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ThemeConstants.textPrimary,
            fontSize: 19.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      bottomNavigationBar: canReconcile
          ? SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 8.h),
                child: InvPrimaryButton(
                  busy: _busy,
                  label: loc.translate('reconcile'),
                  color: ThemeConstants.successGreen,
                  onPressed: _reconcile,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              )
            : d == null
                ? InvEmptyState(
                    icon: Icons.local_shipping_outlined,
                    message: loc.translate('no_data'),
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
                    children: <Widget>[
                      Container(
                        decoration: ThemeConstants.glassCardDecoration,
                        padding: EdgeInsets.all(12.w),
                        child: InvKeyValueWrap(entries: <String, String>{
                          loc.translate('status'): loc.translate(d.status),
                          if (d.vehicle.isNotEmpty)
                            loc.translate('vehicle'): d.vehicle,
                          if (d.route.isNotEmpty)
                            loc.translate('route'): d.route,
                          loc.translate('date'): d.dispatchDate,
                          if (d.isReconciled)
                            loc.translate('cash_expected'):
                                'TSH ${d.cashExpected.toStringAsFixed(0)}',
                          if (d.isReconciled)
                            loc.translate('cash_returned'):
                                'TSH ${d.cashReturned.toStringAsFixed(0)}',
                        }),
                      ),
                      SizedBox(height: 12.h),
                      ...d.lines.map(
                        (InvDispatchLine l) => Padding(
                          padding: EdgeInsets.only(bottom: 8.h),
                          child: _LineCard(
                            line: l,
                            controller: _returned[l.id],
                            editable: canReconcile,
                          ),
                        ),
                      ),
                      if (canReconcile) ...<Widget>[
                        SizedBox(height: 4.h),
                        InvTextField(
                          controller: _cash,
                          label: loc.translate('cash_returned'),
                          hint: 'e.g. 480,000',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: <TextInputFormatter>[ThousandsFormatter()],
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          loc.translateForKind('reconcile_note', isDepot: context.watch<DepotProvider>().capabilities.isDepot),
                          style: ThemeConstants.captionStyle,
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }

  Future<void> _reconcile() async {
    final InvDispatch? d = _dispatch;
    if (d == null) {
      return;
    }

    setState(() => _busy = true);
    final Map<String, dynamic>? result = await context
        .read<DepotProvider>()
        .reconcileDispatch(
          widget.dispatchId,
          cashReturned: double.tryParse(_cash.text.replaceAll(',', '').trim()) ?? 0,
          lines: d.lines
              .map((InvDispatchLine l) => <String, dynamic>{
                    'line_id': l.id,
                    'returned_quantity':
                        int.tryParse(_returned[l.id]?.text.trim() ?? '0') ?? 0,
                  })
              .toList(),
        );

    if (!mounted) {
      return;
    }
    setState(() => _busy = false);

    if (result == null) {
      ThemeConstants.showErrorSnackBar(
        context,
        LocalizationService.instance.translate('operation_failed'),
      );
      return;
    }

    final dynamic rawDifference = result['difference'];
    final double difference = rawDifference is num
        ? rawDifference.toDouble()
        : double.tryParse('$rawDifference') ?? 0;
    ThemeConstants.showInfoSnackBar(
      context,
      difference.abs() < 0.01
          ? LocalizationService.instance.translate('reconciled_balanced')
          : '${LocalizationService.instance.translate('difference')}: '
              'TSH ${difference.toStringAsFixed(0)}',
    );
    await _load();
    if (mounted) {
      await context.read<InventoryProvider>().fetchProducts();
    }
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.controller,
    required this.editable,
  });

  final InvDispatchLine line;
  final TextEditingController? controller;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    return Container(
      decoration: ThemeConstants.glassCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AutoSizeText(
            line.productName,
            maxLines: 1,
            minFontSize: 11,
            overflow: TextOverflow.ellipsis,
            style:
                ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 4.h),
          InvKeyValueWrap(entries: <String, String>{
            loc.translate('loaded'): '${line.loadedQuantity}',
            if (!editable)
              loc.translate('returned'): '${line.returnedQuantity}',
            if (!editable) loc.translate('sold'): '${line.soldQuantity}',
            loc.translate('unit_price'): line.unitPrice.toStringAsFixed(0),
          }),
          if (editable && controller != null) ...<Widget>[
            SizedBox(height: 8.h),
            InvTextField(
              controller: controller!,
              label: loc.translate('returned_quantity'),
              hint: 'e.g. 5',
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
          ],
        ],
      ),
    );
  }
}
