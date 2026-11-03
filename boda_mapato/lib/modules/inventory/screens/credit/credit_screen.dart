import 'customer_account_screen.dart';
import 'customer_report_screen.dart';
import 'merge_customers_screen.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/crates_owed.dart';
import '../../models/inv_customer_debt.dart';
import '../../models/inv_depot_models.dart';
import '../../providers/depot_provider.dart';
import '../widgets/crates_owed_note.dart';
import '../widgets/customer_debt_card.dart';
import '../widgets/inv_action_button.dart';
import '../widgets/glow_list_card.dart';
import '../widgets/joined_sections.dart';
import '../widgets/inventory_widgets.dart';
import '../../providers/inventory_provider.dart';
import '../salon/client_history_screen.dart';

/// Area 6 — credit limits, blocking, statements and debtor ageing.
class CreditScreen extends StatefulWidget {
  const CreditScreen({super.key});

  @override
  State<CreditScreen> createState() => _CreditScreenState();
}

class _CreditScreenState extends State<CreditScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Draw whatever is already cached; only show a spinner on a cold start.
    _loading = context.read<DepotProvider>().creditCustomers.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final DepotProvider depot = context.read<DepotProvider>();
    await Future.wait<void>(<Future<void>>[
      depot.fetchCreditCustomers(),
      depot.fetchDebtorsAgeing(),
      depot.fetchCrateBalances(),
      depot.fetchDuplicateCustomers(),
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
        loc.translate('customers'),
        loc.translate('debtors_ageing'),
      ],
      views: <Widget>[
        _CreditCustomersTab(onRefresh: _load),
        _AgeingTab(onRefresh: _load),
      ],
    );
  }
}

class _CreditCustomersTab extends StatefulWidget {
  const _CreditCustomersTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  State<_CreditCustomersTab> createState() => _CreditCustomersTabState();
}

class _CreditCustomersTabState extends State<_CreditCustomersTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final String q = _query.trim().toLowerCase();
    final int duplicates = context.watch<DepotProvider>().duplicateGroups.length;
    final List<InvCreditCustomer> rows = context
        .watch<DepotProvider>()
        .creditCustomers
        .where((InvCreditCustomer c) =>
            q.isEmpty ||
            c.name.toLowerCase().contains(q) ||
            c.phone.contains(q))
        .toList();

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      backgroundColor: Colors.white,
      color: ThemeConstants.primaryBlue,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
        children: <Widget>[
          if (duplicates > 0) _DuplicatesBanner(groups: duplicates),
          InvSearchField(
            hint: loc.translate('search_customers'),
            onChanged: (String v) => setState(() => _query = v),
          ),
          SizedBox(height: 10.h),
          // Every customer is a row of ONE card, divided from the next by the glowing line of the inventory dashboard.
          if (rows.isNotEmpty)
            GlowListCard(
              dividerKey: 'customer_divider',
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
              children: <Widget>[for (final InvCreditCustomer c in rows) _CreditCustomerCard(customer: c)],
            ),
        ],
      ),
    );
  }
}

/// Said above the list when some customers look like one person saved twice: opens the screen that merges them.
class _DuplicatesBanner extends StatelessWidget {
  const _DuplicatesBanner({required this.groups});

