import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_loan_models.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'loan_detail_screen.dart';
import 'widgets/groups_ui.dart';
import 'widgets/member_picker.dart';

/// The member's loans: whether they can borrow and up to how much (the sum shown, never only the answer), applying, their loans, and the
/// guarantees others asked of them (accept or decline).
class MyLoansScreen extends StatefulWidget {
  const MyLoansScreen({required this.api, required this.me, super.key});

  final GroupsApi api;
  final GroupMe me;

  @override
  State<MyLoansScreen> createState() => _MyLoansScreenState();
}

class _MyLoansScreenState extends State<MyLoansScreen> {
  GroupLoanEligibility? _eligibility;
  List<GroupLoan> _loans = const <GroupLoan>[];
  List<GroupGuarantee> _guarantees = const <GroupGuarantee>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final GroupLoanEligibility? e = await widget.api.myEligibility();
      final (List<GroupLoan>, List<GroupGuarantee>) mine = await widget.api.myLoans();
      if (!mounted) return;
      setState(() {
        _eligibility = e;
        _loans = mine.$1;
        _guarantees = mine.$2;
        _loading = false;
        _error = null;
      });
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = readableErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(final int loanId) async {
    await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => LoanDetailScreen(api: widget.api, me: widget.me, loanId: loanId)));
    await _load();
  }

  Future<void> _apply() async {
    final GroupLoanEligibility? e = _eligibility;
    if (e == null) return;
    final bool? sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.bgMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (final BuildContext c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: _ApplyForm(api: widget.api, eligibility: e, me: widget.me)),
    );
    if (sent ?? false) await _load();
  }

  Future<void> _answer(final GroupGuarantee g, {required final bool accept}) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final bool ok = await groupConfirm(
      context,
      title: accept ? (sw ? 'Kubali kuwa mdhamini?' : 'Agree to guarantee?') : (sw ? 'Kataa udhamini?' : 'Decline to guarantee?'),
      message: '${g.borrower}: ${tsh(g.amount)} · ${g.termMonths} ${sw ? 'miezi' : 'month(s)'} · ${g.purpose}.\n'
          '${accept ? (sw ? 'Ukikubali, utawajibika mkopaji akishindwa kulipa, kwa kanuni za kikundi.' : "If you agree, you answer for it if the borrower cannot pay, by the group's rules.") : ''}',
      yes: accept ? (sw ? 'Nakubali' : 'I agree') : (sw ? 'Nakataa' : 'Decline'),
      tone: accept ? GroupTone.positive : GroupTone.danger,
    );
    if (!ok) return;
    try {
      await widget.api.respondGuarantee(g.id, accept: accept);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Jibu limetumwa.' : 'Answer sent.');
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupLoanEligibility? e = _eligibility;
    final bool hasOpen = _loans.any((final GroupLoan l) => l.isOpen);
    final List<GroupGuarantee> waiting = _guarantees.where((final GroupGuarantee g) => g.waitsForMe).toList();
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Mikopo yangu' : 'My loans', flat: true),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: <Widget>[
                    if (_error != null) GroupEmpty(_error!),
                    if (waiting.isNotEmpty)
                      GlowCard(title: sw ? 'Umeombwa kudhamini' : 'Asked to guarantee', children: <Widget>[
                        for (final GroupGuarantee g in waiting)
                          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                            Text('${g.borrower} · ${tsh(g.amount)}', key: Key('grp_guarantee_${g.id}'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            Text('${g.purpose} · ${g.termMonths} ${sw ? 'miezi' : 'month(s)'}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                            const SizedBox(height: 6),
                            Row(children: <Widget>[
                              Expanded(
                                child: OutlinedButton(
                                  key: Key('grp_guarantee_decline_${g.id}'),
                                  style: OutlinedButton.styleFrom(foregroundColor: ThemeConstants.errorRed, side: const BorderSide(color: ThemeConstants.errorRed)),
                                  onPressed: () => _answer(g, accept: false),
                                  child: Text(sw ? 'Kataa' : 'Decline'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  key: Key('grp_guarantee_accept_${g.id}'),
                                  style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen),
                                  onPressed: () => _answer(g, accept: true),
                                  child: Text(sw ? 'Kubali' : 'Agree'),
                                ),
                              ),
                            ]),
                          ]),
                      ]),
                    if (e != null)
                      GlowCard(title: sw ? 'Unaweza kukopa kiasi gani' : 'How much you can borrow', children: <Widget>[
                        GroupDetailRow(sw ? 'Akiba yako' : 'Your savings', tsh(e.savings)),
                        GroupDetailRow(sw ? 'Mara' : 'Times', '× ${e.multiplier % 1 == 0 ? e.multiplier.toStringAsFixed(0) : e.multiplier}'),
                        if (e.otherLoans > 0) GroupDetailRow(sw ? 'Ukiondoa mikopo mingine' : 'Less other loans', '− ${tsh(e.otherLoans)}'),
                        GroupDetailRow(sw ? 'Kikomo' : 'Ceiling', tsh(e.ceiling), valueColor: ThemeConstants.invAccent),
                        if (e.sharesNeeded > 0) GroupDetailRow(sw ? 'Hisa' : 'Shares', '${tsh(e.sharesPaid)} / ${tsh(e.sharesNeeded)}', valueColor: e.sharesPaid + 0.001 >= e.sharesNeeded ? ThemeConstants.successGreen : ThemeConstants.warningAmber),
                        GroupDetailRow(
                          sw ? 'Masharti' : 'Terms',
                          e.rate == null || e.method == null
                              ? (sw ? 'Bado hayajawekwa' : 'Not set yet')
                              : '${e.rate}% ${sw ? 'kwa mwezi' : 'a month'} · ${interestMethodLabel(sw: sw, method: e.method!)} · ${sw ? 'hadi miezi' : 'up to'} ${e.maxMonths}${sw ? '' : ' months'}',
                        ),
                        for (final String r in e.reasons)
                          Row(children: <Widget>[
                            const Icon(Icons.info_outline, color: ThemeConstants.warningAmber, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(eligibilityReasonLabel(sw: sw, reason: r), key: Key('grp_reason_$r'), style: const TextStyle(color: Colors.white70))),
                          ]),
                        if (e.eligible && !hasOpen)
                          FilledButton.icon(
                            key: const Key('grp_loan_apply_open'),
                            style: FilledButton.styleFrom(backgroundColor: ThemeConstants.primaryOrange),
                            onPressed: _apply,
                            icon: const Icon(Icons.request_quote_rounded),
                            label: Text(sw ? 'Omba mkopo' : 'Apply for a loan'),
                          ),
                      ]),
                    if (_loans.isEmpty && _error == null) GroupEmpty(sw ? 'Bado huna mkopo.' : 'No loans yet.'),
                    if (_loans.isNotEmpty)
                      GlowListCard(
                        dividerKey: 'grp_myloans_div',
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        children: <Widget>[for (final GroupLoan l in _loans) LoanTile(loan: l, sw: sw, onTap: () => _open(l.id))],
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// A loan in a list.
class LoanTile extends StatelessWidget {
  const LoanTile({required this.loan, required this.sw, super.key, this.showMember = false, this.onTap});

  final GroupLoan loan;
  final bool sw;
  final bool showMember;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) => ListTile(
        key: Key('grp_loan_${loan.id}'),
        onTap: onTap,
        title: Text('${showMember ? '${loan.memberName ?? ''} · ' : ''}${tsh(loan.amountApproved ?? loan.amountRequested)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Text(
          <String>[
            loan.reference,
            '${loan.termMonths} ${sw ? 'miezi' : 'mo'}',
            if (loan.outstanding != null && loan.status == 'active') '${sw ? 'Deni' : 'Owed'} ${tsh(loan.outstanding!)}',
            if (loan.nextDue != null) '${sw ? 'Lijalo' : 'Next'} ${dateLabel(loan.nextDue)}',
          ].join(' · '),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: GroupPill(loanStateLabel(sw: sw, state: loan.state), color: loanStateColor(loan.state)),
      );
}

/// Apply: how much (never above the ceiling), what for, how long (never above the group's limit) and the guarantors.
class _ApplyForm extends StatefulWidget {
  const _ApplyForm({required this.api, required this.eligibility, required this.me});

  final GroupsApi api;
  final GroupLoanEligibility eligibility;
  final GroupMe me;

  @override
  State<_ApplyForm> createState() => _ApplyFormState();
}

class _ApplyFormState extends State<_ApplyForm> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _purpose = TextEditingController();
  late int _months = widget.eligibility.maxMonths < 6 ? widget.eligibility.maxMonths : 6;
  final List<GroupMember> _guarantors = <GroupMember>[];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _purpose.dispose();
    super.dispose();
  }

  Future<void> _addGuarantor() async {
    final GroupMember? g = await pickGroupMember(context, api: widget.api, exceptId: widget.me.member?.id);
    if (g != null && !_guarantors.any((final GroupMember x) => x.id == g.id)) setState(() => _guarantors.add(g));
  }

  Future<void> _send() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final GroupLoanEligibility e = widget.eligibility;
    final double? amount = double.tryParse(_amount.text.trim());
    String? problem;
    if (amount == null || amount < 1000) {
      problem = sw ? 'Weka kiasi (angalau 1,000).' : 'Enter an amount (at least 1,000).';
    } else if (amount > e.ceiling + 0.001) {
      problem = sw ? 'Ni zaidi ya kikomo chako (${tsh(e.ceiling)}).' : 'More than your ceiling (${tsh(e.ceiling)}).';
    } else if (_purpose.text.trim().length < 3) {
      problem = sw ? 'Andika matumizi ya mkopo.' : 'Write what the loan is for.';
    } else if (_guarantors.length < e.guarantors) {
      problem = sw ? 'Chagua wadhamini ${e.guarantors}.' : 'Choose ${e.guarantors} guarantor(s).';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Tuma ombi la mkopo?' : 'Send the loan application?',
      message: '${tsh(amount!)} · $_months ${sw ? 'miezi' : 'month(s)'} · ${e.rate}% ${sw ? 'kwa mwezi' : 'a month'} (${interestMethodLabel(sw: sw, method: e.method ?? '')}).\n'
          '${_guarantors.isEmpty ? '' : '${sw ? 'Wadhamini' : 'Guarantors'}: ${_guarantors.map((final GroupMember g) => g.fullName).join(', ')}.'}',
      yes: sw ? 'Tuma' : 'Send',
      tone: GroupTone.positive,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.applyLoan(<String, dynamic>{
        'amount': amount,
        'purpose': _purpose.text.trim(),
        'term_months': _months,
        'guarantor_ids': <int>[for (final GroupMember g in _guarantors) g.id],
      });
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Ombi limetumwa.' : 'Application sent.');
      Navigator.pop(context, true);
    } on Exception catch (err) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = readableErrorMessage(err);
        });
      }
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupLoanEligibility e = widget.eligibility;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(sw ? 'Ombi la mkopo' : 'Loan application', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const Divider(color: Colors.white12, height: 24),
          TextField(
            key: const Key('grp_apply_amount'),
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Kiasi' : 'Amount', helper: '${sw ? 'Hadi' : 'Up to'} ${tsh(e.ceiling)}'),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('grp_apply_purpose'),
            controller: _purpose,
            maxLength: 255,
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Ni kwa ajili ya nini' : 'What it is for'),
          ),
          Row(children: <Widget>[
            Text(sw ? 'Miezi' : 'Months', style: const TextStyle(color: Colors.white70)),
            Expanded(
              child: Slider(
                key: const Key('grp_apply_months'),
                value: _months.toDouble(),
                min: 1,
                max: e.maxMonths.toDouble(),
                divisions: e.maxMonths > 1 ? e.maxMonths - 1 : null,
                label: '$_months',
                onChanged: e.maxMonths > 1 ? (final double v) => setState(() => _months = v.round()) : null,
              ),
            ),
            Text('$_months', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
          if (e.guarantors > 0) ...<Widget>[
            Text('${sw ? 'Wadhamini' : 'Guarantors'} (${_guarantors.length}/${e.guarantors})', style: const TextStyle(color: Colors.white70)),
            Wrap(spacing: 8, children: <Widget>[
              for (final GroupMember g in _guarantors) InputChip(label: Text(g.fullName), onDeleted: () => setState(() => _guarantors.remove(g))),
              ActionChip(key: const Key('grp_apply_add_guarantor'), avatar: const Icon(Icons.add, size: 18), label: Text(sw ? 'Ongeza' : 'Add'), onPressed: _addGuarantor),
            ]),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const Key('grp_apply_error'), style: const TextStyle(color: ThemeConstants.errorText))),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const Key('grp_apply_send'),
            style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: Text(sw ? 'Tuma ombi' : 'Send the application'),
          ),
        ]),
      ),
    );
  }
}
