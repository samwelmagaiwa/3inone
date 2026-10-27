import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../models/user_permissions.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_batch.dart';
import '../../models/inv_product.dart';
import '../../providers/inventory_provider.dart';
import '../widgets/inventory_widgets.dart';

/// Area 3 — batches, expiry dates and stock valuation.
class BatchesScreen extends StatefulWidget {
  const BatchesScreen({super.key});

  @override
  State<BatchesScreen> createState() => _BatchesScreenState();
}

enum _BatchFilter { all, expiringSoon, expired }

class _BatchesScreenState extends State<BatchesScreen> {
  _BatchFilter _filter = _BatchFilter.all;
  String _query = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Draw whatever is already cached; only show a spinner on a cold start.
    _loading = context.read<InventoryProvider>().batches.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final InventoryProvider inv = context.read<InventoryProvider>();
    await Future.wait<void>(<Future<void>>[
      inv.fetchBatches(),
      inv.fetchExpirySummary(),
    ]);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  List<InvBatch> _visible(List<InvBatch> all) {
    final String q = _query.trim().toLowerCase();
    return all.where((InvBatch b) {
      final bool matchesFilter = switch (_filter) {
        _BatchFilter.all => true,
        _BatchFilter.expiringSoon => b.expiresWithin(30),
        _BatchFilter.expired => b.isExpired,
      };
      if (!matchesFilter) {
        return false;
      }
      if (q.isEmpty) {
        return true;
      }
      return b.batchNumber.toLowerCase().contains(q) ||
          b.productName.toLowerCase().contains(q) ||
          b.productSku.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InventoryProvider inv = context.watch<InventoryProvider>();
    final bool canManage = context.select<AuthProvider, UserPermissions>((AuthProvider a) => a.permissions).has('inv_manage_stock');

    final List<InvBatch> rows = _visible(inv.batches);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              heroTag: 'batches_fab',
              backgroundColor: ThemeConstants.primaryOrange,
              onPressed: _openReceiveSheet,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                loc.translate('receive_stock'),
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white70))
            : RefreshIndicator(
                onRefresh: _load,
                backgroundColor: Colors.white,
                color: ThemeConstants.primaryBlue,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: <Widget>[
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _ExpirySummaryRow(
                              expired: inv.expiredBatchCount,
                              expiringSoon: inv.expiringSoonCount,
                              valuation: inv.stockValuation,
                            ),
                            SizedBox(height: 10.h),
                            InvSearchField(
                              hint: loc.translate('search_batches'),
                              onChanged: (String v) =>
                                  setState(() => _query = v),
                            ),
                            SizedBox(height: 8.h),
                            InvFilterChips<_BatchFilter>(
                              value: _filter,
                              options: <_BatchFilter, String>{
                                _BatchFilter.all: loc.translate('all'),
                                _BatchFilter.expiringSoon:
                                    loc.translate('expiring_soon'),
                                _BatchFilter.expired: loc.translate('expired'),
                              },
                              onSelected: (_BatchFilter v) =>
                                  setState(() => _filter = v),
                            ),
                            SizedBox(height: 8.h),
                          ],
                        ),
                      ),
                    ),
                    if (rows.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: InvEmptyState(
                          icon: Icons.inventory_2_outlined,
                          message: loc.translate('no_batches'),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 88.h),
                        sliver: SliverList.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => SizedBox(height: 8.h),
                          itemBuilder: (_, int i) => _BatchCard(
                            batch: rows[i],
                            canManage: canManage,
                            onEditExpiry: () => _pickExpiry(rows[i]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _openReceiveSheet() async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ReceiveStockSheet(),
    );
    if ((saved ?? false) && mounted) {
      ThemeConstants.showSuccessSnackBar(
        context,
        LocalizationService.instance.translate('stock_received'),
      );
    }
  }

  Future<void> _pickExpiry(InvBatch batch) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: batch.expiryDate ?? now.add(const Duration(days: 90)),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) {
      return;
    }
    final bool ok = await context
        .read<InventoryProvider>()
        .updateBatch(batch.id, expiryDate: picked);
    if (mounted) {
      ThemeConstants.showInfoSnackBar(
        context,
        LocalizationService.instance
            .translate(ok ? 'saved' : 'operation_failed'),
      );
    }
  }
}

/// Expired / expiring / valuation at a glance.
class _ExpirySummaryRow extends StatelessWidget {
  const _ExpirySummaryRow({
    required this.expired,
    required this.expiringSoon,
    required this.valuation,
  });

