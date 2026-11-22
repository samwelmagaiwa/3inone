import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_loan_models.dart';
import '../models/group_models.dart';
import '../services/group_documents.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'payment_form.dart';
import 'widgets/amount_dialogs.dart';
import 'widgets/groups_ui.dart';
import 'widgets/member_picker.dart';

/// One loan: amounts and terms, guarantors, the committee's recommendation, the instalments (or what they would be), and the next step --
/// each step offered only to the person whose job it is, never to the borrower for their own loan, and each asked Yes / No first.
class LoanDetailScreen extends StatefulWidget {
  const LoanDetailScreen({required this.api, required this.me, required this.loanId, super.key});

  final GroupsApi api;
  final GroupMe me;
  final int loanId;

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  GroupLoan? _loan;
  String? _error;

  bool get _sw => context.read<LocalizationService>().isSwahili;

  bool get _mine => widget.me.member?.id == _loan?.memberId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final GroupLoan l = await widget.api.loan(widget.loanId);
      if (mounted) {
        setState(() {
          _loan = l;
          _error = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  /// The loan's statement and repayment schedule as a PDF, to share.
  Future<void> _share(final GroupLoan l) async {
    final bool sw = _sw;
    try {
      final GroupMe me = await widget.api.me();
      await GroupDocuments.share(await GroupDocuments.loanStatement(l, sw: sw, group: me.groupName ?? ''), '${l.reference}.pdf');
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _run(final Future<Object?> Function() action, final String done) async {
    try {
      await action();
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, done);
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _recommend(final GroupLoan l) async {
    final bool sw = _sw;
    final (double, String)? got = await showDialog<(double, String)>(
      context: context,
      builder: (_) => AmountNoteDialog(
        title: sw ? 'Pendekeza mkopo' : 'Recommend the loan',
        amount: l.amountRequested,
        max: l.ceiling == null ? l.amountRequested : (l.ceiling! < l.amountRequested ? l.ceiling! : l.amountRequested),
        noteLabel: sw ? 'Maoni ya kamati' : "The committee's view",
        noteRequired: true,
      ),
    );
    if (got == null || !mounted) return;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Tuma pendekezo?' : 'Send the recommendation?',
      message: '${l.memberName ?? ''}: ${tsh(got.$1)} · ${got.$2}',
      yes: sw ? 'Pendekeza' : 'Recommend',
      tone: GroupTone.positive,
    );
    if (ok) await _run(() => widget.api.recommendLoan(l.id, amount: got.$1, note: got.$2), sw ? 'Pendekezo limetumwa.' : 'Recommendation sent.');
  }

  Future<void> _approve(final GroupLoan l) async {
    final bool sw = _sw;
    final (double, String)? got = await showDialog<(double, String)>(
      context: context,
      builder: (_) => AmountNoteDialog(title: sw ? 'Idhinisha mkopo' : 'Approve the loan', amount: l.amountApproved ?? l.amountRequested, max: l.amountApproved ?? l.amountRequested),
    );
    if (got == null || !mounted) return;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Idhinisha mkopo?' : 'Approve this loan?',
      message: '${l.memberName ?? ''}: ${tsh(got.$1)} · ${l.termMonths} ${sw ? 'miezi' : 'month(s)'} · ${l.interestRate}% ${sw ? 'kwa mwezi' : 'a month'}.',
      yes: sw ? 'Idhinisha' : 'Approve',
      tone: GroupTone.positive,
    );
    if (ok) await _run(() => widget.api.approveLoan(l.id, amount: got.$1), sw ? 'Mkopo umeidhinishwa.' : 'Loan approved.');
  }

  Future<void> _reject(final GroupLoan l) async {
    final bool sw = _sw;
    final String? reason = await groupReason(context, title: sw ? 'Kataa mkopo' : 'Turn the loan down', message: '${l.memberName ?? ''} · ${tsh(l.amountRequested)}', yes: sw ? 'Kataa' : 'Turn down');
    if (reason != null) await _run(() => widget.api.rejectLoan(l.id, reason), sw ? 'Mkopo umekataliwa.' : 'Loan turned down.');
  }

  Future<void> _disburse(final GroupLoan l) async {
    final bool sw = _sw;
    final (String, String)? how = await showDialog<(String, String)>(context: context, builder: (_) => const PayOutDialog());
    if (how == null || !mounted) return;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Toa mkopo?' : 'Pay the loan out?',
      message: '${l.memberName ?? ''}: ${tsh(l.amountApproved ?? 0)} · ${methodLabel(sw: sw, method: how.$1)}.\n'
          '${sw ? 'Mkopo utaanza baada ya mtu mwingine kuthibitisha malipo haya.' : 'The loan starts once someone else verifies this payment.'}',
      yes: sw ? 'Toa' : 'Pay out',
      tone: GroupTone.danger,
    );
    if (ok) await _run(() => widget.api.disburseLoan(l.id, method: how.$1, reference: how.$2), sw ? 'Imerekodiwa; inasubiri uthibitisho.' : 'Recorded; waiting for verification.');
  }

  Future<void> _cancel(final GroupLoan l) async {
    final bool sw = _sw;
    final bool ok = await groupConfirm(context, title: sw ? 'Ondoa ombi la mkopo?' : 'Withdraw the application?', message: '${l.reference} · ${tsh(l.amountRequested)}', yes: sw ? 'Ondoa' : 'Withdraw', tone: GroupTone.danger);
    if (ok) await _run(() => widget.api.cancelLoan(l.id), sw ? 'Ombi limeondolewa.' : 'Application withdrawn.');
  }

  Future<void> _addGuarantor(final GroupLoan l) async {
    final bool sw = _sw;
    final GroupMember? g = await pickGroupMember(context, api: widget.api, exceptId: l.memberId);
    if (g == null || !mounted) return;
    final bool ok = await groupConfirm(context, title: sw ? 'Ongeza mdhamini?' : 'Add a guarantor?', message: g.fullName, yes: sw ? 'Ongeza' : 'Add', tone: GroupTone.positive);
    if (ok) await _run(() => widget.api.addGuarantor(l.id, g.id), sw ? 'Ombi limetumwa kwa mdhamini.' : 'Asked the guarantor.');
  }

  Future<void> _repay(final GroupLoan l) async {
    if (await showPaymentForm(context, api: widget.api, me: widget.me, loan: l)) await _load();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupLoan? l = _loan;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(
        l?.reference ?? (sw ? 'Mkopo' : 'Loan'),
        flat: true,
        actions: <Widget>[
          if (l != null && l.instalments.isNotEmpty && l.previewTotal == null)
            IconButton(key: const Key('grp_loan_pdf'), tooltip: sw ? 'Taarifa ya mkopo (PDF)' : 'Loan statement (PDF)', icon: const Icon(Icons.picture_as_pdf_rounded), onPressed: () => _share(l)),
        ],
      ),
      body: SafeArea(
        child: l == null
            ? Center(child: _error == null ? const CircularProgressIndicator() : GroupEmpty(_error!))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: <Widget>[
                    GlowCard(children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(child: Text(l.memberName ?? '', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
                        GroupPill(loanStateLabel(sw: sw, state: l.state), color: loanStateColor(l.state)),
                      ]),
                      GroupDetailRow(sw ? 'Kiasi kilichoombwa' : 'Asked for', tsh(l.amountRequested)),
                      if (l.amountApproved != null) GroupDetailRow(sw ? 'Kiasi kilichokubaliwa' : 'Agreed amount', tsh(l.amountApproved!), valueColor: ThemeConstants.successGreen),
                      GroupDetailRow(sw ? 'Muda' : 'Term', '${l.termMonths} ${sw ? 'miezi' : 'month(s)'}'),
                      GroupDetailRow(sw ? 'Riba' : 'Interest', '${l.interestRate}% ${sw ? 'kwa mwezi' : 'a month'} · ${interestMethodLabel(sw: sw, method: l.interestMethod)}'),
                      GroupDetailRow(sw ? 'Matumizi ya mkopo' : 'Purpose', l.purpose),
                      if (l.ceiling != null) GroupDetailRow(sw ? 'Kikomo alipoomba' : 'Ceiling when applied', tsh(l.ceiling!)),
                      if (l.recommendation != null) GroupDetailRow(sw ? 'Pendekezo la kamati' : "Committee's note", l.recommendation!),
                      if (l.rejectReason != null) GroupDetailRow(sw ? 'Sababu ya kukataliwa' : 'Why turned down', l.rejectReason!, valueColor: ThemeConstants.errorText),
                    ]),
                    if (l.status == 'active')
                      GlowCard(title: sw ? 'Hali ya mkopo' : 'Where it stands', children: <Widget>[
                        GroupDetailRow(sw ? 'Deni lililobaki' : 'Still owed', tsh(l.outstanding ?? 0), valueColor: (l.outstanding ?? 0) > 0 ? ThemeConstants.warningAmber : ThemeConstants.successGreen),
                        GroupDetailRow(sw ? 'Msingi uliolipwa' : 'Principal repaid', tsh(l.principalPaid)),
                        GroupDetailRow(sw ? 'Riba iliyolipwa' : 'Interest paid', tsh(l.interestPaid)),
                        GroupDetailRow(sw ? 'Msingi uliobaki' : 'Principal left', tsh(l.outstandingPrincipal)),
                        GroupDetailRow(sw ? 'Riba iliyobaki' : 'Interest left', tsh(l.outstandingInterest)),
                        if ((l.arrears ?? 0) > 0) GroupDetailRow(sw ? 'Imepita muda' : 'Overdue', tsh(l.arrears!), valueColor: ThemeConstants.errorText),
                        if (l.nextDue != null) GroupDetailRow(sw ? 'Rejesho lijalo' : 'Next instalment', '${tsh(l.nextAmount ?? 0)} · ${dateLabel(l.nextDue)}'),
                      ]),
                    if (l.previewTotal != null)
                      GlowCard(title: sw ? 'Itakavyolipwa' : 'How it would be repaid', children: <Widget>[
                        GroupDetailRow(sw ? 'Riba yote' : 'Total interest', tsh(l.previewInterest ?? 0)),
                        GroupDetailRow(sw ? 'Jumla ya kulipa' : 'Total to repay', tsh(l.previewTotal!)),
                        GroupDetailRow(sw ? 'Kila mwezi (takriban)' : 'Each month (about)', tsh(l.instalments.isEmpty ? 0 : l.instalments.first.total)),
                      ]),
                    if (l.guarantors.isNotEmpty)
                      GlowCard(title: sw ? 'Wadhamini' : 'Guarantors', children: <Widget>[
                        for (final GroupGuarantor g in l.guarantors)
                          Row(children: <Widget>[
                            Expanded(child: Text(g.name, style: const TextStyle(color: Colors.white))),
                            GroupPill(guarantorStatusLabel(sw: sw, status: g.status), color: guarantorStatusColor(g.status)),
                          ]),
                      ]),
                    if (l.instalments.isNotEmpty && l.status == 'active')
                      GlowListCard(
                        dividerKey: 'grp_inst_div',
                        children: <Widget>[
                          for (final GroupInstalment i in l.instalments)
                            Row(children: <Widget>[
                              SizedBox(width: 28, child: Text('${i.number}', style: const TextStyle(color: Colors.white54))),
                              Expanded(
                                child: Text('${dateLabel(i.dueDate)} · ${tsh(i.total)}', style: const TextStyle(color: Colors.white)),
                              ),
                              GroupPill(obligationStateLabel(sw: sw, state: i.state ?? 'due'), color: obligationStateColor(i.state ?? 'due')),
                            ]),
                        ],
                      ),
                    const SizedBox(height: 12),
                    ..._actions(l, sw),
                  ],
                ),
              ),
      ),
    );
  }

  /// The buttons for the next step, in the colours of what they do.
  List<Widget> _actions(final GroupLoan l, final bool sw) {
    final GroupMe me = widget.me;
    final List<Widget> out = <Widget>[];
    Widget button(final Key key, final String label, final IconData icon, final Color color, final VoidCallback onTap, {final bool outlined = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: outlined
              ? OutlinedButton.icon(
                  key: key,
                  style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color), padding: const EdgeInsets.symmetric(vertical: 13)),
                  onPressed: onTap,
                  icon: Icon(icon),
                  label: Text(label),
                )
              : FilledButton.icon(
                  key: key,
                  style: FilledButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 13)),
                  onPressed: onTap,
                  icon: Icon(icon),
                  label: Text(label),
                ),
        );
    if (!_mine) {
      if (l.status == 'under_review' && me.can('recommend_loans')) {
        out.add(button(const Key('grp_loan_recommend'), sw ? 'Pendekeza' : 'Recommend', Icons.thumb_up_alt_outlined, ThemeConstants.successGreen, () => _recommend(l)));
      }
      if (l.status == 'recommended' && me.can('approve_loans')) {
        out.add(button(const Key('grp_loan_approve'), sw ? 'Idhinisha' : 'Approve', Icons.verified_rounded, ThemeConstants.successGreen, () => _approve(l)));
      }
      if (l.status == 'approved' && me.can('record_payouts')) {
        out.add(button(const Key('grp_loan_disburse'), sw ? 'Toa mkopo' : 'Pay it out', Icons.payments_rounded, ThemeConstants.primaryOrange, () => _disburse(l)));
      }
      if (l.isOpen && (me.can('approve_loans') || me.can('recommend_loans'))) {
        out.add(button(const Key('grp_loan_reject'), sw ? 'Kataa' : 'Turn down', Icons.block_rounded, ThemeConstants.errorRed, () => _reject(l), outlined: true));
      }
    } else {
      if (l.isRunning) out.add(button(const Key('grp_loan_repay'), sw ? 'Rejesha' : 'Repay', Icons.payments_rounded, ThemeConstants.primaryOrange, () => _repay(l)));
      if (l.status == 'awaiting_guarantors' && l.guarantors.any((final GroupGuarantor g) => g.status == 'declined')) {
        out.add(button(const Key('grp_loan_add_guarantor'), sw ? 'Ongeza mdhamini' : 'Add a guarantor', Icons.person_add_alt_1_rounded, ThemeConstants.invAccent, () => _addGuarantor(l), outlined: true));
      }
      if (l.isOpen) out.add(button(const Key('grp_loan_cancel'), sw ? 'Ondoa ombi' : 'Withdraw', Icons.close_rounded, ThemeConstants.errorRed, () => _cancel(l), outlined: true));
    }
    return out;
  }
}
