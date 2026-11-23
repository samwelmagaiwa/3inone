import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../models/group_loan_models.dart';
import '../services/group_documents.dart';
import '../services/groups_api.dart';
import 'group_dashboard_screen.dart';
import 'groups_text.dart';
import 'widgets/groups_ui.dart';

/// A member's statement: the balance of each kind of money, what is still owed, what waits for verification, promises, and every verified
/// movement with the balance after it. One's own ([memberId] null) or, for an officer, a member's.
class GroupStatementScreen extends StatefulWidget {
  const GroupStatementScreen({required this.api, super.key, this.memberId, this.memberName});

  final GroupsApi api;
  final int? memberId;
  final String? memberName;

  @override
  State<GroupStatementScreen> createState() => _GroupStatementScreenState();
}

class _GroupStatementScreenState extends State<GroupStatementScreen> {
  GroupStatementData? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final GroupStatementData? d = await widget.api.statement(memberId: widget.memberId);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
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

  /// Makes the statement as a PDF (with the loans still owed, for one's own) and opens the share sheet.
  Future<void> _share() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final GroupStatementData? d = _data;
    if (d == null) return;
    try {
      final GroupMe me = await widget.api.me();
      List<GroupLoan> loans = const <GroupLoan>[];
      if (widget.memberId == null) {
        loans = (await widget.api.myLoans()).$1;
      }
      final Uint8List bytes = await GroupDocuments.statement(d, sw: sw, group: me.groupName ?? '', memberName: widget.memberName ?? me.member?.fullName ?? '', loans: loans);
      await GroupDocuments.share(bytes, 'statement.pdf');
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupStatementData? d = _data;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(
        widget.memberName ?? (sw ? 'Taarifa yangu ya fedha' : 'My statement'),
        flat: true,
        actions: <Widget>[
          if (d != null)
            IconButton(key: const Key('grp_stmt_pdf'), tooltip: sw ? 'Shiriki (PDF)' : 'Share (PDF)', icon: const Icon(Icons.picture_as_pdf_rounded), onPressed: _share),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : d == null
                ? GroupEmpty(_error ?? (sw ? 'Hakuna taarifa.' : 'No statement.'))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: joinGlowCards(<Widget>[
                        GlowCard(
                          title: sw ? 'Salio' : 'Balances',
                          children: <Widget>[
                            for (final MapEntry<String, double> b in d.balances.entries) GroupDetailRow(categoryLabel(sw: sw, category: b.key), tsh(b.value)),
                            GroupDetailRow(
                              sw ? 'Deni la michango' : 'Contributions owed',
                              tsh(d.owingTotal),
                              valueColor: d.owingTotal > 0 ? ThemeConstants.warningAmber : ThemeConstants.successGreen,
                            ),
                          ],
                        ),
                        if (d.owing.isNotEmpty)
                          GlowCard(
                            title: sw ? 'Kinachodaiwa' : 'Owed',
                            children: <Widget>[for (final GroupObligation o in d.owing) ObligationLine(o: o, sw: sw)],
                          ),
                        if (d.waiting.isNotEmpty)
                          GlowCard(
                            title: sw ? 'Yanasubiri uthibitisho' : 'Waiting for verification',
                            children: <Widget>[for (final GroupTransaction t in d.waiting) GroupTransactionTile(t: t, sw: sw)],
                          ),
                        if (d.promises.isNotEmpty)
                          GlowCard(
                            title: sw ? 'Ahadi' : 'Promises',
                            children: <Widget>[for (final GroupPromise p in d.promises) PromiseLine(p: p, sw: sw)],
                          ),
                        if (d.lines.isEmpty) GroupEmpty(sw ? 'Bado hakuna malipo yaliyothibitishwa.' : 'No verified payments yet.'),
                        if (d.lines.isNotEmpty)
                          GlowListCard(
                            dividerKey: 'grp_stmt_div',
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            children: <Widget>[
                              for (final GroupTransaction t in d.lines)
                                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                                  GroupTransactionTile(
                                    t: t,
                                    sw: sw,
                                    onTap: t.receiptNumber == null ? null : () => GroupDocuments.shareReceipt(context, widget.api, t.id, sw: sw),
                                  ),
                                  if (d.balanceAfter[t.id] != null)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                      child: Text(
                                        '${sw ? 'Salio la' : 'Balance of'} ${categoryLabel(sw: sw, category: t.category).toLowerCase()}: ${tsh(d.balanceAfter[t.id]!)}',
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                                      ),
                                    ),
                                ]),
                            ],
                          ),
                      ]),
                    ),
                  ),
      ),
    );
  }
}

/// One contribution owed: what, when it falls due, how much is left, where it stands.
class ObligationLine extends StatelessWidget {
  const ObligationLine({required this.o, required this.sw, super.key, this.showMember = false, this.onTap});

  final GroupObligation o;
  final bool sw;
  final bool showMember;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) => ListTile(
        key: Key('grp_obl_${o.id}'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        title: Text(showMember ? '${o.memberName ?? ''} · ${o.title}' : o.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(
          <String>[
            '${sw ? 'Mwisho' : 'Due'} ${dateLabel(o.dueDate)}',
            if (o.daysOverdue > 0) (sw ? 'siku ${o.daysOverdue}' : '${o.daysOverdue} day(s)'),
            if (o.paid > 0) '${sw ? 'Imelipwa' : 'Paid'} ${tsh(o.paid)}',
            if (o.exemptReason != null) o.exemptReason!,
          ].join(' · '),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(tsh(o.owing ? o.remaining : o.amountDue), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            GroupPill(obligationStateLabel(sw: sw, state: o.state), color: obligationStateColor(o.state)),
          ],
        ),
      );
}

/// One promise: how much, by when, and whether it was kept.
class PromiseLine extends StatelessWidget {
  const PromiseLine({required this.p, required this.sw, super.key, this.showMember = false, this.onTap});

  final GroupPromise p;
  final bool sw;
  final bool showMember;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) => ListTile(
        key: Key('grp_prom_${p.id}'),
        dense: true,
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        title: Text(
          '${showMember ? '${p.memberName ?? ''} · ' : ''}${tsh(p.amount)} · ${dateLabel(p.promisedOn)}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(<String>[if (p.obligationLabel != null) p.obligationLabel!, if (p.note != null) p.note!].join(' · '), style: const TextStyle(color: Colors.white60, fontSize: 12)),
        trailing: GroupPill(promiseStateLabel(sw: sw, state: p.state), color: promiseStateColor(p.state)),
      );
}
