import 'dart:async';

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
import '../../providers/depot_provider.dart';
import '../../providers/inventory_provider.dart';
import '../scanning/barcode_scanner_screen.dart';
import '../widgets/inventory_widgets.dart';

/// Area 3 — damages, breakages and expired goods, with approval.
class WriteOffsScreen extends StatefulWidget {
  const WriteOffsScreen({super.key});

  @override
  State<WriteOffsScreen> createState() => _WriteOffsScreenState();
}

class _WriteOffsScreenState extends State<WriteOffsScreen> {
  String _status = 'pending';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Draw whatever is already cached; only show a spinner on a cold start.
    _loading = context.read<InventoryProvider>().writeOffs.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await context.read<InventoryProvider>().fetchWriteOffs(status: _status);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InventoryProvider inv = context.watch<InventoryProvider>();
    final AuthProvider auth = context.read<AuthProvider>();
    // fromUser (not fromRole) honours a per-user explicit grant too, not
    // just the role default -- matters now that inv_report_damage lets a
    // sales_officer submit a write-off without inv_manage_stock, so this
    // button must stay hidden for them specifically (they can submit, not
    // approve).
    final UserPermissions perms = UserPermissions.fromUser(
      userRole: auth.user?.role ?? 'viewer',
      explicitGrants: auth.user?.permissions,
    );
    final bool canApprove = perms.has('inv_manage_stock');