  final int groups;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: InkWell(
        key: const ValueKey<String>('duplicates_banner'),
        borderRadius: BorderRadius.circular(12.r),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MergeCustomersScreen())),
        child: Container(
          padding: EdgeInsets.all(10.w),
          decoration: BoxDecoration(color: ThemeConstants.warningAmber.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12.r), border: Border.all(color: ThemeConstants.warningAmber)),
          child: Row(
            children: <Widget>[
              Icon(Icons.merge_type_rounded, color: ThemeConstants.warningAmber, size: 22.sp),
              SizedBox(width: 8.w),
              Expanded(child: Text(loc.translate('dup_banner').replaceAll('{n}', '$groups'), style: ThemeConstants.captionStyle.copyWith(color: Colors.white, fontWeight: FontWeight.w600))),
              const Icon(Icons.chevron_right_rounded, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

/// Is this the salon's home? (False where there is no inventory provider at all, as in the debts screens.)
bool _isSalon(BuildContext context) {
  try {
    return context.read<InventoryProvider>().salonMode;
  } on ProviderNotFoundException {
    return false;
  }
}

/// A few labelled figures side by side with the glowing vertical line of the inventory dashboard between them.
class _CreditFigures extends StatelessWidget {
  const _CreditFigures({required this.figures});

  final List<(String, String)> figures;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < figures.length; i++) ...<Widget>[
            if (i > 0) Padding(padding: EdgeInsets.symmetric(vertical: 4.h, horizontal: 8.w), child: const SizedBox(width: SectionGlowVerticalDivider.lineWidth, child: SectionGlowVerticalDivider())),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(figures[i].$1, style: ThemeConstants.captionStyle),
                  SizedBox(height: 2.h),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(figures[i].$2, maxLines: 1, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreditCustomerCard extends StatelessWidget {
  const _CreditCustomerCard({required this.customer});

  final InvCreditCustomer customer;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    final (Color color, String label) = switch (customer) {
      final InvCreditCustomer c when c.isBlocked => (
          ThemeConstants.errorRed,
          loc.translate('blocked')
        ),
      final InvCreditCustomer c when c.isOverLimit => (
          ThemeConstants.errorRed,
          loc.translate('over_limit')
        ),
      final InvCreditCustomer c when c.isNearLimit => (
          ThemeConstants.warningAmber,
          loc.translate('near_limit')
        ),
      _ => (ThemeConstants.successGreen, loc.translate('ok')),
    };

    return InkWell(
      onTap: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CustomerStatementScreen(
            customerId: customer.id,
            customerName: customer.name,
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(20.r),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: AutoSizeText(
                    customer.name,
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
            // Owes | Credit limit | Available, with the glowing vertical line between them.
            _CreditFigures(figures: <(String, String)>[
              (loc.translate('owes'), 'TSH ${customer.balance.toStringAsFixed(0)}'),
              (loc.translate('credit_limit'), customer.hasLimit ? 'TSH ${customer.creditLimit.toStringAsFixed(0)}' : '—'),
              (loc.translate('available'), customer.hasLimit ? 'TSH ${customer.available.toStringAsFixed(0)}' : '—'),
            ]),
            CratesOwedNote(
              owed: CratesOwed.forCustomer(
                  context.watch<DepotProvider>().crateBalances, customer.id),
              swahili: loc.isSwahili,
              isDepot: context.watch<DepotProvider>().capabilities.isDepot,
            ),
            if (customer.hasLimit) ...<Widget>[
              SizedBox(height: 8.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(6.r),
                child: LinearProgressIndicator(
                  value: customer.usedFraction,
                  minHeight: 6.h,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
            // Salon: the client's page (visits, favourite service, notes, when they are due back).
            if (_isSalon(context)) ...<Widget>[
              SizedBox(height: 8.h),
              InvActionButton(
                key: ValueKey<String>('client_history_${customer.id}'),
                label: loc.isSwahili ? 'Historia ya mteja' : 'Client history',
                icon: Icons.history_rounded,
                color: const Color(0xFF8B5CF6),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(builder: (_) => ClientHistoryScreen(customerId: customer.id, name: customer.name)),
                ),
              ),
            ],
            SizedBox(height: 10.h),
            // The whole account on one page: old debt, new debt, total, every debt with its payments, and all payments by date.
            InvActionButton(
              key: ValueKey<String>('customer_account_${customer.id}'),
              label: loc.translate('cd_account_title'),
              icon: Icons.account_balance_wallet_rounded,
              color: const Color(0xFFF59E0B),
              onPressed: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => CustomerAccountScreen(customer: customer))),
            ),
            SizedBox(height: 8.h),
            // Everything about this customer for any week, month or year: bought, paid, profit brought, what they owe.
            InvActionButton(
              key: ValueKey<String>('customer_report_${customer.id}'),
              label: loc.isSwahili ? 'Ripoti ya mteja (wiki, mwezi, mwaka)' : 'Customer report (week, month, year)',
              icon: Icons.insights_rounded,
              color: const Color(0xFF3B82F6),
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (_) => CustomerReportScreen(customerId: customer.id, name: customer.name)),
              ),
            ),
            SizedBox(height: 8.h),
            Row(
              children: <Widget>[
                Expanded(
                  child: InvActionButton(
                    key: ValueKey<String>('credit_settings_${customer.id}'),
                    label: loc.translate('credit_settings'),
                    icon: Icons.tune_rounded,
                    color: const Color(0xFF94A3B8),
                    filled: false,
                    arrow: false,
                    onPressed: () => showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => _CreditSettingsSheet(customer: customer),
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: InvActionButton(
                    key: ValueKey<String>('receive_payment_${customer.id}'),
                    label: loc.translate('receive_payment'),
                    icon: Icons.payments_rounded,
                    color: ThemeConstants.successGreen,
                    arrow: false,
                    onPressed: () => showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => ReceivePaymentSheet(customer: customer),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreditSettingsSheet extends StatefulWidget {
  const _CreditSettingsSheet({required this.customer});

  final InvCreditCustomer customer;

  @override
  State<_CreditSettingsSheet> createState() => _CreditSettingsSheetState();
}

class _CreditSettingsSheetState extends State<_CreditSettingsSheet> {
  late final TextEditingController _limit = TextEditingController(
      text: widget.customer.creditLimit.toStringAsFixed(0));
  late final TextEditingController _terms =
      TextEditingController(text: '${widget.customer.paymentTermsDays}');
  late final TextEditingController _reason =
      TextEditingController(text: widget.customer.blockReason);
  late bool _blocked = widget.customer.isBlocked;
  bool _saving = false;

  @override
  void dispose() {
    _limit.dispose();
    _terms.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final bool ok = await context.read<DepotProvider>().updateCredit(
          widget.customer.id,
          creditLimit: double.tryParse(_limit.text.replaceAll(',', '').trim()) ?? 0,
          paymentTermsDays: int.tryParse(_terms.text.trim()) ?? 0,
          isBlocked: _blocked,
          blockReason: _reason.text.trim(),
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
      title: '${loc.translate('credit_settings')} — ${widget.customer.name}',
      children: <Widget>[
        InvTextField(
          controller: _limit,
          label: '${loc.translate('credit_limit')} (TSH)',
          hint: 'e.g. 500,000',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[ThousandsFormatter()],
        ),
        SizedBox(height: 10.h),
        InvTextField(
          controller: _terms,
          label: loc.translate('payment_terms_days'),
          hint: 'e.g. 14',
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
        ),
        SizedBox(height: 6.h),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _blocked,
          activeThumbColor: ThemeConstants.errorRed,
          onChanged: (bool v) => setState(() => _blocked = v),
          title: AutoSizeText(
            loc.translate('block_customer'),
            maxLines: 1,
            minFontSize: 11,
            style: ThemeConstants.bodyStyle,
          ),
          subtitle: AutoSizeText(
            loc.translate('block_customer_note'),
            maxLines: 2,
            minFontSize: 9,
            style: ThemeConstants.captionStyle,
          ),
        ),
        if (_blocked) ...<Widget>[
          SizedBox(height: 6.h),
          InvTextField(
            controller: _reason,
            label: loc.translate('block_reason'),
            hint: LocalizationService.instance.translate('e_g_not_paying_overdue_invoices'),
            isOptional: true,
          ),
        ],
        SizedBox(height: 16.h),
        InvPrimaryButton(busy: _saving, onPressed: _save),
      ],
    );
  }
}

/// Take money against a customer's debt: the OLD debt (from before the app) and the NEW debt (credit sales) are shown apart, with the
/// total of both, and the money is shared between them as chosen here.
class ReceivePaymentSheet extends StatefulWidget {
  const ReceivePaymentSheet({super.key, required this.customer});

  final InvCreditCustomer customer;

  @override
  State<ReceivePaymentSheet> createState() => _ReceivePaymentSheetState();
}

/// One debt that can be paid: an old debt entry, or a credit sale.
class _PayLine {
  _PayLine({required this.isOld, required this.id, required this.title, required this.left, required this.paid, this.date, this.due, this.status = ''});

  final bool isOld;
  final int id;
  final String title;
  final double left;
  final double paid;
  final DateTime? date;
  final DateTime? due;
  final String status;
  final TextEditingController amount = TextEditingController();
  bool selected = false;

  double get entered => double.tryParse(amount.text.replaceAll(',', '').trim()) ?? 0;
}

class _ReceivePaymentSheetState extends State<ReceivePaymentSheet> {
  final TextEditingController _reference = TextEditingController();
  String _method = 'cash';
  bool _loading = true;
  bool _saving = false;
  bool _failed = false;

  CustomerDebtSummary? _debt;
  final List<_PayLine> _lines = <_PayLine>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final CustomerDebtSummary? s = await context.read<DepotProvider>().fetchCustomerDebtSummary(widget.customer.id);
    if (!mounted) return;
    for (final _PayLine l in _lines) {
      l.amount.dispose();
    }
    _lines.clear();
    if (s != null) {
      for (final OldDebtEntry e in s.oldEntries.where((final OldDebtEntry e) => e.left > 0)) {
        _lines.add(_PayLine(isOld: true, id: e.id, title: e.note?.trim().isNotEmpty == true ? e.note!.trim() : LocalizationService.instance.translate('cd_old_title'), left: e.left, paid: e.paid, date: DateTime.tryParse(e.startedOn)));
      }
      for (final NewDebtSale sale in s.newSales) {
        _lines.add(_PayLine(isOld: false, id: sale.id, title: sale.number.isEmpty ? '—' : sale.number, left: sale.left, paid: sale.paid, date: DateTime.tryParse(sale.createdAt ?? ''), due: DateTime.tryParse(sale.dueDate ?? ''), status: sale.paymentStatus));
      }
    }
    setState(() {
      _debt = s;
      _failed = s == null;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _reference.dispose();
    for (final _PayLine l in _lines) {
      l.amount.dispose();
    }
    super.dispose();
  }

  double get _totalEntered => _lines.where((final _PayLine l) => l.selected).fold<double>(0, (final double s, final _PayLine l) => s + l.entered);

  Future<void> _save() async {
    final List<Map<String, dynamic>> sales = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> old = <Map<String, dynamic>>[];
    for (final _PayLine l in _lines) {
      if (!l.selected || l.entered <= 0) continue;
      (l.isOld ? old : sales).add(<String, dynamic>{l.isOld ? 'debt_id' : 'sale_id': l.id, 'amount': l.entered});
    }

    if (sales.isEmpty && old.isEmpty) {
      ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translate('select_at_least_one_debt_and'));
      return;
    }

    setState(() => _saving = true);
    final double total = _totalEntered;
    final Map<String, dynamic>? result = await context.read<DepotProvider>().receivePayment(
          customerId: widget.customer.id,
          amount: total,
          method: _method,
          reference: _reference.text.trim(),
          allocations: sales,
          oldAllocations: old,
        );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result == null) {
      ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translate('operation_failed'));
      return;
    }

    Navigator.pop(context, true);
    ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('payment_recorded'));
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final CustomerDebtSummary? debt = _debt;
    final List<_PayLine> oldLines = _lines.where((final _PayLine l) => l.isOld).toList();
    final List<_PayLine> newLines = _lines.where((final _PayLine l) => !l.isOld).toList();

    return InvSheetShell(
      title: '${loc.translate('receive_payment')} — ${widget.customer.name}',
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: Colors.white54)),
          )
        else if (_failed || debt == null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            child: Column(
              children: <Widget>[
                Text(
                  loc.translate('receive_payment_load_failed'),
                  key: const ValueKey<String>('debts_load_failed'),
                  style: ThemeConstants.captionStyle,
                  textAlign: TextAlign.center,
                ),
                TextButton(key: const ValueKey<String>('debts_retry'), onPressed: _load, child: Text(loc.translate('retry'))),
              ],
            ),
          )
        else ...<Widget>[
          // The three parts: old debt, new debt, and the total of both
          CustomerDebtCard(summary: debt),
          SizedBox(height: 14.h),
          if (_lines.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16.h),
              child: Text(loc.translate('no_outstanding_debts_found'), style: ThemeConstants.captionStyle, textAlign: TextAlign.center),
            )
          else ...<Widget>[
            Text(loc.translate('select_debts_to_pay'), style: ThemeConstants.captionStyle.copyWith(color: Colors.white70)),
            SizedBox(height: 8.h),
            if (oldLines.isNotEmpty) ...<Widget>[
              _groupTitle(loc.translate('cd_old_title')),
              ...oldLines.map(_lineTile),
            ],
            if (newLines.isNotEmpty) ...<Widget>[
              _groupTitle(loc.translate('cd_new_title')),
              ...newLines.map(_lineTile),
            ],
            if (_totalEntered > 0) ...<Widget>[
              SizedBox(height: 4.h),
              _summaryRow(loc.translate('total_payment'), _totalEntered, ThemeConstants.successGreen, const ValueKey<String>('payment_entered')),
              _summaryRow(loc.translate('cd_balance_after_payment'), (debt.totalLeft - _totalEntered).clamp(0, double.infinity).toDouble(), ThemeConstants.warningAmber, const ValueKey<String>('balance_after_payment')),
            ],
            SizedBox(height: 14.h),
          ],
        ],

        // Method
        DropdownButtonFormField<String>(
          initialValue: _method,
          isExpanded: true,
          dropdownColor: ThemeConstants.primaryBlue,
          style: ThemeConstants.bodyStyle,
          decoration: ThemeConstants.invInputDecoration(loc.translate('method')),
          items: const ['cash', 'mobile_money', 'bank_transfer', 'cheque']
              .map((m) => DropdownMenuItem(
                    value: m,
                    child: Text(loc.translate(m), maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _method = v ?? 'cash'),
        ),
        SizedBox(height: 10.h),
        InvTextField(
          controller: _reference,
          label: loc.translate('reference'),
          hint: LocalizationService.instance.translate('e_g_m_pesa_code_or'),
          isOptional: true,
        ),
        SizedBox(height: 16.h),
        InvPrimaryButton(busy: _saving, onPressed: _save),
      ],
    );
  }

  Widget _groupTitle(final String title) => Padding(
        padding: EdgeInsets.only(top: 6.h, bottom: 6.h),
        child: Text(title.toUpperCase(), style: ThemeConstants.captionStyle.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1)),
      );

  Widget _summaryRow(final String label, final double value, final Color color, final Key key) => Padding(
        key: key,
        padding: EdgeInsets.symmetric(vertical: 2.h),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Text('$label: ', style: ThemeConstants.captionStyle),
            Text('TSH ${value.toStringAsFixed(0)}', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );

  /// One debt (old or new) that can be ticked and paid in part or in full.
  Widget _lineTile(final _PayLine l) {
    final bool overdue = l.due != null && l.due!.isBefore(DateTime.now());
    return Container(
      key: ValueKey<String>('pay_line_${l.isOld ? 'old' : 'sale'}_${l.id}'),
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: l.selected ? ThemeConstants.successGreen.withOpacity(0.12) : ThemeConstants.invFill,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: l.selected ? ThemeConstants.successGreen.withOpacity(0.5) : ThemeConstants.invBorder),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
            onTap: () => setState(() {
              l.selected = !l.selected;
              if (l.selected && l.amount.text.isEmpty) l.amount.text = formatAmount(l.left.round());
            }),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              child: Row(
                children: [
                  Icon(l.selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked, color: l.selected ? ThemeConstants.successGreen : Colors.white38, size: 20.sp),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.title, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                        SizedBox(height: 2.h),
                        Row(
                          children: [
                            if (l.date != null) Text('${l.date!.day}/${l.date!.month}/${l.date!.year}', style: ThemeConstants.captionStyle),
                            if (l.due != null) ...[
                              Text(' · ', style: ThemeConstants.captionStyle),
                              Text(
                                LocalizationService.instance.translateWith('due_2', <Object?>[l.due!.day, l.due!.month, l.due!.year]),
                                style: ThemeConstants.captionStyle.copyWith(color: overdue ? ThemeConstants.errorText : Colors.white54),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('TSH ${l.left.toStringAsFixed(0)}', style: ThemeConstants.bodyStyle.copyWith(color: overdue ? ThemeConstants.errorText : ThemeConstants.warningAmber, fontWeight: FontWeight.w700)),
                      if (l.paid > 0)
                        Text(LocalizationService.instance.translateWith('partial_paid', <Object?>[l.paid.toStringAsFixed(0)]), style: ThemeConstants.captionStyle.copyWith(fontSize: 10.sp)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (l.selected)
            Padding(
              padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 10.h),
              child: TextField(
                key: ValueKey<String>('pay_amount_${l.isOld ? 'old' : 'sale'}_${l.id}'),
                controller: l.amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[ThousandsFormatter()],
                onChanged: (_) => setState(() {}),
                decoration: ThemeConstants.invInputDecoration('Amount to pay (TSH)').copyWith(
                  hintText: LocalizationService.instance.translateWith('max', <Object?>[l.left.toStringAsFixed(0)]),
                ),
                style: ThemeConstants.bodyStyle,
              ),
            ),
        ],
      ),
    );
  }
}

class _AgeingTab extends StatelessWidget {
  const _AgeingTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final DepotProvider depot = context.watch<DepotProvider>();
    final List<InvDebtorAgeing> rows = depot.debtors;
    final Map<String, double> totals = depot.debtorTotals;

    return RefreshIndicator(
      onRefresh: onRefresh,
      backgroundColor: Colors.white,
      color: ThemeConstants.primaryBlue,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: InvStatTile(
                  label: loc.translate('total_owed'),
                  value:
                      'TSH ${(totals['grand_total'] ?? 0).toStringAsFixed(0)}',
                  icon: Icons.account_balance_wallet_outlined,
                  accent: ThemeConstants.warningAmber,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: InvStatTile(
                  label: '90+ ${loc.translate('days')}',
                  value:
                      'TSH ${(totals['days_90_plus'] ?? 0).toStringAsFixed(0)}',
                  icon: Icons.warning_amber_rounded,
                  accent: (totals['days_90_plus'] ?? 0) > 0
                      ? ThemeConstants.errorRed
                      : null,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          if (rows.isEmpty)
            InvEmptyState(
              icon: Icons.verified_outlined,
              message: loc.translate('no_debtors'),
            )
          else
            GlowListCard(
              dividerKey: 'ageing_divider',
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              children: <Widget>[for (final InvDebtorAgeing d in rows) _AgeingCard(debtor: d)],
            ),
        ],
      ),
    );
  }
}

class _AgeingCard extends StatelessWidget {
  const _AgeingCard({required this.debtor});

  final InvDebtorAgeing debtor;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: AutoSizeText(
                  debtor.customerName,
                  maxLines: 1,
                  minFontSize: 11,
                  overflow: TextOverflow.ellipsis,
                  style: ThemeConstants.bodyStyle
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(width: 8.w),
              InvBadge(
                label: 'TSH ${debtor.total.toStringAsFixed(0)}',
                color: debtor.days90Plus > 0
                    ? ThemeConstants.errorRed
                    : ThemeConstants.warningAmber,
              ),
            ],
          ),
          SizedBox(height: 6.h),
          _CreditFigures(figures: <(String, String)>[
            ('0-30', debtor.current.toStringAsFixed(0)),
            ('31-60', debtor.days31to60.toStringAsFixed(0)),
            ('61-90', debtor.days61to90.toStringAsFixed(0)),
            ('90+', debtor.days90Plus.toStringAsFixed(0)),
            (loc.translate('oldest'), '${debtor.oldestDays}d'),
          ]),
        ],
      ),
    );
  }
}

/// A customer's statement for a period: opening, movements, closing.
class CustomerStatementScreen extends StatefulWidget {
  const CustomerStatementScreen({
    required this.customerId,
    required this.customerName,
    super.key,
  });

  final int customerId;
  final String customerName;

  @override
  State<CustomerStatementScreen> createState() =>
      _CustomerStatementScreenState();
}

class _CustomerStatementScreenState extends State<CustomerStatementScreen> {
  InvStatement? _statement;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final DepotProvider depot = context.read<DepotProvider>();
    final List<Object?> results = await Future.wait<Object?>(<Future<Object?>>[
      depot.fetchStatement(widget.customerId),
      depot.fetchCrateBalances(),
    ]);
    final InvStatement? s = results.first as InvStatement?;
    if (mounted) {
      setState(() {
        _statement = s;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final InvStatement? s = _statement;

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: ThemeConstants.textPrimary),
        title: AutoSizeText(
          widget.customerName,
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
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              )
            : s == null
                ? InvEmptyState(
                    icon: Icons.receipt_long_outlined,
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
                      padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
                      children: <Widget>[
                        Container(
                          decoration: ThemeConstants.glassCardDecoration,
                          padding: EdgeInsets.all(12.w),
                          child: InvKeyValueWrap(entries: <String, String>{
                            loc.translate('period'): '${s.from} ? ${s.to}',
                            loc.translate('opening'):
                                'TSH ${s.openingBalance.toStringAsFixed(0)}',
                            loc.translate('charges'):
                                'TSH ${s.periodCharges.toStringAsFixed(0)}',
                            loc.translate('payments'):
                                'TSH ${s.periodPayments.toStringAsFixed(0)}',
                            loc.translate('closing'):
                                'TSH ${s.closingBalance.toStringAsFixed(0)}',
                          }),
                        ),
                        CratesOwedNote(
                          owed: CratesOwed.forCustomer(
                              context.watch<DepotProvider>().crateBalances,
                              widget.customerId),
                          swahili: loc.isSwahili,
                          isDepot: context.watch<DepotProvider>().capabilities.isDepot,
                        ),
                        SizedBox(height: 12.h),
                        if (s.lines.isEmpty)
                          InvEmptyState(
                            icon: Icons.history_outlined,
                            message: loc.translate('no_transactions'),
                          )
                        else
                          ...s.lines.map(
                            (InvStatementLine l) => Padding(
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
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          AutoSizeText(
                                            l.description,
                                            maxLines: 1,
                                            minFontSize: 10,
                                            overflow: TextOverflow.ellipsis,
                                            style: ThemeConstants.bodyStyle,
                                          ),
                                          AutoSizeText(
                                            '${l.date.day}/${l.date.month}/${l.date.year}',
                                            maxLines: 1,
                                            minFontSize: 9,
                                            style: ThemeConstants.captionStyle,
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: 8.w),
                                    Text(
                                      l.charge > 0
                                          ? '+${l.charge.toStringAsFixed(0)}'
                                          : '-${l.payment.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        color: l.charge > 0
                                            ? ThemeConstants.warningAmber
                                            : ThemeConstants.successGreen,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.sp,
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
}
