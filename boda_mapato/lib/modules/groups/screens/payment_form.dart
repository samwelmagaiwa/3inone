import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'widgets/groups_ui.dart';

/// The form for a payment: a member paying for themself ([member] null), or an officer recording what a member paid ([member] given).
/// Either way it is sent as WAITING: it counts only after the treasurer verifies it. Returns true when one was sent.
Future<bool> showPaymentForm(
  final BuildContext context, {
  required final GroupsApi api,
  required final GroupMe me,
  final GroupMember? member,
  final Map<String, double>? paid,
}) async {
  final bool? sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ThemeConstants.bgMid,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (final BuildContext c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
      child: _PaymentForm(api: api, me: me, member: member, paid: paid ?? (member == null ? me.balances : null) ?? const <String, double>{}),
    ),
  );
  return sent ?? false;
}

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({required this.api, required this.me, required this.paid, this.member});

  final GroupsApi api;
  final GroupMe me;
  final GroupMember? member;
  final Map<String, double> paid;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _ref = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _category = 'joining_fee';
  String _method = 'mpesa';
  bool _busy = false;
  String? _error;

  /// What is still owed in [category], from the group's amount and what is verified so far (never below 0).
  double _remaining(final String category) {
    final double due = category == 'joining_fee' ? widget.me.joiningFee : widget.me.shareAmount;
    return (due - (widget.paid[category] ?? 0)).clamp(0, double.infinity).toDouble();
  }

  @override
  void initState() {
    super.initState();
    // Start where something is still owed.
    if (_remaining('joining_fee') <= 0 && _remaining('shares') > 0) _category = 'shares';
    _fillAmount();
  }

  void _fillAmount() {
    final double r = _remaining(_category);
    _amount.text = r > 0 ? r.toStringAsFixed(0) : '';
  }

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final double? amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (amount == null || amount < 1) {
      setState(() => _error = sw ? 'Weka kiasi sahihi.' : 'Enter a valid amount.');
      return;
    }
    if (_method != 'cash' && _ref.text.trim().isEmpty) {
      setState(() => _error = sw ? 'Weka namba ya muamala (reference).' : 'Enter the transaction reference.');
      return;
    }
    final String who = widget.member == null ? '' : ' (${widget.member!.fullName})';
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Tuma malipo?' : 'Send this payment?',
      message: '${categoryLabel(sw: sw, category: _category)}$who: ${tsh(amount)} · ${methodLabel(sw: sw, method: _method)}.\n'
          '${sw ? 'Yatahesabiwa baada ya Mweka Hazina kuyathibitisha.' : 'It counts once the treasurer verifies it.'}',
      yes: sw ? 'Tuma' : 'Send',
      tone: GroupTone.positive,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final Map<String, dynamic> body = <String, dynamic>{
      'category': _category,
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
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Malipo yametumwa; yanasubiri uthibitisho.' : 'Payment sent; it waits for verification.');
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
              children: <Widget>[
                for (final String c in const <String>['joining_fee', 'shares'])
                  ChoiceChip(
                    key: Key('grp_pay_cat_$c'),
                    label: Text(categoryLabel(sw: sw, category: c)),
                    selected: _category == c,
                    onSelected: (_) => setState(() {
                      _category = c;
                      _fillAmount();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${sw ? 'Kinachobaki' : 'Still due'}: ${tsh(_remaining(_category))}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
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
              decoration: ThemeConstants.darkField(sw ? 'Njia ya malipo' : 'Paid by'),
              items: <DropdownMenuItem<String>>[
                for (final String m in paymentMethods) DropdownMenuItem<String>(value: m, child: Text(methodLabel(sw: sw, method: m))),
              ],
              onChanged: (final String? v) => setState(() => _method = v ?? 'cash'),
            ),
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
            if (instructions.isNotEmpty) ...<Widget>[
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
              style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _busy ? null : _send,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
              label: Text(sw ? 'Tuma malipo' : 'Send payment'),
            ),
          ],
        ),
      ),
    );
  }
}
