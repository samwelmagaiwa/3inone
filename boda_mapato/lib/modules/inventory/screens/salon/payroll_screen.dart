import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../providers/inventory_provider.dart';
import '../../services/salon_api.dart';
import '../widgets/inventory_widgets.dart';
import 'salon_text.dart';

/// What each person earns for a month and what has been paid: their salary, the commission they earned on their
/// services, what was paid out and advanced, and what the salon still owes them. The owner records each payment here.
/// (Revenue, commission and the cash a person has handed over are different figures: this page is about pay.)
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key, this.api, this.today});

  /// The server calls (a fake in tests).
  final SalonApi? api;

  /// What "today" is (a test fixes it); the real clock otherwise.
  final DateTime? today;

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  late String _month = _monthOf(widget.today ?? DateTime.now());

  PayrollReport? _report;
  List<Payout> _payouts = <Payout>[];
  String? _error;
  bool _loading = true;

  static String _monthOf(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  DateTime get _today => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final String asked = _month;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final PayrollReport report = await _api.payroll(asked);
      final List<Payout> payouts = await _api.payouts(asked);
      if (!mounted || asked != _month) return;
      setState(() {
        _report = report;
        _payouts = payouts;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted || asked != _month) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  void _go(final int by) {
    setState(() => _month = shiftMonth(_month, by));
    _load();
  }

  Future<void> _pay(final PayrollRow row) async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheet) => _PayoutSheet(api: _api, row: row, month: _month, today: _today),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _editProfile(final PayrollRow row) async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheet) => _ProfileSheet(api: _api, row: row),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _delete(final Payout p) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext d) => AlertDialog(
        title: Text(sw ? 'Futa malipo haya?' : 'Delete this payment?'),
        content: Text('${tsh(p.amount)} • ${p.staffName ?? ''}'),
        actions: <Widget>[
          TextButton(key: const ValueKey<String>('payout_delete_no'), onPressed: () => Navigator.pop(d, false), child: Text(sw ? 'Hapana' : 'No')),
          TextButton(key: const ValueKey<String>('payout_delete_yes'), onPressed: () => Navigator.pop(d, true), child: Text(sw ? 'Futa' : 'Delete')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await _api.deletePayout(p.id);
      if (mounted) await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return Material(
      color: ThemeConstants.primaryBlue,
      child: RefreshIndicator(
        onRefresh: _load,
        backgroundColor: Colors.white,
        color: ThemeConstants.primaryBlue,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
          children: _body(sw),
        ),
      ),
    );
  }

  List<Widget> _body(final bool sw) {
    final PayrollReport? r = _report;

    return <Widget>[
      Row(
        children: <Widget>[
          IconButton(key: const ValueKey<String>('payroll_prev'), onPressed: () => _go(-1), icon: const Icon(Icons.chevron_left, color: Colors.white)),
          Expanded(child: Center(child: Text(monthLabel(sw: sw, month: _month), key: const ValueKey<String>('payroll_month'), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800)))),
          IconButton(key: const ValueKey<String>('payroll_next'), onPressed: () => _go(1), icon: const Icon(Icons.chevron_right, color: Colors.white)),
        ],
      ),
      SizedBox(height: 6.h),
      if (_loading && r == null)
        Padding(padding: EdgeInsets.only(top: 60.h), child: const Center(child: CircularProgressIndicator(color: Colors.white70)))
      else if (_error != null && r == null) ...<Widget>[
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(child: TextButton(key: const ValueKey<String>('payroll_retry'), onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)))),
      ] else if (r != null) ...<Widget>[
        Row(
          children: <Widget>[
            Expanded(child: InvStatTile(label: sw ? 'Mishahara' : 'Salaries', value: tsh(r.salary), icon: Icons.badge_outlined)),
            SizedBox(width: 8.w),
            Expanded(child: InvStatTile(label: sw ? 'Kamisheni' : 'Commission', value: tsh(r.commissionEarned), icon: Icons.percent_rounded, accent: ThemeConstants.warningAmber)),
            SizedBox(width: 8.w),
            Expanded(child: InvStatTile(label: sw ? 'Anadaiwa' : 'Still owed', value: tsh(r.owed), icon: Icons.payments_outlined, accent: ThemeConstants.successGreen)),
          ],
        ),
        SizedBox(height: 12.h),
        if (r.staff.isEmpty)
          InvEmptyState(icon: Icons.people_outline, message: sw ? 'Hakuna wafanyakazi bado.' : 'No staff yet.')
        else
          for (final PayrollRow row in r.staff) ...<Widget>[
            _StaffCard(row: row, sw: sw, onPay: () => _pay(row), onEdit: () => _editProfile(row)),
            SizedBox(height: 8.h),
          ],
        if (_payouts.isNotEmpty) ...<Widget>[
          SizedBox(height: 8.h),
          Text(sw ? 'Malipo ya mwezi huu' : 'Payments this month', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: 6.h),
          for (final Payout p in _payouts)
            ListTile(
              key: ValueKey<String>('payout_${p.id}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('${p.staffName ?? ''} • ${_payoutKind(p.kind, sw)}', style: ThemeConstants.bodyStyle),
              subtitle: Text('${dayLabel(p.paidOn)} • ${channelLabel(sw: sw, channel: p.method)}${p.note == null ? '' : ' • ${p.note}'}', style: ThemeConstants.captionStyle),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Text(tsh(p.amount), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
                IconButton(key: ValueKey<String>('payout_remove_${p.id}'), onPressed: () => _delete(p), icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 20)),
              ]),
            ),
        ],
      ],
    ];
  }
}

