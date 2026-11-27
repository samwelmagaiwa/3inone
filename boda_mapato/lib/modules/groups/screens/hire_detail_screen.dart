import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_asset_models.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'widgets/amount_dialogs.dart';
import 'widgets/groups_ui.dart';

/// One hire: who, what, when, the money, and the next step. The keeper (or whoever manages assets) confirms, hands over, takes back and
/// closes; whoever decides hire charges sets a damage charge; the hirer pays or withdraws. Never one's own hire for the first two.
class HireDetailScreen extends StatefulWidget {
  const HireDetailScreen({required this.api, required this.me, required this.hire, super.key});

  final GroupsApi api;
  final GroupMe me;
  final GroupHire hire;

  @override
  State<HireDetailScreen> createState() => _HireDetailScreenState();
}

class _HireDetailScreenState extends State<HireDetailScreen> {
  late GroupHire _h = widget.hire;

  bool get _sw => context.read<LocalizationService>().isSwahili;

  bool get _mine => widget.me.member != null && widget.me.member!.id == _h.memberId;

  bool get _handles => !_mine && (widget.me.can('manage_assets') || widget.me.keepsAssets);

  Future<void> _run(final Future<GroupHire> Function() action, final String done) async {
    try {
      final GroupHire h = await action();
      if (!mounted) return;
      setState(() => _h = h);
      ThemeConstants.showSuccessSnackBar(context, done);
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _decide({required final bool approve}) async {
    final bool sw = _sw;
    if (approve) {
      final bool ok = await groupConfirm(
        context,
        title: sw ? 'Kubali ukodishaji?' : 'Confirm this hire?',
        message: '${_h.quantity} × ${_h.assetName ?? ''} · ${dateLabel(_h.startDate)} – ${dateLabel(_h.endDate)} · ${tsh(_h.amount)}.\n'
            '${sw ? 'Hakikisha vipo kweli kwa siku hizo.' : 'Make sure they really are there on those days.'}',
        yes: sw ? 'Kubali' : 'Confirm',
        tone: GroupTone.positive,
      );
      if (ok) await _run(() => widget.api.decideHire(_h.id, approve: true), sw ? 'Imekubaliwa.' : 'Confirmed.');
      return;
    }
    final String? note = await groupReason(context, title: sw ? 'Kataa ukodishaji' : 'Decline the hire', message: _h.who, yes: sw ? 'Kataa' : 'Decline');
    if (note != null) await _run(() => widget.api.decideHire(_h.id, approve: false, note: note), sw ? 'Imekataliwa.' : 'Declined.');
  }

  Future<void> _pay() async {
    final bool sw = _sw;
    final (double, String)? amount = await showDialog<(double, String)>(
      context: context,
      builder: (_) => AmountNoteDialog(title: sw ? 'Kiasi kinacholipwa' : 'Amount paid', amount: _h.balance, max: _h.balance),
    );
    if (amount == null || !mounted) return;
    final (String, String)? how = await showDialog<(String, String)>(context: context, builder: (_) => const PayOutDialog());
    if (how == null || !mounted) return;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Tuma malipo?' : 'Send this payment?',
      message: '${_h.reference}: ${tsh(amount.$1)} · ${methodLabel(sw: sw, method: how.$1)}.\n${sw ? 'Yatahesabiwa baada ya kuthibitishwa.' : 'It counts once it is verified.'}',
      yes: sw ? 'Tuma' : 'Send',
      tone: GroupTone.positive,
    );
    if (!ok) return;
    if (_mine) {
      try {
        await widget.api.payMine(<String, dynamic>{'category': 'hire', 'hire_id': _h.id, 'amount': amount.$1, 'method': how.$1, if (how.$2.isNotEmpty) 'external_ref': how.$2});
        if (!mounted) return;
        ThemeConstants.showSuccessSnackBar(context, sw ? 'Malipo yametumwa; yanasubiri uthibitisho.' : 'Payment sent; it waits for verification.');
      } on Exception catch (e) {
        if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
      }
      return;
    }
    await _run(() => widget.api.payHire(_h.id, amount: amount.$1, method: how.$1, reference: how.$2), sw ? 'Malipo yamerekodiwa; yanasubiri uthibitisho.' : 'Payment recorded; it waits for verification.');
  }

  Future<void> _issue() async {
    final bool sw = _sw;
    final (double, String)? got = await showDialog<(double, String)>(
      context: context,
      builder: (_) => AmountNoteDialog(title: sw ? 'Vimetolewa vingapi' : 'How many handed over', amount: _h.quantity.toDouble(), max: _h.quantity.toDouble(), noteLabel: sw ? 'Hali yake (hiari)' : 'Their condition (optional)'),
    );
    if (got == null || !mounted) return;
    final bool ok = await groupConfirm(context, title: sw ? 'Toa vitu?' : 'Hand them over?', message: '${got.$1.toStringAsFixed(0)} × ${_h.assetName ?? ''} → ${_h.who ?? ''}', yes: sw ? 'Toa' : 'Hand over', tone: GroupTone.positive);
    if (ok) await _run(() => widget.api.issueHire(_h.id, quantity: got.$1.round(), condition: got.$2), sw ? 'Vimetolewa.' : 'Handed over.');
  }

  Future<void> _return() async {
    final bool sw = _sw;
    final (int, int, int, String)? got = await showDialog<(int, int, int, String)>(context: context, builder: (_) => _ReturnDialog(issued: _h.issuedQuantity ?? _h.quantity));
    if (got == null || !mounted) return;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Pokea vitu?' : 'Take them back?',
      message: '${sw ? 'Vimerudi' : 'Back'} ${got.$1} · ${sw ? 'vibovu' : 'damaged'} ${got.$2} · ${sw ? 'vimepotea' : 'missing'} ${got.$3}.\n'
          '${got.$2 + got.$3 > 0 ? (sw ? 'Vibovu na vilivyopotea vinaondolewa kwenye idadi; gharama itaamuliwa na Mwenyekiti.' : 'Damaged and missing leave the count; the chair decides any charge.') : ''}',
      yes: sw ? 'Pokea' : 'Take back',
      tone: got.$2 + got.$3 > 0 ? GroupTone.danger : GroupTone.positive,
    );
    if (ok) await _run(() => widget.api.returnHire(_h.id, returned: got.$1, damaged: got.$2, missing: got.$3, note: got.$4), sw ? 'Vimepokelewa.' : 'Taken back.');
  }

