import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_customer.dart';
import '../../models/inv_depot_models.dart';
import '../../providers/depot_provider.dart';
import '../../providers/inventory_provider.dart';
import '../widgets/inventory_widgets.dart';

/// Area 8 — crates and empties, tracked separately from money owed.
class CratesScreen extends StatefulWidget {
  const CratesScreen({super.key});

  @override
  State<CratesScreen> createState() => _CratesScreenState();
}

class _CratesScreenState extends State<CratesScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Draw whatever is already cached; only show a spinner on a cold start.
    _loading = context.read<DepotProvider>().cratePosition.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final DepotProvider depot = context.read<DepotProvider>();
    await Future.wait<void>(<Future<void>>[
      depot.fetchCrateTypes(),
      depot.fetchCratePosition(),
      depot.fetchCrateBalances(),
    ]);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final bool isDepot = context.select<DepotProvider, bool>((DepotProvider d) => d.capabilities.isDepot);

    if (_loading) {
      return const Scaffold(
        backgroundColor: ThemeConstants.primaryBlue,
        body: Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }

    return InvTabScaffold(
      title: '',
      tabs: <String>[
        loc.translateForKind('depot_position', isDepot: isDepot),
        loc.translate('customers'),
      ],
      views: <Widget>[
        _DepotPositionTab(onRefresh: _load),
        _CustomerHoldingsTab(onRefresh: _load),
      ],
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'crates_fab',
        backgroundColor: ThemeConstants.primaryOrange,
        onPressed: () async {
          final bool? saved = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const _CrateMovementSheet(),
          );
          if ((saved ?? false) && mounted) {
            await _load();
          }
        },
        icon: const Icon(Icons.swap_horiz, color: Colors.white),
        label: Text(
          loc.translate('record_movement'),
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

class _DepotPositionTab extends StatelessWidget {
  const _DepotPositionTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  static const TableBorder _border = TableBorder(
    top:              BorderSide(color: Colors.white24, width: 0.8),
    bottom:           BorderSide(color: Colors.white24, width: 0.8),
    left:             BorderSide(color: Colors.white24, width: 0.8),
    right:            BorderSide(color: Colors.white24, width: 0.8),
    horizontalInside: BorderSide(color: Colors.white24, width: 0.8),
    verticalInside:   BorderSide(color: Colors.white24, width: 0.8),
  );

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final List<InvCrateBalance> rows =
        context.watch<DepotProvider>().cratePosition;

    final int totalOut =
        rows.fold<int>(0, (int s, InvCrateBalance c) => s + c.outWithCustomers);
    final double atRisk = rows.fold<double>(
        0, (double s, InvCrateBalance c) => s + c.depositAtRisk);

    final headerStyle = ThemeConstants.captionStyle
        .copyWith(fontWeight: FontWeight.w700, fontSize: 11.sp);
    final cellStyle = ThemeConstants.bodyStyle.copyWith(fontSize: 11.sp);
    final pad = EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h);

    final headers = <String>[
      loc.translate('type'),
      loc.translate('issued'),
      loc.translate('returned'),
      loc.translate('broken'),
      loc.translate('out'),
      loc.translate('deposit'),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      backgroundColor: Colors.white,
      color: ThemeConstants.primaryBlue,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 88.h),
        child: Column(
          children: <Widget>[
            // ── Summary tiles ─────────────────────────────────────
            Row(
              children: <Widget>[
                Expanded(
                  child: InvStatTile(
                    label: loc.translate('out_with_customers'),
                    value: '$totalOut',
                    icon: Icons.outbox_outlined,
                    accent: totalOut > 0 ? ThemeConstants.warningAmber : null,
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: InvStatTile(
                    label: loc.translate('deposit_at_risk'),
                    value: 'TZS ${atRisk.toStringAsFixed(0)}',
                    icon: Icons.savings_outlined,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            // ── Grid table ────────────────────────────────────────
            if (rows.isEmpty)
              InvEmptyState(
                icon: Icons.inbox_outlined,
                message: loc.translate('no_crate_movements'),
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: IntrinsicWidth(
                      child: Table(
                        border: _border,
                        defaultColumnWidth: const IntrinsicColumnWidth(),
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        children: <TableRow>[
                          // Header
                          TableRow(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                            ),
                            children: headers
                                .map((String h) => Padding(
                                      padding: pad,
                                      child: Text(h,
                                          style: headerStyle, maxLines: 1),
                                    ))
                                .toList(),
                          ),
                          // Data rows
                          ...rows.asMap().entries.map(
                            (MapEntry<int, InvCrateBalance> e) {
                              final InvCrateBalance c = e.value;
                              return TableRow(
                                decoration: BoxDecoration(
                                  color: e.key.isOdd
                                      ? Colors.white.withOpacity(0.04)
                                      : Colors.transparent,
                                ),
                                children: <Widget>[
                                  Padding(padding: pad, child: Text(c.crateTypeName, style: cellStyle, maxLines: 2, overflow: TextOverflow.ellipsis)),
                                  Padding(padding: pad, child: Text('${c.issued}', style: cellStyle)),
                                  Padding(padding: pad, child: Text('${c.returned}', style: cellStyle)),
                                  Padding(padding: pad, child: Text('${c.broken}', style: cellStyle)),
                                  Padding(
                                    padding: pad,
                                    child: Text(
                                      '${c.outWithCustomers}',
                                      style: cellStyle.copyWith(
                                        color: c.outWithCustomers > 0
                                            ? ThemeConstants.warningAmber
                                            : null,
                                        fontWeight: c.outWithCustomers > 0
                                            ? FontWeight.bold
                                            : null,
                                      ),
                                    ),
                                  ),
                                  Padding(padding: pad, child: Text('TZS ${c.depositAtRisk.toStringAsFixed(0)}', style: cellStyle)),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CustomerHoldingsTab extends StatelessWidget {
  const _CustomerHoldingsTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  static const TableBorder _border = TableBorder(
    top:              BorderSide(color: Colors.white24, width: 0.8),
    bottom:           BorderSide(color: Colors.white24, width: 0.8),
    left:             BorderSide(color: Colors.white24, width: 0.8),
    right:            BorderSide(color: Colors.white24, width: 0.8),
    horizontalInside: BorderSide(color: Colors.white24, width: 0.8),
    verticalInside:   BorderSide(color: Colors.white24, width: 0.8),
  );

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final List<InvCrateBalance> rows =
        context.watch<DepotProvider>().crateBalances;

    if (rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        backgroundColor: Colors.white,
        color: ThemeConstants.primaryBlue,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            SizedBox(height: 60.h),
            InvEmptyState(
              icon: Icons.people_outline,
              message: loc.translate('no_customer_crates'),
            ),
          ],
        ),
      );
    }

    final headerStyle = ThemeConstants.captionStyle
        .copyWith(fontWeight: FontWeight.w700, fontSize: 11.sp);
    final cellStyle = ThemeConstants.bodyStyle.copyWith(fontSize: 11.sp);
    final pad = EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h);

    final headers = <String>[
      loc.translate('customer'),
      loc.translate('type'),
      loc.translate('held'),
      loc.translate('deposit'),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      backgroundColor: Colors.white,
      color: ThemeConstants.primaryBlue,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 88.h),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: IntrinsicWidth(
              child: Table(
                border: _border,
                defaultColumnWidth: const IntrinsicColumnWidth(),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: <TableRow>[
                  // Header
                  TableRow(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                    ),
                    children: headers
                        .map((String h) => Padding(
                              padding: pad,
                              child: Text(h, style: headerStyle, maxLines: 1),
                            ))
                        .toList(),
                  ),
                  // Data rows
                  ...rows.asMap().entries.map(
                    (MapEntry<int, InvCrateBalance> e) {
                      final InvCrateBalance c = e.value;
                      return TableRow(
                        decoration: BoxDecoration(
                          color: e.key.isOdd
                              ? Colors.white.withOpacity(0.04)
                              : Colors.transparent,
                        ),
                        children: <Widget>[
                          Padding(padding: pad, child: Text(c.customerName, style: cellStyle, maxLines: 2, overflow: TextOverflow.ellipsis)),
                          Padding(padding: pad, child: Text(c.crateTypeName, style: cellStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Padding(
                            padding: pad,
                            child: Text(
                              '${c.held}',
                              style: cellStyle.copyWith(
                                color: c.held > 0 ? ThemeConstants.warningAmber : null,
                                fontWeight: c.held > 0 ? FontWeight.bold : null,
                              ),
                            ),
                          ),
                          Padding(padding: pad, child: Text('TZS ${c.depositAtRisk.toStringAsFixed(0)}', style: cellStyle)),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrateMovementSheet extends StatefulWidget {
  const _CrateMovementSheet();

  @override
  State<_CrateMovementSheet> createState() => _CrateMovementSheetState();
}

class _CrateMovementSheetState extends State<_CrateMovementSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _note = TextEditingController();
  int? _crateTypeId;
  int? _customerId;
  String _direction = 'issued';
  bool _saving = false;

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final LocalizationService loc = LocalizationService.instance;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_crateTypeId == null) {
      ThemeConstants.showWarningSnackBar(
          context, loc.translate('select_crate_type'));
      return;
    }

    setState(() => _saving = true);
    final bool ok = await context.read<DepotProvider>().recordCrateMovement(
          crateTypeId: _crateTypeId!,
          direction: _direction,
          quantity: int.parse(_quantity.text.trim()),
          customerId: _customerId,
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
    final List<InvCrateType> types = context.watch<DepotProvider>().activeCrateTypes;
    final List<InvCustomer> customers =
        context.watch<InventoryProvider>().customers;

    return InvSheetShell(
      title: loc.translate('record_movement'),
      children: <Widget>[
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DropdownButtonFormField<int>(
                initialValue: _crateTypeId,
                isExpanded: true,
                dropdownColor: ThemeConstants.primaryBlue,
                style: ThemeConstants.bodyStyle,
                decoration: ThemeConstants.invInputDecoration(
                    loc.translate('crate_type')),
                items: types
                    .map((InvCrateType t) => DropdownMenuItem<int>(
                          value: t.id,
                          child: Text(
                            t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ThemeConstants.bodyStyle,
                          ),
                        ))
                    .toList(),
                onChanged: (int? v) => setState(() => _crateTypeId = v),
              ),
              SizedBox(height: 10.h),
              DropdownButtonFormField<String>(
                initialValue: _direction,
                isExpanded: true,
                dropdownColor: ThemeConstants.primaryBlue,
                style: ThemeConstants.bodyStyle,
                decoration: ThemeConstants.invInputDecoration(
                    loc.translate('direction')),
                items: const <String>[
                  'issued',
                  'returned',
                  'broken',
                  'purchased',
                ]
                    .map((String d) => DropdownMenuItem<String>(
                          value: d,
                          child: Text(
                            loc.translate(d),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ThemeConstants.bodyStyle,
                          ),
                        ))
                    .toList(),
                onChanged: (String? v) =>
                    setState(() => _direction = v ?? 'issued'),
              ),
              SizedBox(height: 10.h),
              DropdownButtonFormField<int>(
                initialValue: _customerId,
                isExpanded: true,
                dropdownColor: ThemeConstants.primaryBlue,
                style: ThemeConstants.bodyStyle,
                decoration: ThemeConstants.invInputDecoration(
                  '${loc.translate('customer')} (${loc.translate('optional')})',
                ),
                items: customers
                    .map((InvCustomer c) => DropdownMenuItem<int>(
                          value: c.id,
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ThemeConstants.bodyStyle,
                          ),
                        ))
                    .toList(),
                onChanged: (int? v) => setState(() => _customerId = v),
              ),
              SizedBox(height: 10.h),
              InvTextField(
                controller: _quantity,
                label: loc.translate('quantity'),
                hint: 'e.g. 10',
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
                hint: 'e.g. Delivered with today\'s order',
                isOptional: true,
              ),
              SizedBox(height: 8.h),
              Text(
                loc.translate('crates_separate_note'),
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