String _payoutKind(final String kind, final bool sw) {
  switch (kind) {
    case 'salary':
      return sw ? 'Mshahara' : 'Salary';
    case 'commission':
      return sw ? 'Kamisheni' : 'Commission';
    default:
      return sw ? 'Advance ya mshahara' : 'Salary advance';
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.row, required this.sw, required this.onPay, required this.onEdit});

  final PayrollRow row;
  final bool sw;
  final VoidCallback onPay;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final bool owing = row.owed > 0;

    return Container(
      key: ValueKey<String>('payroll_${row.staffId}'),
      decoration: ThemeConstants.glassCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700))),
              IconButton(key: ValueKey<String>('payroll_profile_${row.staffId}'), tooltip: sw ? 'Mshahara na kiwango cha kamisheni' : 'Salary and commission rate', onPressed: onEdit, icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 20)),
            ],
          ),
          InvKeyValueWrap(entries: <String, String>{
            sw ? 'Mshahara' : 'Salary': tsh(row.salary),
            sw ? 'Kamisheni' : 'Commission': tsh(row.commissionEarned),
            sw ? 'Imelipwa' : 'Paid': tsh(row.salaryPaid + row.commissionPaid),
            'Advance': tsh(row.advances),
          }),
          SizedBox(height: 8.h),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  owing ? (sw ? 'Anadaiwa ${tsh(row.owed)}' : 'Owed ${tsh(row.owed)}') : (sw ? 'Hadaiwi kitu' : 'Nothing owed'),
                  key: ValueKey<String>('payroll_owed_${row.staffId}'),
                  style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800, color: owing ? ThemeConstants.warningAmber : ThemeConstants.successGreen),
                ),
              ),
              OutlinedButton(key: ValueKey<String>('payroll_pay_${row.staffId}'), onPressed: onPay, child: Text(sw ? 'Lipa' : 'Pay', style: const TextStyle(color: Colors.white))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Record a salary, commission or advance paid to one person.
class _PayoutSheet extends StatefulWidget {
  const _PayoutSheet({required this.api, required this.row, required this.month, required this.today});

  final SalonApi api;
  final PayrollRow row;
  final String month;
  final DateTime today;

  @override
  State<_PayoutSheet> createState() => _PayoutSheetState();
}

class _PayoutSheetState extends State<_PayoutSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _kind = 'salary';
  String _method = 'cash';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount.text = widget.row.owed > 0 ? formatAmount(widget.row.owed) : '';
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final double amount = parseAmount(_amount.text);
    if (amount <= 0) {
      setState(() => _error = sw ? 'Andika kiasi.' : 'Write the amount.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.savePayout(
        staffId: widget.row.staffId,
        kind: _kind,
        amount: amount,
        paidOn: widget.today,
        method: _method,
        // A payment made in another month still settles the month being looked at.
        periodMonth: _kind == 'advance' ? null : widget.month,
        note: _note.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return InvSheetShell(
      title: sw ? 'Lipa ${widget.row.name}' : 'Pay ${widget.row.name}',
      children: <Widget>[
        Wrap(
          spacing: 8.w,
          children: <Widget>[
            for (final String k in <String>['salary', 'commission', 'advance'])
              ChoiceChip(key: ValueKey<String>('payout_kind_$k'), label: Text(_payoutKind(k, sw)), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
          ],
        ),
        SizedBox(height: 10.h),
        InvTextField(key: const ValueKey<String>('payout_amount'), controller: _amount, label: sw ? 'Kiasi (TZS)' : 'Amount (TZS)', keyboardType: TextInputType.number, inputFormatters: <TextInputFormatter>[ThousandsFormatter()]),
        SizedBox(height: 10.h),
        Text(sw ? 'Imelipwa kwa' : 'Paid by', style: ThemeConstants.captionStyle),
        SizedBox(height: 4.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 4.h,
          children: <Widget>[
            for (final String c in InventoryProvider.paymentChannels)
              ChoiceChip(key: ValueKey<String>('payout_method_$c'), label: Text(channelLabel(sw: sw, channel: c)), selected: _method == c, onSelected: (_) => setState(() => _method = c)),
          ],
        ),
        SizedBox(height: 10.h),
        InvTextField(key: const ValueKey<String>('payout_note'), controller: _note, label: sw ? 'Maelezo' : 'Note', isOptional: true),
        if (_error != null)
          Padding(padding: EdgeInsets.only(top: 10.h), child: Text(_error!, key: const ValueKey<String>('payout_error'), style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.errorRed, fontSize: 12.sp))),
        SizedBox(height: 14.h),
        InvPrimaryButton(key: const ValueKey<String>('payout_save'), busy: _saving, label: sw ? 'Hifadhi malipo' : 'Save payment', onPressed: _save),
      ],
    );
  }

}

/// A person's specialization, monthly salary and own commission rate.
class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet({required this.api, required this.row});

  final SalonApi api;
  final PayrollRow row;

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  final TextEditingController _specialization = TextEditingController();
  final TextEditingController _salary = TextEditingController();
  final TextEditingController _rate = TextEditingController();
  bool _saving = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _salary.text = widget.row.salary > 0 ? formatAmount(widget.row.salary) : '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _fill());
  }

  Future<void> _fill() async {
    try {
      final List<StaffProfile> all = await widget.api.staffProfiles();
      final StaffProfile? p = all.where((StaffProfile x) => x.staffId == widget.row.staffId).firstOrNull;
      if (!mounted) return;
      setState(() {
        _specialization.text = p?.specialization ?? '';
        _salary.text = (p?.monthlySalary ?? 0) > 0 ? formatAmount(p!.monthlySalary) : '';
        _rate.text = p?.commissionPercent == null ? '' : (p!.commissionPercent! % 1 == 0 ? p.commissionPercent!.toInt().toString() : p.commissionPercent.toString());
        _loaded = true;
      });
    } on Exception {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  void dispose() {
    _specialization.dispose();
    _salary.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final double? rate = double.tryParse(_rate.text.trim().replaceAll(',', '.'));
    if (rate != null && (rate < 0 || rate > 100)) {
      setState(() => _error = sw ? 'Kamisheni iwe kati ya 0 na 100.' : 'The commission must be between 0 and 100 percent.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.saveStaffProfile(
        widget.row.staffId,
        specialization: _specialization.text.trim(),
        monthlySalary: parseAmount(_salary.text),
        commissionPercent: rate,
        clearCommission: rate == null,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return InvSheetShell(
      title: widget.row.name,
      children: <Widget>[
        InvTextField(key: const ValueKey<String>('profile_specialization'), controller: _specialization, label: sw ? 'Kazi (mf. Msusi, Kucha, Makeup)' : 'Specialization (e.g. Hair stylist, Nails, Makeup)', isOptional: true),
        SizedBox(height: 10.h),
        InvTextField(key: const ValueKey<String>('profile_salary'), controller: _salary, label: sw ? 'Mshahara wa mwezi (TZS)' : 'Monthly salary (TZS)', isOptional: true, keyboardType: TextInputType.number, inputFormatters: <TextInputFormatter>[ThousandsFormatter()]),
        SizedBox(height: 10.h),
        InvTextField(key: const ValueKey<String>('profile_rate'), controller: _rate, label: sw ? 'Kamisheni yake mwenyewe (%)' : 'Their own commission (%)', isOptional: true, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        Padding(
          padding: EdgeInsets.only(top: 4.h),
          child: Text(sw ? 'Hutumika kwa huduma isiyo na kiwango chake.' : 'Used for a service that has no rate of its own.', style: ThemeConstants.captionStyle),
        ),
        if (_error != null)
          Padding(padding: EdgeInsets.only(top: 10.h), child: Text(_error!, key: const ValueKey<String>('profile_error'), style: ThemeConstants.captionStyle.copyWith(color: ThemeConstants.errorRed, fontSize: 12.sp))),
        SizedBox(height: 14.h),
        InvPrimaryButton(key: const ValueKey<String>('profile_save'), busy: _saving || !_loaded, label: sw ? 'Hifadhi' : 'Save', onPressed: _save),
      ],
    );
  }
}