  Future<void> _charge() async {
    final bool sw = _sw;
    final (double, String)? got = await showDialog<(double, String)>(
      context: context,
      builder: (_) => AmountNoteDialog(title: sw ? 'Gharama ya uharibifu' : 'Damage charge', amount: 0, max: 100000000, noteLabel: sw ? 'Sababu' : 'Reason', noteRequired: true, allowZero: true),
    );
    if (got == null || !mounted) return;
    final bool ok = await groupConfirm(context, title: sw ? 'Weka gharama?' : 'Set the charge?', message: '${_h.who ?? ''}: ${tsh(got.$1)} · ${got.$2}', yes: sw ? 'Weka' : 'Set it', tone: GroupTone.danger);
    if (ok) await _run(() => widget.api.chargeHire(_h.id, amount: got.$1, note: got.$2), sw ? 'Gharama imewekwa.' : 'Charge set.');
  }

  Future<void> _close() async {
    final bool sw = _sw;
    final bool ok = await groupConfirm(context, title: sw ? 'Funga ukodishaji?' : 'Close the hire?', message: _h.reference, yes: sw ? 'Funga' : 'Close', tone: GroupTone.positive);
    if (ok) await _run(() => widget.api.closeHire(_h.id), sw ? 'Imefungwa.' : 'Closed.');
  }

