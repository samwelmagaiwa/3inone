import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_batch.dart';
import '../../models/inv_product.dart';
import '../../providers/depot_provider.dart';
import '../../providers/inventory_provider.dart';
import '../scanning/barcode_scanner_screen.dart';
import '../widgets/inventory_widgets.dart';

/// Area 3 — physical stock counts with variance.
class StockCountsScreen extends StatefulWidget {
  const StockCountsScreen({super.key});

  @override
  State<StockCountsScreen> createState() => _StockCountsScreenState();
}

class _StockCountsScreenState extends State<StockCountsScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Draw whatever is already cached; only show a spinner on a cold start.
    _loading = context.read<InventoryProvider>().stockCounts.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await context.read<InventoryProvider>().fetchStockCounts();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final List<InvStockCount> counts =
        context.watch<InventoryProvider>().stockCounts;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'stock_counts_fab',
        backgroundColor: ThemeConstants.primaryOrange,
        onPressed: _openNewCount,
        icon: const Icon(Icons.playlist_add_check, color: Colors.white),
        label: Text(
          loc.translate('new_stock_count'),
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
                child: counts.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: <Widget>[
                          SizedBox(height: 80.h),
                          InvEmptyState(
                            icon: Icons.fact_check_outlined,
                            message: loc.translate('no_stock_counts'),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 88.h),
                        itemCount: counts.length,
                        separatorBuilder: (_, __) => SizedBox(height: 8.h),
                        itemBuilder: (_, int i) => _CountCard(
                          count: counts[i],
                          onOpen: () => _openCount(counts[i].id),
                        ),
                      ),
              ),
      ),
    );
  }

  Future<void> _openNewCount() async {
    final int? id = await context.read<InventoryProvider>().openStockCount();
    if (id == null) {
      if (mounted) {
        ThemeConstants.showErrorSnackBar(
          context,
          LocalizationService.instance.translate('operation_failed'),
        );
      }
      return;
    }
    await _openCount(id);
  }

  Future<void> _openCount(int id) async {
    if (!mounted) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => StockCountDetailScreen(countId: id),
      ),
    );
    await _load();
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.count, required this.onOpen});

  final InvStockCount count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final (Color color, String label) = switch (count.status) {
      'posted' => (ThemeConstants.successGreen, loc.translate('posted')),
      'cancelled' => (ThemeConstants.errorRed, loc.translate('cancelled')),
      _ => (ThemeConstants.warningAmber, loc.translate('draft')),
    };

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(20.r),
      child: Container(
        decoration: ThemeConstants.glassCardDecoration,
        padding: EdgeInsets.all(12.w),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AutoSizeText(
                    count.reference,
                    maxLines: 1,
                    minFontSize: 11,
                    overflow: TextOverflow.ellipsis,
                    style: ThemeConstants.bodyStyle
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 2.h),
                  AutoSizeText(
                    <String>[
                      '${count.linesCount} ${loc.translate('lines')}',
                      '${loc.translate('variance')}: ${count.totalVariance}',
                      if (count.countedByName.isNotEmpty) count.countedByName,
                    ].join('  •  '),
                    maxLines: 1,
                    minFontSize: 9,
                    overflow: TextOverflow.ellipsis,
                    style: ThemeConstants.captionStyle,
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            InvBadge(label: label, color: color),
            Icon(Icons.chevron_right, color: Colors.white38, size: 20.sp),
          ],
        ),
      ),
    );
  }
}

/// One count: capture counted quantities, see variance, then post.
class StockCountDetailScreen extends StatefulWidget {
  const StockCountDetailScreen({required this.countId, super.key});

  final int countId;

  @override
  State<StockCountDetailScreen> createState() => _StockCountDetailScreenState();
}

