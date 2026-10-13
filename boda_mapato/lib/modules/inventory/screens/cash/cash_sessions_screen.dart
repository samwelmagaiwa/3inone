import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/inv_depot_models.dart';
import '../../providers/depot_provider.dart';
import '../widgets/inventory_widgets.dart';

/// Area 7 — the daily cash reconciliation each staff member does per shift.
class CashSessionsScreen extends StatefulWidget {
  const CashSessionsScreen({super.key});

  @override
  State<CashSessionsScreen> createState() => _CashSessionsScreenState();
}

class _CashSessionsScreenState extends State<CashSessionsScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Draw whatever is already cached; only show a spinner on a cold start.
    _loading = context.read<DepotProvider>().cashSessions.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await context.read<DepotProvider>().fetchCashSessions();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final List<InvCashSession> rows =
        context.watch<DepotProvider>().cashSessions;
    final bool hasOpen = rows.any((InvCashSession s) => s.isOpen);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: hasOpen
          ? null
          : FloatingActionButton.extended(
              heroTag: 'cash_open_fab',
              backgroundColor: ThemeConstants.primaryOrange,
              onPressed: _openSession,
              icon: const Icon(Icons.point_of_sale, color: Colors.white),
              label: Text(
                loc.translate('open_session'),
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
                            icon: Icons.point_of_sale_outlined,
                            message: loc.translate('no_cash_sessions'),
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
                        itemBuilder: (_, int i) => _SessionCard(
                          session: rows[i],
                          onOpen: () => _openDetail(rows[i].id),
                        ),
                      ),
              ),
      ),
    );
  }

  Future<void> _openSession() async {
    final TextEditingController floatCtrl = TextEditingController(text: '0');
    final LocalizationService loc = LocalizationService.instance;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(loc.translate('open_session'),
            style: ThemeConstants.headingStyle),
        content: InvTextField(
          controller: floatCtrl,
          label: loc.translate('opening_float'),
          hint: 'e.g. 50,000',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.translate('open_session')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      floatCtrl.dispose();
      return;
    }

    final int? id = await context.read<DepotProvider>().openCashSession(
          openingFloat: double.tryParse(floatCtrl.text.trim()) ?? 0,
        );
    floatCtrl.dispose();

    if (!mounted) {
      return;
    }
    if (id == null) {
      ThemeConstants.showErrorSnackBar(
        context,
        LocalizationService.instance.translate('session_already_open'),
      );
      return;
    }
    await _openDetail(id);
  }

  Future<void> _openDetail(int id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CashSessionDetailScreen(sessionId: id),
      ),
    );
    await _load();
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onOpen});

  final InvCashSession session;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    final (Color color, String label) = switch (session) {
      final InvCashSession s when s.isOpen => (
          ThemeConstants.primaryCyan,
          loc.translate('open')
        ),
      final InvCashSession s when s.balances => (
          ThemeConstants.successGreen,
          loc.translate('balanced')
        ),
      final InvCashSession s when s.isShort => (
          ThemeConstants.errorRed,
          loc.translate('short')
        ),
      _ => (ThemeConstants.warningAmber, loc.translate('surplus')),
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
                    session.reference,
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
              loc.translate('date'): session.businessDate,
              if (session.userName.isNotEmpty)
                loc.translate('staff'): session.userName,
              if (!session.isOpen)
                loc.translate('difference'):
                    'TSH ${session.difference.toStringAsFixed(0)}',
            }),
          ],
        ),
      ),
    );
  }
}

/// One shift: expenses, expected vs counted, and closing.
class CashSessionDetailScreen extends StatefulWidget {
  const CashSessionDetailScreen({required this.sessionId, super.key});

  final int sessionId;

  @override
  State<CashSessionDetailScreen> createState() =>
      _CashSessionDetailScreenState();
}