    final List<InvWriteOff> rows = _status == 'all'
        ? inv.writeOffs
        : inv.writeOffs.where((InvWriteOff w) => w.status == _status).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'write_offs_fab',
        backgroundColor: ThemeConstants.primaryOrange,
        onPressed: _openCreateSheet,
        icon: const Icon(Icons.report_problem_outlined, color: Colors.white),
        label: Text(
          loc.translate('record_write_off'),
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
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: <Widget>[
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
                      sliver: SliverToBoxAdapter(
                        child: InvFilterChips<String>(
                          value: _status,
                          options: <String, String>{
                            'pending': loc.translate('pending'),
                            'approved': loc.translate('approved'),
                            'rejected': loc.translate('rejected'),
                            'all': loc.translate('all'),
                          },
                          onSelected: (String v) {
                            setState(() => _status = v);
                            unawaited(_load());
                          },
                        ),
                      ),
                    ),
                    if (rows.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: InvEmptyState(
                          icon: Icons.verified_outlined,
                          message: loc.translate('no_write_offs'),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 88.h),
                        sliver: SliverList.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => SizedBox(height: 8.h),
                          itemBuilder: (_, int i) => _WriteOffCard(
                            writeOff: rows[i],
                            canApprove: canApprove,
                            onDecide: (bool approve) =>
                                _decide(rows[i], approve),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _openCreateSheet() async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _WriteOffFormSheet(),
    );
    if ((saved ?? false) && mounted) {
      ThemeConstants.showSuccessSnackBar(
        context,
        LocalizationService.instance.translate('submitted_for_approval'),
      );
      await _load();
    }
  }

  Future<void> _decide(InvWriteOff writeOff, bool approve) async {
    final LocalizationService loc = LocalizationService.instance;
    final TextEditingController note = TextEditingController();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(
          loc.translate(approve ? 'approve_write_off' : 'reject_write_off'),
          style: ThemeConstants.headingStyle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              approve
                  ? '${loc.translate('approve_removes_stock')}: '
                      '${writeOff.quantity} × ${writeOff.productName}'
                  : writeOff.productName,
              style: ThemeConstants.bodyStyle,
            ),
            SizedBox(height: 12.h),
            InvTextField(
              controller: note,
              label: loc.translate('decision_note'),
              hint: 'e.g. Confirmed damaged on arrival',
              isOptional: true,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              loc.translate(approve ? 'approve' : 'reject'),
              style: TextStyle(
                color: approve
                    ? ThemeConstants.successGreen
                    : ThemeConstants.errorText,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      note.dispose();
      return;
    }

    final bool ok = await context.read<InventoryProvider>().decideWriteOff(
          writeOff.id,
          approve: approve,
          note: note.text.trim(),
        );
    note.dispose();

    if (mounted) {
      ThemeConstants.showInfoSnackBar(
        context,
        LocalizationService.instance
            .translate(ok ? 'saved' : 'operation_failed'),
      );
    }
  }
}

class _WriteOffCard extends StatelessWidget {
  const _WriteOffCard({
    required this.writeOff,
    required this.canApprove,
    required this.onDecide,
  });

  final InvWriteOff writeOff;
  final bool canApprove;
  final ValueChanged<bool> onDecide;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final (Color color, String label) = switch (writeOff.status) {
      'approved' => (ThemeConstants.successGreen, loc.translate('approved')),
      'rejected' => (ThemeConstants.errorRed, loc.translate('rejected')),
      _ => (ThemeConstants.warningAmber, loc.translate('pending')),
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
                  writeOff.productName,
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
          AutoSizeText(
            <String>[
              loc.translate(writeOff.reason),
              '${writeOff.quantity}',
              'TSH ${writeOff.costValue.toStringAsFixed(0)}',
              if (writeOff.batchNumber.isNotEmpty) writeOff.batchNumber,
            ].join('  •  '),
            maxLines: 1,
            minFontSize: 9,
            overflow: TextOverflow.ellipsis,
            style: ThemeConstants.captionStyle,
          ),
          if (writeOff.note.isNotEmpty) ...<Widget>[
            SizedBox(height: 2.h),
            AutoSizeText(
              writeOff.note,
              maxLines: 2,
              minFontSize: 9,
              overflow: TextOverflow.ellipsis,
              style: ThemeConstants.captionStyle,
            ),
          ],
          SizedBox(height: 2.h),
          AutoSizeText(
            <String>[
              writeOff.reference,
              if (writeOff.requestedByName.isNotEmpty) writeOff.requestedByName,
            ].join('  •  '),
            maxLines: 1,
            minFontSize: 9,
            overflow: TextOverflow.ellipsis,
            style: ThemeConstants.captionStyle,
          ),
          if (canApprove && writeOff.isPending) ...<Widget>[
            SizedBox(height: 10.h),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: ThemeConstants.errorRed),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    onPressed: () => onDecide(false),
                    child: Text(
                      loc.translate('reject'),
                      style: const TextStyle(color: ThemeConstants.errorText),
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ThemeConstants.successGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    onPressed: () => onDecide(true),
                    child: Text(
                      loc.translate('approve'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WriteOffFormSheet extends StatefulWidget {
  const _WriteOffFormSheet();

  @override
  State<_WriteOffFormSheet> createState() => _WriteOffFormSheetState();
}

class _WriteOffFormSheetState extends State<_WriteOffFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _note = TextEditingController();
  int? _productId;
  int? _batchId;
  bool _countByBatch = false;
  String _reason = 'damage';
  bool _saving = false;

  @override
  void dispose() {
    _quantity.dispose();
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
    final bool ok = await context.read<InventoryProvider>().createWriteOff(
          productId: _productId!,
          reason: _reason,
          quantity: int.parse(_quantity.text.trim()),
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
        loc.translate('operation_failed'),
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
      title: loc.translate('record_write_off'),
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
                                p.name,
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
              DropdownButtonFormField<String>(
                initialValue: _reason,
                isExpanded: true,
                dropdownColor: ThemeConstants.primaryBlue,
                style: ThemeConstants.bodyStyle,
                decoration:
                    ThemeConstants.invInputDecoration(loc.translate('reason')),
                items: const <String>[
                  'damage',
                  'breakage',
                  'expiry',
                  'theft',
                  'other',
                ]
                    .map(
                      (String r) => DropdownMenuItem<String>(
                        value: r,
                        child: Text(
                          loc.translate(r),
                          style: ThemeConstants.bodyStyle,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (String? v) =>
                    setState(() => _reason = v ?? 'damage'),
              ),
              SizedBox(height: 10.h),
              InvTextField(
                controller: _quantity,
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
              InvTextField(
                controller: _note,
                label: loc.translate('note'),
                hint: 'e.g. Crate dropped during offloading',
                isOptional: true,
                maxLines: 2,
              ),
              SizedBox(height: 8.h),
              Text(
                loc.translate('write_off_needs_approval_note'),
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