  final int expired;
  final int expiringSoon;
  final double valuation;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    return Row(
      children: <Widget>[
        Expanded(
          child: InvStatTile(
            label: loc.translate('expired'),
            value: '$expired',
            icon: Icons.dangerous_outlined,
            accent: expired > 0 ? ThemeConstants.errorRed : null,
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: InvStatTile(
            label: loc.translate('expiring_soon'),
            value: '$expiringSoon',
            icon: Icons.schedule_outlined,
            accent: expiringSoon > 0 ? ThemeConstants.warningAmber : null,
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: InvStatTile(
            label: loc.translate('stock_value'),
            value: 'TSH ${valuation.toStringAsFixed(0)}',
            icon: Icons.savings_outlined,
          ),
        ),
      ],
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({
    required this.batch,
    required this.canManage,
    required this.onEditExpiry,
  });

  final InvBatch batch;
  final bool canManage;
  final VoidCallback onEditExpiry;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final int? days = batch.daysToExpiry;

    final (Color color, String label) = switch (days) {
      null => (Colors.white38, loc.translate('no_expiry')),
      final int d when d < 0 => (
          ThemeConstants.errorRed,
          '${loc.translate('expired')} ${-d}d'
        ),
      final int d when d <= 30 => (
          ThemeConstants.warningAmber,
          '${d}d ${loc.translate('left')}'
        ),
      _ => (ThemeConstants.successGreen, '${days}d ${loc.translate('left')}'),
    };

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
                  batch.productName.isEmpty
                      ? batch.batchNumber
                      : batch.productName,
                  maxLines: 1,
                  minFontSize: 11,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.bodyStyle
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2.h),
                AutoSizeText(
                  '${loc.translate('batch')}: ${batch.batchNumber}  •  '
                  '${batch.quantity} ${batch.productUnit}',
                  maxLines: 1,
                  minFontSize: 9,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.captionStyle,
                ),
                SizedBox(height: 2.h),
                AutoSizeText(
                  '${loc.translate('cost')}: TSH '
                  '${batch.costPrice.toStringAsFixed(0)}  •  '
                  '${loc.translate('value')}: TSH '
                  '${batch.stockValue.toStringAsFixed(0)}',
                  maxLines: 1,
                  minFontSize: 9,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.captionStyle,
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              InvBadge(label: label, color: color),
              if (canManage) ...<Widget>[
                SizedBox(height: 4.h),
                InkWell(
                  onTap: onEditExpiry,
                  borderRadius: BorderRadius.circular(8.r),
                  child: Padding(
                    padding: EdgeInsets.all(4.w),
                    child: Icon(
                      Icons.event_outlined,
                      size: 18.sp,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Receive stock into a batch, capturing expiry and buying cost.
class _ReceiveStockSheet extends StatefulWidget {
  const _ReceiveStockSheet();

  @override
  State<_ReceiveStockSheet> createState() => _ReceiveStockSheetState();
}

class _ReceiveStockSheetState extends State<_ReceiveStockSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _batchNumber = TextEditingController();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _cost = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  int? _productId;
  DateTime? _expiry;
  bool _saving = false;

  @override
  void dispose() {
    _batchNumber.dispose();
    _quantity.dispose();
    _cost.dispose();
    _reference.dispose();
    super.dispose();
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
    final bool ok = await context.read<InventoryProvider>().receiveBatch(
          productId: _productId!,
          batchNumber: _batchNumber.text.trim().isEmpty
              ? null
              : _batchNumber.text.trim(),
          quantity: int.parse(_quantity.text.trim()),
          expiryDate: _expiry,
          costPrice: double.tryParse(_cost.text.replaceAll(',', '').trim()),
          reference: _reference.text.trim(),
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
        loc.translate('operation_failed'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InventoryProvider inv = context.watch<InventoryProvider>();

    return InvSheetShell(
      title: loc.translate('receive_stock'),
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DropdownButtonFormField<int>(
                initialValue: _productId,
                isExpanded: true,
                dropdownColor: ThemeConstants.primaryBlue,
                style: ThemeConstants.bodyStyle,
                decoration:
                    ThemeConstants.invInputDecoration(loc.translate('product')),
                items: inv.products
                    .map(
                      (InvProduct p) => DropdownMenuItem<int>(
                        value: p.id,
                        child: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ThemeConstants.bodyStyle,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (int? v) => setState(() => _productId = v),
              ),
              SizedBox(height: 10.h),
              InvTextField(
                controller: _batchNumber,
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
                      inputFormatters: <TextInputFormatter>[ThousandsFormatter()],
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
                controller: _reference,
                label: loc.translate('reference'),
                hint: 'e.g. Delivery note number',
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