class _StockCountDetailScreenState extends State<StockCountDetailScreen> {
  InvStockCount? _count;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final InvStockCount? fresh =
        await context.read<InventoryProvider>().fetchStockCount(widget.countId);
    if (mounted) {
      setState(() {
        _count = fresh;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InvStockCount? count = _count;
    final bool isDraft = count?.isDraft ?? false;
    final int netVariance = (count?.lines ?? const <InvStockCountLine>[])
        .fold<int>(0, (int sum, InvStockCountLine l) => sum + l.variance);

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: ThemeConstants.textPrimary),
        title: AutoSizeText(
          count?.reference ?? loc.translate('stock_count'),
          maxLines: 1,
          minFontSize: 13,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ThemeConstants.textPrimary,
            fontSize: 19.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: <Widget>[
          if (isDraft)
            IconButton(
              tooltip: loc.translate('cancel'),
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: _busy ? null : _cancel,
            ),
        ],
      ),
      floatingActionButton: isDraft
          ? FloatingActionButton.extended(
              heroTag: 'stock_count_line_fab',
              backgroundColor: ThemeConstants.primaryOrange,
              onPressed: _busy ? null : _openLineSheet,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                loc.translate('count_item'),
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
      bottomNavigationBar: isDraft
          ? SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 8.h),
                child: InvPrimaryButton(
                  busy: _busy,
                  label: loc.translate('post_count'),
                  color: ThemeConstants.successGreen,
                  onPressed: _post,
                ),
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
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 96.h),
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: InvStatTile(
                            label: loc.translate('lines'),
                            value: '${count?.lines.length ?? 0}',
                            icon: Icons.list_alt_outlined,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: InvStatTile(
                            label: loc.translate('net_variance'),
                            value: netVariance > 0
                                ? '+$netVariance'
                                : '$netVariance',
                            icon: Icons.calculate_outlined,
                            accent: netVariance == 0
                                ? ThemeConstants.successGreen
                                : ThemeConstants.warningAmber,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),
                    if ((count?.lines ?? const <InvStockCountLine>[]).isEmpty)
                      InvEmptyState(
                        icon: Icons.fact_check_outlined,
                        message: loc.translate('nothing_counted_yet'),
                      )
                    else
                      ...count!.lines.map(
                        (InvStockCountLine l) => Padding(
                          padding: EdgeInsets.only(bottom: 8.h),
                          child: _LineCard(
                            line: l,
                            onDelete: isDraft ? () => _deleteLine(l) : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _openLineSheet() async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CountLineSheet(countId: widget.countId),
    );
    if ((saved ?? false) && mounted) {
      await _load();
    }
  }

  Future<void> _deleteLine(InvStockCountLine line) async {
    final LocalizationService loc = LocalizationService.instance;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(loc.translate('remove_line'),
            style: ThemeConstants.headingStyle),
        content: Text(
          loc.translate('remove_line_confirm').replaceAll(
                '{product}',
                line.productName,
              ),
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

    setState(() => _busy = true);
    await context
        .read<InventoryProvider>()
        .deleteStockCountLine(widget.countId, line.id);
    if (mounted) {
      setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _post() async {
    final LocalizationService loc = LocalizationService.instance;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(loc.translate('post_count'),
            style: ThemeConstants.headingStyle),
        content: Text(
          loc.translate('post_count_confirm'),
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
              loc.translate('post_count'),
              style: const TextStyle(color: ThemeConstants.successGreen),
            ),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) {
      return;
    }

    setState(() => _busy = true);
    final InventoryProvider inv = context.read<InventoryProvider>();
    final bool done = await inv.postStockCount(widget.countId);
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    ThemeConstants.showInfoSnackBar(
      context,
      done
          ? LocalizationService.instance.translate('stock_count_posted')
          : (inv.lastStockCountError ??
              LocalizationService.instance.translate('operation_failed')),
    );
    await _load();
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    await context.read<InventoryProvider>().cancelStockCount(widget.countId);
    if (mounted) {
      setState(() => _busy = false);
      await _load();
    }
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line, this.onDelete});

  final InvStockCountLine line;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final Color varianceColor = line.matches
        ? ThemeConstants.successGreen
        : (line.variance > 0
            ? ThemeConstants.warningAmber
            : ThemeConstants.errorRed);

    return Container(
      decoration: ThemeConstants.glassCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AutoSizeText(
                  line.productName,
                  maxLines: 1,
                  minFontSize: 11,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.bodyStyle
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2.h),
                AutoSizeText(
                  <String>[
                    '${loc.translate('system')}: ${line.systemQuantity}',
                    '${loc.translate('counted')}: ${line.countedQuantity}',
                    if (line.batchNumber.isNotEmpty) line.batchNumber,
                  ].join('  •  '),
                  maxLines: 1,
                  minFontSize: 9,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.captionStyle,
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          InvBadge(
            label: line.variance > 0 ? '+${line.variance}' : '${line.variance}',
            color: varianceColor,
          ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline,
                color: Colors.white38,
                size: 20.sp,
              ),
            ),
        ],
      ),
    );
  }
}

class _CountLineSheet extends StatefulWidget {
  const _CountLineSheet({required this.countId});