class _CashSessionDetailScreenState extends State<CashSessionDetailScreen> {
  InvCashSession? _session;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final InvCashSession? s =
        await context.read<DepotProvider>().fetchCashSession(widget.sessionId);
    if (mounted) {
      setState(() {
        _session = s;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InvCashSession? s = _session;
    final bool isOpen = s?.isOpen ?? false;

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: ThemeConstants.textPrimary),
        title: AutoSizeText(
          s?.reference ?? loc.translate('cash_session'),
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
      floatingActionButton: isOpen
          ? FloatingActionButton.extended(
              heroTag: 'cash_expense_fab',
              backgroundColor: ThemeConstants.primaryOrange,
              onPressed: _busy ? null : _addExpense,
              icon:
                  const Icon(Icons.remove_circle_outline, color: Colors.white),
              label: Text(
                loc.translate('add_expense'),
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
      bottomNavigationBar: isOpen
          ? SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 8.h),
                child: InvPrimaryButton(
                  busy: _busy,
                  label: loc.translate('close_session'),
                  color: ThemeConstants.successGreen,
                  onPressed: _close,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              )
            : s == null
                ? InvEmptyState(
                    icon: Icons.point_of_sale_outlined,
                    message: loc.translate('no_data'),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    backgroundColor: Colors.white,
                    color: ThemeConstants.primaryBlue,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 96.h),
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: InvStatTile(
                                label: loc.translate('expected_cash'),
                                value:
                                    'TSH ${s.expectedCash.toStringAsFixed(0)}',
                                icon: Icons.calculate_outlined,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: InvStatTile(
                                label: loc.translate('expenses'),
                                value:
                                    'TSH ${s.expensesTotal.toStringAsFixed(0)}',
                                icon: Icons.receipt_outlined,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8.h),
                        Container(
                          decoration: ThemeConstants.glassCardDecoration,
                          padding: EdgeInsets.all(12.w),
                          child: InvKeyValueWrap(entries: <String, String>{
                            loc.translate('opening_float'):
                                'TSH ${s.openingFloat.toStringAsFixed(0)}',
                            loc.translate('date'): s.businessDate,
                            if (!s.isOpen)
                              loc.translate('counted'):
                                  'TSH ${s.countedCash.toStringAsFixed(0)}',
                            if (!s.isOpen)
                              loc.translate('difference'):
                                  'TSH ${s.difference.toStringAsFixed(0)}',
                            if (!s.isOpen && s.differenceReason.isNotEmpty)
                              loc.translate('reason'): s.differenceReason,
                          }),
                        ),
                        SizedBox(height: 12.h),
                        AutoSizeText(
                          loc.translate('expenses'),
                          maxLines: 1,
                          minFontSize: 11,
                          style: ThemeConstants.headingStyle,
                        ),
                        SizedBox(height: 8.h),
                        if (s.expenses.isEmpty)
                          InvEmptyState(
                            icon: Icons.receipt_outlined,
                            message: loc.translate('no_expenses'),
                          )
                        else
                          ...s.expenses.map(
                            (InvCashExpense e) => Padding(
                              padding: EdgeInsets.only(bottom: 6.h),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10.w,
                                  vertical: 10.h,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: AutoSizeText(
                                        e.description,
                                        maxLines: 2,
                                        minFontSize: 10,
                                        overflow: TextOverflow.ellipsis,
                                        style: ThemeConstants.bodyStyle,
                                      ),
                                    ),
                                    SizedBox(width: 8.w),
                                    Text(
                                      'TSH ${e.amount.toStringAsFixed(0)}',
                                      style: ThemeConstants.bodyStyle.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Future<void> _addExpense() async {
    final LocalizationService loc = LocalizationService.instance;
    final TextEditingController desc = TextEditingController();
    final TextEditingController amount = TextEditingController();

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(loc.translate('add_expense'),
            style: ThemeConstants.headingStyle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            InvTextField(
              controller: desc,
              label: loc.translate('description'),
              hint: LocalizationService.instance.translate('e_g_fuel_for_delivery_motorbike'),
            ),
            SizedBox(height: 10.h),
            InvTextField(
              controller: amount,
              label: '${loc.translate('amount')} (TSH)',
              hint: 'e.g. 20,000',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
            child: Text(loc.translate('save')),
          ),
        ],
      ),
    );

    final String description = desc.text.trim();
    final double? value = double.tryParse(amount.text.trim());
    desc.dispose();
    amount.dispose();

    if (ok != true || !mounted || description.isEmpty || value == null) {
      return;
    }

    setState(() => _busy = true);
    await context.read<DepotProvider>().addCashExpense(
          widget.sessionId,
          description: description,
          amount: value,
        );
    if (mounted) {
      setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _close() async {
    final LocalizationService loc = LocalizationService.instance;
    final InvCashSession? s = _session;
    if (s == null) {
      return;
    }

    final TextEditingController counted = TextEditingController();
    final TextEditingController reason = TextEditingController();

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setInner) {
          final double? typed = double.tryParse(counted.text.trim());
          final double diff = typed == null ? 0 : typed - s.expectedCash;

          return AlertDialog(
            backgroundColor: ThemeConstants.primaryBlue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
            ),
            title: Text(loc.translate('close_session'),
                style: ThemeConstants.headingStyle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${loc.translate('expected_cash')}: '
                    'TSH ${s.expectedCash.toStringAsFixed(0)}',
                    style: ThemeConstants.bodyStyle,
                  ),
                  SizedBox(height: 10.h),
                  InvTextField(
                    controller: counted,
                    label: loc.translate('counted_cash'),
                    hint: 'e.g. 480,000',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  if (typed != null && diff.abs() > 0.009) ...<Widget>[
                    SizedBox(height: 8.h),
                    Text(
                      '${diff < 0 ? loc.translate('short') : loc.translate('surplus')}: '
                      'TSH ${diff.abs().toStringAsFixed(0)}',
                      style: TextStyle(
                        color: diff < 0
                            ? ThemeConstants.errorRed
                            : ThemeConstants.warningAmber,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    InvTextField(
                      controller: reason,
                      label: loc.translate('explain_difference'),
                      hint: LocalizationService.instance.translate('e_g_gave_change_from_a'),
                    ),
                  ],
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(loc.translate('cancel')),
              ),
              TextButton(
                onPressed: () {
                  setInner(() {});
                  Navigator.pop(ctx, true);
                },
                child: Text(loc.translate('close_session')),
              ),
            ],
          );
        },
      ),
    );

    final double? countedValue = double.tryParse(counted.text.trim());
    final String reasonText = reason.text.trim();
    counted.dispose();
    reason.dispose();

    if (ok != true || !mounted || countedValue == null) {
      return;
    }

    setState(() => _busy = true);
    final String? error = await context.read<DepotProvider>().closeCashSession(
          widget.sessionId,
          countedCash: countedValue,
          reason: reasonText,
        );

    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (error != null) {
      ThemeConstants.showErrorSnackBar(
        context,
        LocalizationService.instance.translate('explain_difference'),
      );
      return;
    }
    await _load();
  }
}
