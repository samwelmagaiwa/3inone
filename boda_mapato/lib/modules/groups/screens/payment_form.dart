import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../models/group_loan_models.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'payment_methods_screen.dart';
import 'widgets/groups_ui.dart';

/// The form for money a member pays in -- by the member for themself ([member] null), or by an officer for a member -- and, for whoever
/// records payouts, a savings withdrawal. Everything is sent WAITING: it counts only after someone else verifies it. Returns true when one
/// was sent. [owing] are the member's open contributions (to choose which one is paid); [obligation] starts the form on one of them.
Future<bool> showPaymentForm(
  final BuildContext context, {
  required final GroupsApi api,
  required final GroupMe me,
  final GroupMember? member,
  final Map<String, double>? paid,
  final List<GroupObligation>? owing,
  final GroupObligation? obligation,
  final GroupLoan? loan,
}) async {
  final bool? sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ThemeConstants.bgMid,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (final BuildContext c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _PaymentForm(
        api: api,
        me: me,
        member: member,
        paid: paid ?? (member == null ? me.balances : null) ?? const <String, double>{},
        owing: owing ?? (member == null ? me.owing : const <GroupObligation>[]),
        obligation: obligation,
        loan: loan,
      ),
    ),
  );
  return sent ?? false;
}

/// What is chosen at the top of the form: a kind of money in, or a withdrawal (savings out).
const String _withdrawal = 'withdrawal';

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({required this.api, required this.me, required this.paid, required this.owing, this.member, this.obligation, this.loan});

  final GroupsApi api;
  final GroupMe me;
  final GroupMember? member;
  final Map<String, double> paid;
  final List<GroupObligation> owing;
  final GroupObligation? obligation;

  /// Given when repaying a loan: the form is for that only.
  final GroupLoan? loan;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _ref = TextEditingController();
  final TextEditingController _note = TextEditingController();
  late String _kind = widget.loan != null ? 'loan_repayment' : (widget.obligation != null ? 'contribution' : 'joining_fee');
  late GroupObligation? _obligation = widget.obligation ?? widget.owing.where((final GroupObligation o) => o.owing).firstOrNull;
  late String _method = widget.me.paymentMethods.isEmpty ? 'mpesa' : widget.me.paymentMethods.first.method;
  bool _busy = false;
  String? _error;

  /// The methods the group authorises (all of them until it has chosen).
  List<String> get _methods => widget.me.paymentMethods.isEmpty ? paymentMethods : <String>[for (final GroupPayMethod m in widget.me.paymentMethods) m.method];

  /// An officer with the payout right, recording for a member whose savings are known, may record a savings withdrawal.
  bool get _mayWithdraw => widget.member != null && widget.me.can('record_payouts') && widget.paid.containsKey('savings');

  List<String> get _kinds => widget.loan != null
      ? const <String>['loan_repayment']
      : <String>[
        'joining_fee',
        'shares',
        'savings',
        if (widget.owing.any((final GroupObligation o) => o.owing)) 'contribution',
        if (_mayWithdraw) _withdrawal,
      ];

  /// What can still be paid in [kind] (null: no limit shown), from the group's amounts and what is verified so far.
  double? _limit(final String kind) {
    switch (kind) {
      case 'joining_fee':
        return (widget.me.joiningFee - (widget.paid['joining_fee'] ?? 0)).clamp(0, double.infinity).toDouble();
      case 'shares':
        return (widget.me.shareAmount - (widget.paid['shares'] ?? 0)).clamp(0, double.infinity).toDouble();
      case 'contribution':
        return _obligation?.remaining ?? 0;
      case _withdrawal:
        return widget.paid['savings'] ?? 0;
      case 'loan_repayment':
        return widget.loan?.outstanding ?? 0;
      default:
        return null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.obligation == null && widget.loan == null) {
      // Start where something is still owed: the joining fee, then the shares, then the oldest contribution.
      if ((_limit('joining_fee') ?? 0) <= 0) _kind = (_limit('shares') ?? 0) > 0 ? 'shares' : (_kinds.contains('contribution') ? 'contribution' : 'savings');
    }
    _fillAmount();
  }

  void _fillAmount() {
    final double? l = _kind == 'loan_repayment' ? (widget.loan?.nextAmount ?? widget.loan?.outstanding) : _limit(_kind);
    _amount.text = l != null && l > 0 && _kind != _withdrawal ? l.toStringAsFixed(0) : '';
  }

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _note.dispose();
    super.dispose();
  }

  String _kindLabel(final bool sw, final String k) => k == _withdrawal ? (sw ? 'Kutoa akiba' : 'Savings withdrawal') : categoryLabel(sw: sw, category: k);

  Future<void> _send() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final double? amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (amount == null || amount < 1) {
      setState(() => _error = sw ? 'Weka kiasi sahihi.' : 'Enter a valid amount.');
      return;
    }
    final double? limit = _limit(_kind);
    if ((_kind == 'contribution' || _kind == _withdrawal || _kind == 'loan_repayment') && limit != null && amount > limit + 0.001) {
      setState(() => _error = _kind == _withdrawal
          ? (sw ? 'Ni zaidi ya akiba iliyopo (${tsh(limit)}).' : 'More than the savings there are (${tsh(limit)}).')
          : (sw ? 'Ni zaidi ya kinachodaiwa (${tsh(limit)}).' : 'More than is owed (${tsh(limit)}).'));
      return;
    }
    if (_kind != _withdrawal && _method != 'cash' && _ref.text.trim().isEmpty) {
      setState(() => _error = sw ? 'Weka namba ya muamala (reference).' : 'Enter the transaction reference.');
      return;
    }
    final String who = widget.member == null ? '' : ' (${widget.member!.fullName})';
    final String what = _kind == 'contribution' && _obligation != null
        ? _obligation!.title
        : (_kind == 'loan_repayment' ? '${_kindLabel(sw, _kind)} ${widget.loan?.reference ?? ''}' : _kindLabel(sw, _kind));
    final bool ok = await groupConfirm(
      context,
      title: _kind == _withdrawal ? (sw ? 'Rekodi kutoa akiba?' : 'Record this withdrawal?') : (sw ? 'Tuma malipo?' : 'Send this payment?'),
      message: '$what$who: ${tsh(amount)} · ${methodLabel(sw: sw, method: _method)}.\n'
          '${sw ? 'Yatahesabiwa baada ya mtu mwingine kuyathibitisha.' : 'It counts once someone else verifies it.'}',
      yes: _kind == _withdrawal ? (sw ? 'Rekodi' : 'Record') : (sw ? 'Tuma' : 'Send'),
      tone: _kind == _withdrawal ? GroupTone.danger : GroupTone.positive,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final Map<String, dynamic> body = <String, dynamic>{
      'category': _kind == _withdrawal ? 'savings' : _kind,
      if (_kind == _withdrawal) 'direction': 'out',
      if (_kind == 'contribution') 'obligation_id': _obligation?.id,
      if (_kind == 'loan_repayment') 'loan_id': widget.loan?.id,
      'amount': amount,
      'method': _method,
      if (_ref.text.trim().isNotEmpty) 'external_ref': _ref.text.trim(),
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      if (widget.member != null) 'member_id': widget.member!.id,
    };
    try {
      if (widget.member == null) {
        await widget.api.payMine(body);
      } else {
        await widget.api.recordPayment(body);
      }
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Imetumwa; inasubiri uthibitisho.' : 'Sent; it waits for verification.');
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = readableErrorMessage(e);
      });
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final String instructions = widget.me.paymentInstructions.trim();
    final double? limit = _limit(_kind);
    final List<GroupObligation> open = widget.owing.where((final GroupObligation o) => o.owing).toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              widget.member == null ? (sw ? 'Lipa' : 'Pay') : '${sw ? 'Rekodi malipo ya' : 'Record a payment for'} ${widget.member!.fullName}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const Divider(color: Colors.white12, height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final String k in _kinds)
                  ChoiceChip(
                    key: Key('grp_pay_cat_$k'),
                    label: Text(_kindLabel(sw, k)),
                    selected: _kind == k,
                    onSelected: (_) => setState(() {
                      _kind = k;
                      _error = null;
                      _fillAmount();
                    }),
                  ),
              ],
            ),
            if (_kind == 'contribution') ...<Widget>[
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                key: const Key('grp_pay_obligation'),
                initialValue: _obligation?.id,
                isExpanded: true,
                dropdownColor: ThemeConstants.bgMid,
                style: const TextStyle(color: Colors.white),
                decoration: ThemeConstants.darkField(sw ? 'Mchango unaolipwa' : 'Contribution being paid'),
                items: <DropdownMenuItem<int>>[
                  for (final GroupObligation o in open)
                    DropdownMenuItem<int>(value: o.id, child: Text('${o.title} · ${tsh(o.remaining)}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (final int? id) => setState(() {
                  _obligation = open.where((final GroupObligation o) => o.id == id).firstOrNull;
                  _fillAmount();
                }),
              ),
            ],
            if (limit != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                _kind == _withdrawal
                    ? '${sw ? 'Akiba iliyopo' : 'Savings there are'}: ${tsh(limit)}'
                    : _kind == 'loan_repayment'
                        ? '${sw ? 'Deni la mkopo' : 'Still owed on the loan'}: ${tsh(limit)}'
                        : '${sw ? 'Kinachobaki' : 'Still due'}: ${tsh(limit)}',
                key: const Key('grp_pay_limit'),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
            if (_kind == 'savings')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${sw ? 'Akiba yako sasa' : 'Savings now'}: ${tsh(widget.paid['savings'] ?? 0)}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('grp_pay_amount'),
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(sw ? 'Kiasi (TSH)' : 'Amount (TSH)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('grp_pay_method'),
              initialValue: _method,
              dropdownColor: ThemeConstants.bgMid,
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(_kind == _withdrawal ? (sw ? 'Amelipwa kwa' : 'Paid out by') : (sw ? 'Njia ya malipo' : 'Paid by')),
              items: <DropdownMenuItem<String>>[
                for (final String m in _methods) DropdownMenuItem<String>(value: m, child: Text(methodLabel(sw: sw, method: m))),
              ],
              onChanged: (final String? v) => setState(() => _method = v ?? 'cash'),
            ),
            if (_kind != _withdrawal && widget.me.paymentMethods.any((final GroupPayMethod m) => m.method == _method && m.number != null)) ...<Widget>[
              const SizedBox(height: 10),
              PayToCard(method: widget.me.paymentMethods.firstWhere((final GroupPayMethod m) => m.method == _method)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('grp_pay_all_numbers'),
                  onPressed: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => PaymentMethodsScreen(api: widget.api, me: widget.me))),
                  child: Text(sw ? 'Namba zote za kulipia' : 'All the numbers to pay to', style: const TextStyle(color: ThemeConstants.primaryOrange)),
                ),
              ),
            ],
            if (_method != 'cash') ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                key: const Key('grp_pay_ref'),
                controller: _ref,
                maxLength: 80,
                style: const TextStyle(color: Colors.white),
                decoration: ThemeConstants.darkField(sw ? 'Namba ya muamala (reference)' : 'Transaction reference'),
              ),
            ],
            const SizedBox(height: 4),
            TextField(
              controller: _note,
              maxLength: 255,
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(sw ? 'Maelezo (hiari)' : 'Note (optional)'),
            ),
            if (instructions.isNotEmpty && _kind != _withdrawal) ...<Widget>[
              const Divider(color: Colors.white12, height: 20),
              Text(sw ? 'Jinsi ya kulipa' : 'How to pay', style: const TextStyle(color: Color(0xFFFFD166), fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              SelectableText(instructions, key: const Key('grp_pay_instructions'), style: const TextStyle(color: Colors.white70)),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(_error!, key: const Key('grp_pay_error'), style: const TextStyle(color: ThemeConstants.errorText)),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('grp_pay_send'),
              style: FilledButton.styleFrom(
                backgroundColor: _kind == _withdrawal ? ThemeConstants.errorRed : ThemeConstants.successGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _busy ? null : _send,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
              label: Text(_kind == _withdrawal ? (sw ? 'Rekodi kutoa akiba' : 'Record the withdrawal') : (sw ? 'Tuma malipo' : 'Send payment')),
            ),
          ],
        ),
      ),
    );
  }
}