  final int countId;

  @override
  State<_CountLineSheet> createState() => _CountLineSheetState();
}

class _CountLineSheetState extends State<_CountLineSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _counted = TextEditingController();
  final TextEditingController _note = TextEditingController();
  int? _productId;
  int? _batchId;
  bool _countByBatch = false;
  bool _saving = false;

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
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
    setState(() {
      _productId = matches.first.id;
      _batchId = null;
      _countByBatch = false;
    });
  }

  Future<void> _save() async {
    final LocalizationService loc = LocalizationService.instance;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_productId == null) {
      ThemeConstants.showWarningSnackBar(
        context,
        loc.translate('select_product'),
      );
      return;
    }

    setState(() => _saving = true);
    final InventoryProvider inv = context.read<InventoryProvider>();
    final bool ok = await inv.saveStockCountLine(
      widget.countId,
      productId: _productId!,
      countedQuantity: int.parse(_counted.text.trim()),
      batchId: _batchId,
      note: _note.text.trim(),
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
        inv.lastStockCountError ?? loc.translate('operation_failed'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InventoryProvider inv = context.watch<InventoryProvider>();
    final List<InvBatch> batches =
        _productId == null ? const <InvBatch>[] : inv.batchesOf(_productId!);

    return InvSheetShell(
      title: loc.translate('count_item'),
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
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
                      items: inv.products
                          .map(
                            (InvProduct p) => DropdownMenuItem<int>(
                              value: p.id,
                              child: Text(
                                '${p.name}  (${p.quantity})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ThemeConstants.bodyStyle,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (int? v) => setState(() {
                        _productId = v;
                        _batchId = null;
                        _countByBatch = false;
                      }),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  IconButton(
                    tooltip: loc.translate('scan_barcode'),
                    onPressed: () => _scanForProduct(inv.products),
                    icon: const Icon(Icons.qr_code_scanner,
                        color: Colors.white70),
                  ),
                ],
              ),
              if (batches.isNotEmpty) ...<Widget>[
                SizedBox(height: 10.h),
                InkWell(
                  borderRadius: BorderRadius.circular(12.r),
                  onTap: () => setState(() {
                    _countByBatch = !_countByBatch;
                    if (!_countByBatch) _batchId = null;
                  }),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.h),
                    child: Row(
                      children: <Widget>[
                        Switch(
                          value: _countByBatch,
                          activeThumbColor: ThemeConstants.primaryOrange,
                          onChanged: (bool v) => setState(() {
                            _countByBatch = v;
                            if (!v) _batchId = null;
                          }),
                        ),
                        SizedBox(width: 4.w),
                        Expanded(
                          child: Text(
                            loc.translate('count_by_batch'),
                            style: ThemeConstants.bodyStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_countByBatch && batches.isNotEmpty) ...<Widget>[
                SizedBox(height: 6.h),
                DropdownButtonFormField<int>(
                  initialValue: _batchId,
                  isExpanded: true,
                  dropdownColor: ThemeConstants.primaryBlue,
                  style: ThemeConstants.bodyStyle,
                  decoration:
                      ThemeConstants.invInputDecoration(loc.translate('batch')),
                  items: batches
                      .map(
                        (InvBatch b) => DropdownMenuItem<int>(
                          value: b.id,
                          child: Text(
                            '${b.batchNumber} — ${b.quantity}',
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
                controller: _counted,
                label: loc.translate('counted_quantity'),
                hint: 'e.g. 48',
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                validator: (String? v) {
                  final int? n = int.tryParse((v ?? '').trim());
                  return (n == null || n < 0)
                      ? loc.translate('enter_valid_number')
                      : null;
                },
              ),
              SizedBox(height: 10.h),
              InvTextField(
                controller: _note,
                label: loc.translate('note'),
                hint: 'e.g. Counted with the shift supervisor',
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
