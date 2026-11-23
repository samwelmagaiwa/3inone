
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../../widgets/scrolling_chip_row.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../services/group_documents.dart';
import '../services/groups_api.dart';
import 'group_dashboard_screen.dart';
import 'groups_text.dart';
import 'widgets/groups_ui.dart';

/// A member's statement: their account (what the group holds for them), the totals of the period chosen, what is still owed, what waits for
/// verification, promises, and every transaction with the balance after it. One's own ([memberId] null) or, for an officer, a member's.
/// The period and the kind of money are chosen with the buttons at the top; the document (PDF, picture, Word) holds the whole period.
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

  /// month | three | year | all | custom
  String _range = 'all';
  DateTimeRange? _custom;

  /// all | savings | shares | contribution | joining_fee | loans | other
  String _kind = 'all';

  static String _iso(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The first and last day of the period chosen (null = no limit).
  (String?, String?) get _period {
    final DateTime now = DateTime.now();
    switch (_range) {
      case 'month':
        return (_iso(DateTime(now.year, now.month)), _iso(now));
      case 'three':
        return (_iso(DateTime(now.year, now.month - 2)), _iso(now));
      case 'year':
        return (_iso(DateTime(now.year)), _iso(now));
      case 'custom':
        return _custom == null ? (null, null) : (_iso(_custom!.start), _iso(_custom!.end));
      default:
        return (null, null);
    }
  }

  /// Which kind of money a line belongs to, for the filter.
  static String _group(final GroupTransaction t) {
    switch (t.category) {
      case 'savings':
      case 'dividend':
        return 'savings';
      case 'shares':
      case 'contribution':
      case 'joining_fee':
        return t.category;
      case 'loan_disbursement':
      case 'loan_repayment':
        return 'loans';
      default:
        return 'other';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final (String? from, String? to) = _period;
      final GroupStatementData? d = await widget.api.statement(memberId: widget.memberId, from: from, to: to);
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
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

  Future<void> _choose(final String range) async {
    if (range == 'custom') {
      final DateTime now = DateTime.now();
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2015),
        lastDate: now,
        initialDateRange: _custom ?? DateTimeRange(start: DateTime(now.year, now.month), end: now),
      );
      if (picked == null || !mounted) return;
      _custom = picked;
    }
    setState(() => _range = range);
    await _load();
  }

  /// The label of the period under the buttons.
  String _periodText(final bool sw) {
    final (String? from, String? to) = _period;
    if (from == null && to == null) return sw ? 'Muda wote' : 'All time';
    return '${dateLabel(from)} - ${dateLabel(to ?? _iso(DateTime.now()))}';
  }

  /// Makes the statement as a PDF, picture or Word file (the whole period, every kind of money) and opens the share sheet.
  Future<void> _share() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final GroupStatementData? d = _data;
    if (d == null) return;
    try {
      final GroupMe me = await widget.api.me();
      if (!mounted) return;
      await GroupDocuments.shareDoc(
        context,
        GroupDocuments.statementDoc(d, sw: sw, group: me.groupName ?? '', memberName: widget.memberName ?? d.member?.fullName ?? me.member?.fullName ?? '', loans: d.loans),
        sw: sw,
      );
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupStatementData? d = _data;
    final List<(String, String)> ranges = <(String, String)>[
      ('all', sw ? 'Muda wote' : 'All time'),
      ('month', sw ? 'Mwezi huu' : 'This month'),
      ('three', sw ? 'Miezi 3' : 'Last 3 months'),
      ('year', sw ? 'Mwaka huu' : 'This year'),
      ('custom', sw ? 'Chagua tarehe' : 'Choose dates'),
    ];
    final List<(String, String)> kinds = <(String, String)>[
      ('all', sw ? 'Zote' : 'All'),
      ('savings', sw ? 'Akiba' : 'Savings'),
      ('shares', sw ? 'Hisa' : 'Shares'),
      ('contribution', sw ? 'Michango' : 'Contributions'),
      ('joining_fee', sw ? 'Ada ya kujiunga' : 'Joining fee'),
      ('loans', sw ? 'Mikopo' : 'Loans'),
      ('other', sw ? 'Nyingine' : 'Other'),
    ];
    final List<GroupTransaction> shown = d == null ? const <GroupTransaction>[] : <GroupTransaction>[for (final GroupTransaction t in d.lines) if (_kind == 'all' || _group(t) == _kind) t];
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(
        widget.memberName ?? (sw ? 'Taarifa yangu ya fedha' : 'My statement'),
        flat: true,
        actions: <Widget>[
          if (d != null)
            IconButton(key: const Key('grp_stmt_pdf'), tooltip: sw ? 'Shiriki (PDF, picha, Word)' : 'Share (PDF, picture, Word)', icon: const Icon(Icons.picture_as_pdf_rounded), onPressed: _share),
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
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: <Widget>[
                        // The buttons first, then the sections.
                        ScrollingChipRow(padding: EdgeInsets.zero, children: <Widget>[
                          for (final (String, String) r in ranges)
                            ScrollChoiceChip(chipKey: Key('grp_stmt_range_${r.$1}'), label: r.$2, selected: _range == r.$1, onSelected: (_) => _choose(r.$1)),
                        ]),
                        const SizedBox(height: 4),
                        ScrollingChipRow(padding: EdgeInsets.zero, children: <Widget>[
                          for (final (String, String) k in kinds)
                            ScrollChoiceChip(chipKey: Key('grp_stmt_kind_${k.$1}'), label: k.$2, selected: _kind == k.$1, onSelected: (_) => setState(() => _kind = k.$1)),
                        ]),
                        const SizedBox(height: 8),
                        ...joinGlowCards(<Widget>[
                          GlowCard(
                            title: sw ? 'Akaunti' : 'Account',
                            children: <Widget>[
                              if (d.member != null)
                                Text(
                                  '${d.member!.fullName}${d.member!.memberNumber == null ? '' : ' · ${d.member!.memberNumber}'}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              const SizedBox(height: 6),
                              Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(tsh(d.account), key: const Key('grp_stmt_account'), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                                ),
                              ),
                              Text(
                                sw ? 'Hadi sasa kikundi kinakushikilia (akiba na hisa)' : 'Held for you by the group so far (savings and shares)',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                              GroupDetailRow(categoryLabel(sw: sw, category: 'savings'), tsh(d.balances['savings'] ?? 0), valueColor: ThemeConstants.invAccent),
                              GroupDetailRow(categoryLabel(sw: sw, category: 'shares'), tsh(d.balances['shares'] ?? 0), valueColor: ThemeConstants.invAccent),
                              GroupDetailRow(categoryLabel(sw: sw, category: 'joining_fee'), tsh(d.balances['joining_fee'] ?? 0)),
                              GroupDetailRow(categoryLabel(sw: sw, category: 'contribution'), tsh(d.balances['contribution'] ?? 0)),
                              GroupDetailRow(
                                sw ? 'Deni la michango' : 'Contributions owed',
                                tsh(d.owingTotal),
                                valueColor: d.owingTotal > 0 ? ThemeConstants.warningAmber : ThemeConstants.successGreen,
                              ),
                            ],
                          ),
                          GlowCard(
                            title: '${sw ? 'Kipindi' : 'Period'}: ${_periodText(sw)}',
                            children: <Widget>[
                              if (_range != 'all') GroupDetailRow(sw ? 'Akaunti mwanzoni' : 'Account at the start', tsh(d.period.opening)),
                              GroupDetailRow(sw ? 'Iliyoingia' : 'Money in', tsh(d.period.moneyIn), valueColor: ThemeConstants.successGreen),
                              GroupDetailRow(sw ? 'Iliyotoka' : 'Money out', tsh(d.period.moneyOut), valueColor: d.period.moneyOut > 0 ? ThemeConstants.errorText : null),
                              GroupDetailRow(sw ? 'Akaunti mwishoni' : 'Account at the end', tsh(d.period.closing)),
                              GroupDetailRow(sw ? 'Miamala' : 'Transactions', '${d.period.count}'),
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
                          if (d.declined.isNotEmpty)
                            GlowCard(
                              key: const Key('grp_stmt_declined'),
                              title: sw ? 'Yaliyokataliwa' : 'Turned down',
                              children: <Widget>[for (final GroupTransaction t in d.declined) GroupTransactionTile(t: t, sw: sw)],
                            ),
                          if (d.promises.isNotEmpty)
                            GlowCard(
                              title: sw ? 'Ahadi' : 'Promises',
                              children: <Widget>[for (final GroupPromise p in d.promises) PromiseLine(p: p, sw: sw)],
                            ),
                          if (shown.isEmpty)
                            GlowCard(
                              title: sw ? 'Miamala yote' : 'All transactions',
                              children: <Widget>[Text(sw ? 'Hakuna miamala katika kipindi hiki.' : 'No transactions in this period.', key: const Key('grp_stmt_none'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60))],
                            )
                          else
                            GlowCard(
                              title: '${sw ? 'Miamala yote' : 'All transactions'} (${shown.length})',
                              dividerKey: 'grp_stmt_div',
                              children: <Widget>[
                                for (final GroupTransaction t in shown)
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
                      ],
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