  Future<void> _cancel() async {
    final bool sw = _sw;
    final bool ok = await groupConfirm(context, title: sw ? 'Ondoa ombi?' : 'Withdraw the request?', message: _h.reference, yes: sw ? 'Ondoa' : 'Withdraw', tone: GroupTone.danger);
    if (ok) await _run(() => widget.api.cancelHire(_h.id), sw ? 'Imeondolewa.' : 'Withdrawn.');
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupHire h = _h;
    Widget button(final String key, final String label, final IconData icon, final Color color, final VoidCallback onTap, {final bool outlined = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: outlined
              ? OutlinedButton.icon(
                  key: Key(key),
                  style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color), padding: const EdgeInsets.symmetric(vertical: 13)),
                  onPressed: onTap,
                  icon: Icon(icon),
                  label: Text(label),
                )
              : FilledButton.icon(
                  key: Key(key),
                  style: FilledButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(vertical: 13)),
                  onPressed: onTap,
                  icon: Icon(icon),
                  label: Text(label),
                ),
        );
    final bool open = const <String>['approved', 'issued', 'returned'].contains(h.status);
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(h.reference, flat: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: joinGlowCards(<Widget>[
            GlowCard(children: <Widget>[
              Row(children: <Widget>[
                Expanded(child: Text('${h.quantity} × ${h.assetName ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800))),
                GroupPill(hireStateLabel(sw: sw, state: h.state), color: hireStateColor(h.state)),
              ]),
              GroupDetailRow(sw ? 'Anayekodi' : 'Hired by', '${h.who ?? ''}${h.phone == null ? '' : ' · ${h.phone}'}'),
              GroupDetailRow(sw ? 'Siku' : 'Dates', '${dateLabel(h.startDate)} – ${dateLabel(h.endDate)} (${h.days} ${sw ? 'siku' : 'day(s)'})'),
              if (h.purpose != null) GroupDetailRow(sw ? 'Kwa ajili ya' : 'For', h.purpose!),
              if (h.decisionNote != null) GroupDetailRow(sw ? 'Maoni' : 'Note', h.decisionNote!),
            ]),
            GlowCard(title: sw ? 'Fedha' : 'Money', children: <Widget>[
              GroupDetailRow(sw ? 'Gharama' : 'Charge', '${h.quantity} × ${tsh(h.rate)} × ${h.days} = ${tsh(h.amount)}'),
              if (h.lateNights > 0)
                GroupDetailRow(
                  sw ? 'Usiku uliopita siku ya kurudisha' : 'Nights past the return day',
                  '${h.lateNights} · ${tsh(h.status == 'issued' ? h.lateChargeNow : h.lateCharge)}',
                  valueColor: ThemeConstants.errorText,
                )
              else if (h.lateCharge > 0)
                GroupDetailRow(sw ? 'Kuchelewa' : 'Late', tsh(h.lateCharge), valueColor: ThemeConstants.errorText),
              if (h.damageCharge > 0 || h.damageNote != null) GroupDetailRow(sw ? 'Uharibifu' : 'Damage', '${tsh(h.damageCharge)}${h.damageNote == null ? '' : ' · ${h.damageNote}'}', valueColor: ThemeConstants.errorText),
              GroupDetailRow(sw ? 'Imelipwa' : 'Paid', tsh(h.paid), valueColor: ThemeConstants.successGreen),
              GroupDetailRow(sw ? 'Inadaiwa' : 'Owed', tsh(h.balance), valueColor: h.balance > 0 ? ThemeConstants.warningAmber : ThemeConstants.successGreen),
            ]),
            if (h.issuedQuantity != null || h.returnedQuantity != null)
              GlowCard(title: sw ? 'Kutoa na kurudisha' : 'Out and back', children: <Widget>[
                if (h.issuedQuantity != null) GroupDetailRow(sw ? 'Vilivyotolewa' : 'Handed over', '${h.issuedQuantity}${h.issuedCondition == null ? '' : ' · ${h.issuedCondition}'}'),
                if (h.returnedQuantity != null) GroupDetailRow(sw ? 'Vilivyorudi' : 'Back', '${h.returnedQuantity} · ${dateLabel(h.returnedOn)}'),
                if ((h.damagedQuantity ?? 0) > 0) GroupDetailRow(sw ? 'Vibovu' : 'Damaged', '${h.damagedQuantity}', valueColor: ThemeConstants.errorText),
                if ((h.missingQuantity ?? 0) > 0) GroupDetailRow(sw ? 'Vimepotea' : 'Missing', '${h.missingQuantity}', valueColor: ThemeConstants.errorText),
                if (h.returnNote != null) GroupDetailRow(sw ? 'Maelezo' : 'Note', h.returnNote!),
              ]),
            const SizedBox(height: 12),
            if (_handles && h.status == 'requested') ...<Widget>[
              button('grp_hire_approve', sw ? 'Kubali' : 'Confirm', Icons.check_circle_rounded, ThemeConstants.successGreen, () => _decide(approve: true)),
              button('grp_hire_decline', sw ? 'Kataa' : 'Decline', Icons.block_rounded, ThemeConstants.errorRed, () => _decide(approve: false), outlined: true),
            ],
            if (open && h.balance > 0 && (_mine || _handles)) button('grp_hire_pay', sw ? 'Lipa' : 'Pay', Icons.payments_rounded, ThemeConstants.primaryOrange, _pay),
            if (_handles && h.status == 'approved' && h.state == 'confirmed') button('grp_hire_issue', sw ? 'Toa vitu' : 'Hand over', Icons.outbox_rounded, ThemeConstants.successGreen, _issue),
            if (_handles && h.status == 'issued') button('grp_hire_return', sw ? 'Pokea vitu' : 'Take back', Icons.move_to_inbox_rounded, ThemeConstants.invAccent, _return),
            if (!_mine && widget.me.can('decide_hire_charges') && h.state == 'damage_pending')
              button('grp_hire_charge', sw ? 'Amua gharama ya uharibifu' : 'Decide the damage charge', Icons.gavel_rounded, ThemeConstants.errorRed, _charge),
            if (_handles && h.state == 'settled') button('grp_hire_close', sw ? 'Funga' : 'Close', Icons.task_alt_rounded, ThemeConstants.successGreen, _close),
            if (_mine && (h.status == 'requested' || (h.status == 'approved' && h.paid == 0)))
              button('grp_hire_cancel', sw ? 'Ondoa ombi' : 'Withdraw', Icons.close_rounded, ThemeConstants.errorRed, _cancel, outlined: true),
          ]),
        ),
      ),
    );
  }
}