/// A group expense (hall hire, transport for a funeral, ...): who was paid, how much, how; recorded by whoever records payouts and verified
/// by someone else. Returns true when one was sent.
Future<bool> showExpenseForm(final BuildContext context, {required final GroupsApi api}) async {
  final bool? sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ThemeConstants.bgMid,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (final BuildContext c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: _ExpenseForm(api: api)),
  );
  return sent ?? false;
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({required this.api});

  final GroupsApi api;

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  final TextEditingController _payee = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _ref = TextEditingController();
  String _method = 'cash';
  List<String> _methods = paymentMethods;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final ({bool configured, bool canManage, List<GroupPayMethod> methods}) r = await widget.api.paymentMethods();
        if (mounted && r.methods.isNotEmpty) {
          setState(() {
            _methods = <String>[for (final GroupPayMethod m in r.methods) m.method];
            _method = _methods.first;
          });
        }
      } on Exception {
        // the form still works with every method
      }
    });
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_payee, _amount, _note, _ref]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final double? amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (_payee.text.trim().length < 2) {
      setState(() => _error = sw ? 'Andika aliyelipwa.' : 'Write who was paid.');
      return;
    }
    if (amount == null || amount < 1) {
      setState(() => _error = sw ? 'Weka kiasi sahihi.' : 'Enter a valid amount.');
      return;
    }
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Rekodi matumizi?' : 'Record this expense?',
      message: '${_payee.text.trim()}: ${tsh(amount)}${_note.text.trim().isEmpty ? '' : ' · ${_note.text.trim()}'}.\n'
          '${sw ? 'Yatahesabiwa baada ya mtu mwingine kuyathibitisha.' : 'It counts once someone else verifies it.'}',
      yes: sw ? 'Rekodi' : 'Record',
      tone: GroupTone.danger,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.recordPayment(<String, dynamic>{
        'category': 'expense',
        'payee': _payee.text.trim(),
        'amount': amount,
        'method': _method,
        if (_ref.text.trim().isNotEmpty) 'external_ref': _ref.text.trim(),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Matumizi yamerekodiwa; yanasubiri uthibitisho.' : 'Expense recorded; it waits for verification.');
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = readableErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(sw ? 'Matumizi ya kikundi' : 'Group expense', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            const Divider(color: Colors.white12, height: 24),
            TextField(key: const Key('grp_exp_payee'), controller: _payee, maxLength: 150, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Aliyelipwa' : 'Paid to')),
            TextField(
              key: const Key('grp_exp_amount'),
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(sw ? 'Kiasi (TSH)' : 'Amount (TSH)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              dropdownColor: ThemeConstants.bgMid,
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(sw ? 'Amelipwa kwa' : 'Paid out by'),
              items: <DropdownMenuItem<String>>[for (final String m in _methods) DropdownMenuItem<String>(value: m, child: Text(methodLabel(sw: sw, method: m)))],
              onChanged: (final String? v) => setState(() => _method = v ?? 'cash'),
            ),
            if (_method != 'cash') ...<Widget>[
              const SizedBox(height: 12),
              TextField(controller: _ref, maxLength: 80, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Namba ya muamala (hiari)' : 'Reference (optional)')),
            ],
            const SizedBox(height: 4),
            TextField(controller: _note, maxLength: 255, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Ni kwa ajili ya nini' : 'What it was for')),
            if (_error != null) Text(_error!, key: const Key('grp_exp_error'), style: const TextStyle(color: ThemeConstants.errorText)),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('grp_exp_send'),
              style: FilledButton.styleFrom(backgroundColor: ThemeConstants.errorRed, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _busy ? null : _send,
              icon: const Icon(Icons.receipt_long_rounded),
              label: Text(sw ? 'Rekodi matumizi' : 'Record the expense'),
            ),
          ],
        ),
      ),
    );
  }
}