/// How many came back, damaged and missing. Back + missing must be what was handed over.
class _ReturnDialog extends StatefulWidget {
  const _ReturnDialog({required this.issued});

  final int issued;

  @override
  State<_ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<_ReturnDialog> {
  late final TextEditingController _back = TextEditingController(text: '${widget.issued}');
  final TextEditingController _damaged = TextEditingController(text: '0');
  final TextEditingController _missing = TextEditingController(text: '0');
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_back, _damaged, _missing, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  int _n(final TextEditingController c) => int.tryParse(c.text.trim()) ?? -1;

  bool get _ready => _n(_back) >= 0 && _n(_damaged) >= 0 && _n(_missing) >= 0 && _n(_back) + _n(_missing) == widget.issued && _n(_damaged) <= _n(_back);

  Widget _count(final TextEditingController c, final String label, final Key key) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: key,
          controller: c,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white),
          decoration: ThemeConstants.darkField(label),
        ),
      );

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      key: const Key('grp_return_dialog'),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('${sw ? 'Vilitolewa' : 'Handed over'}: ${widget.issued}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          // As wide as the screen allows, not as narrow as the fields' hints.
          const SizedBox(width: double.maxFinite),
          _count(
              _back,
              sw
                  ? 'Vimerudi (pamoja na vibovu)'
                  : 'Came back (damaged included)',
              const Key('grp_return_back')),
          _count(_damaged, sw ? 'Kati ya hivyo, vibovu' : 'Of those, damaged',
              const Key('grp_return_damaged')),
          _count(_missing, sw ? 'Havijarudi' : 'Did not come back',
              const Key('grp_return_missing')),
          TextField(
              controller: _note,
              maxLength: 255,
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(
                  sw ? 'Maelezo (hiari)' : 'Note (optional)')),
          if (!_ready)
            Text(
                sw
                    ? 'Vilivyorudi + vilivyopotea = ${widget.issued}'
                    : 'Back + missing = ${widget.issued}',
                style: const TextStyle(
                    color: ThemeConstants.warningAmber, fontSize: 12)),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white60))),
        TextButton(
          key: const Key('grp_return_next'),
          onPressed: _ready ? () => Navigator.pop(context, (_n(_back), _n(_damaged), _n(_missing), _note.text.trim())) : null,
          child: Text(sw ? 'Endelea' : 'Next', style: TextStyle(color: _ready ? ThemeConstants.successGreen : Colors.white24, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

/// A line for a hire in a list.
class HireTile extends StatelessWidget {
  const HireTile({required this.h, required this.sw, super.key, this.onTap});

  final GroupHire h;
  final bool sw;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) => ListTile(
        key: Key('grp_hire_${h.id}'),
        onTap: onTap,
        title: Text('${h.quantity} × ${h.assetName ?? ''} · ${h.who ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${dateLabel(h.startDate)} – ${dateLabel(h.endDate)} · ${tsh(h.total)}${h.balance > 0 ? ' · ${sw ? 'deni' : 'owed'} ${tsh(h.balance)}' : ''}',
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: GroupPill(hireStateLabel(sw: sw, state: h.state), color: hireStateColor(h.state)),
      );
}
