import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'assets_screen.dart';
import 'community_screen.dart' show dateTimeLabel;
import 'dividends_screen.dart';
import 'group_overview_dashboard.dart';
import 'groups_text.dart';
import 'meeting_record_screen.dart';
import 'my_loans_screen.dart';
import 'payment_form.dart';
import 'promise_form.dart';
import 'records_screens.dart';
import 'statement_screen.dart';
import 'welfare_screen.dart';
import 'widgets/groups_ui.dart';

/// Home: the person's own membership and money, and -- for officers -- what waits for them. Everyone has it; a member sees nothing of anyone else.
class GroupDashboardScreen extends StatefulWidget {
  const GroupDashboardScreen({required this.me, required this.api, required this.onChanged, required this.onOpen, super.key});

  final GroupMe me;
  final GroupsApi api;
  final Future<void> Function() onChanged;
  final void Function(String section) onOpen;

  @override
  State<GroupDashboardScreen> createState() => _GroupDashboardScreenState();
}

class _GroupDashboardScreenState extends State<GroupDashboardScreen> {
  List<GroupTransaction> _mine = const <GroupTransaction>[];
  String? _error;
  final GlobalKey<GroupOverviewDashboardState> _overview = GlobalKey<GroupOverviewDashboardState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMine());
  }

  Future<void> _loadMine() async {
    if (widget.me.member == null) return;
    try {
      final List<GroupTransaction> mine = await widget.api.myTransactions();
      if (mounted) setState(() => _mine = mine);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  Future<void> _refresh() async {
    await widget.onChanged();
    await _loadMine();
    await _overview.currentState?.load();
  }

  Future<void> _pay([final GroupObligation? o]) async {
    if (await showPaymentForm(context, api: widget.api, me: widget.me, obligation: o)) await _refresh();
  }

  Future<void> _promise() async {
    if (await showPromiseForm(context, api: widget.api, owing: widget.me.owing)) await _refresh();
  }

  Future<void> _myLoans() async {
    await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => MyLoansScreen(api: widget.api, me: widget.me)));
    await _refresh();
  }

  Future<void> _myWelfare() async {
    await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => MyWelfareScreen(api: widget.api)));
    await _refresh();
  }

  Future<void> _myHires() async {
    await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => MyHiresScreen(api: widget.api, me: widget.me)));
    await _refresh();
  }

  Future<void> _myDividends() => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => MyDividendsScreen(api: widget.api)));

  Future<void> _statement() => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => GroupStatementScreen(api: widget.api)));

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupMe me = widget.me;
    final GroupMember? m = me.member;

    final bool officer = me.can('view_finance') || me.can('view_members');
    final List<Widget> personal = <Widget>[
          // Who I am in the group (an administrator with no member record has nothing to show).
          if (m != null)
          GlowListCard(
            dividerKey: 'grp_me_div',
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: ThemeConstants.invAccent.withValues(alpha: 0.25),
                    child: const Icon(Icons.person_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          m.fullName,
                          key: const Key('grp_me_name'),
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${officeLabel(sw: sw, office: m.office)} · ${m.memberNumber ?? m.applicationRef ?? ''}',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  GroupPill(statusLabel(sw: sw, status: m.status), color: statusColor(m.status)),
                ],
              ),
              if (m.statusReason != null && m.status != 'active')
                Text(m.statusReason!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          if (me.waiting.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _WaitingCard(
              sw: sw,
              lines: <Widget>[
                if ((me.waiting['votes_to_cast'] ?? 0) > 0)
                  _WaitLine(
                    key: const Key('grp_wait_votes'),
                    icon: Icons.how_to_vote_rounded,
                    label: sw ? 'Kura za kupiga' : 'Votings waiting for your vote',
                    count: me.waiting['votes_to_cast']!,
                    onTap: () => widget.onOpen('voting'),
                  ),
                if (me.waiting.containsKey('payments_to_verify'))
                  _WaitLine(
                    key: const Key('grp_wait_payments'),
                    icon: Icons.fact_check_rounded,
                    label: sw ? 'Malipo ya kuthibitisha' : 'Payments to verify',
                    count: me.waiting['payments_to_verify']!,
                    onTap: () => widget.onOpen('payments'),
                  ),
                if (me.waiting.containsKey('guarantees'))
                  _WaitLine(
                    key: const Key('grp_wait_guarantees'),
                    icon: Icons.handshake_rounded,
                    label: sw ? 'Umeombwa kudhamini mkopo' : 'Asked to guarantee a loan',
                    count: me.waiting['guarantees']!,
                    onTap: _myLoans,
                  ),
                if (me.waiting.containsKey('loans_to_recommend'))
                  _WaitLine(
                    key: const Key('grp_wait_recommend'),
                    icon: Icons.thumb_up_alt_outlined,
                    label: sw ? 'Mikopo ya kupendekeza' : 'Loans to recommend',
                    count: me.waiting['loans_to_recommend']!,
                    onTap: () => widget.onOpen('loans'),
                  ),
                if (me.waiting.containsKey('loans_to_approve'))
                  _WaitLine(
                    key: const Key('grp_wait_approve'),
                    icon: Icons.verified_rounded,
                    label: sw ? 'Mikopo ya kuidhinisha' : 'Loans to approve',
                    count: me.waiting['loans_to_approve']!,
                    onTap: () => widget.onOpen('loans'),
                  ),
                if (me.waiting.containsKey('loans_to_disburse'))
                  _WaitLine(
                    key: const Key('grp_wait_disburse'),
                    icon: Icons.payments_rounded,
                    label: sw ? 'Mikopo ya kutoa' : 'Loans to pay out',
                    count: me.waiting['loans_to_disburse']!,
                    onTap: () => widget.onOpen('loans'),
                  ),
                if (me.waiting.containsKey('benefits_to_decide'))
                  _WaitLine(
                    key: const Key('grp_wait_benefits'),
                    icon: Icons.volunteer_activism_rounded,
                    label: sw ? 'Maombi ya msaada' : 'Welfare requests',
                    count: me.waiting['benefits_to_decide']!,
                    onTap: () => widget.onOpen('welfare'),
                  ),
                if ((me.waiting['minutes_to_approve'] ?? 0) > 0)
                  _WaitLine(
                    key: const Key('grp_wait_minutes'),
                    icon: Icons.fact_check_rounded,
                    label: sw ? 'Muhtasari wa kuidhinisha' : 'Minutes to approve',
                    count: me.waiting['minutes_to_approve']!,
                    onTap: () => widget.onOpen('community'),
                  ),
                if ((me.waiting['actions_overdue'] ?? 0) > 0)
                  _WaitLine(
                    key: const Key('grp_wait_actions_overdue'),
                    icon: Icons.assignment_late_rounded,
                    label: sw ? 'Kazi za vikao zilizochelewa' : 'Meeting actions overdue',
                    count: me.waiting['actions_overdue']!,
                    onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => MeetingActionsScreen(api: widget.api, all: true))),
                  ),
                if ((me.waiting['my_actions'] ?? 0) > 0)
                  _WaitLine(
                    key: const Key('grp_wait_my_actions'),
                    icon: Icons.assignment_turned_in_rounded,
                    label: sw ? 'Kazi zangu za vikao' : 'My meeting actions',
                    count: me.waiting['my_actions']!,
                    onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => MeetingActionsScreen(api: widget.api, all: false))),
                  ),
                if ((me.waiting['expenses_to_approve'] ?? 0) > 0)
                  _WaitLine(
                    key: const Key('grp_wait_expenses_approve'),
                    icon: Icons.receipt_long_rounded,
                    label: sw ? 'Matumizi ya kuidhinisha' : 'Expenses to approve',
                    count: me.waiting['expenses_to_approve']!,
                    onTap: () => widget.onOpen('expenses'),
                  ),
                if ((me.waiting['expenses_to_pay'] ?? 0) > 0)
                  _WaitLine(
                    key: const Key('grp_wait_expenses_pay'),
                    icon: Icons.payments_rounded,
                    label: sw ? 'Matumizi ya kulipa' : 'Expenses to pay out',
                    count: me.waiting['expenses_to_pay']!,
                    onTap: () => widget.onOpen('expenses'),
                  ),
                if ((me.waiting['projects_to_review'] ?? 0) > 0)
                  _WaitLine(
                    key: const Key('grp_wait_projects_review'),
                    icon: Icons.business_center_rounded,
                    label: sw ? 'Miradi ya kupendekeza' : 'Projects to review',
                    count: me.waiting['projects_to_review']!,
                    onTap: () => widget.onOpen('projects'),
                  ),
                if ((me.waiting['projects_to_approve'] ?? 0) > 0)
                  _WaitLine(
                    key: const Key('grp_wait_projects_approve'),
                    icon: Icons.business_center_rounded,
                    label: sw ? 'Miradi ya kuidhinisha' : 'Projects to approve',
                    count: me.waiting['projects_to_approve']!,
                    onTap: () => widget.onOpen('projects'),
                  ),
                if ((me.waiting['hires_to_decide'] ?? 0) > 0)
                  _WaitLine(
                    key: const Key('grp_wait_hires'),
                    icon: Icons.event_available_rounded,
                    label: sw ? 'Maombi ya kukodi' : 'Hire requests',
                    count: me.waiting['hires_to_decide']!,
                    onTap: () => widget.onOpen('assets'),
                  ),
                if (me.waiting.containsKey('hires_overdue'))
                  _WaitLine(
                    key: const Key('grp_wait_hires_late'),
                    icon: Icons.timer_off_outlined,
                    label: sw ? 'Vitu vilivyochelewa kurudi' : 'Hired things late back',
                    count: me.waiting['hires_overdue']!,
                    onTap: () => widget.onOpen('assets'),
                  ),
                if ((me.waiting['hire_charges'] ?? 0) > 0)
                  _WaitLine(
                    key: const Key('grp_wait_hire_charges'),
                    icon: Icons.gavel_rounded,
                    label: sw ? 'Gharama za uharibifu za kuamua' : 'Damage charges to decide',
                    count: me.waiting['hire_charges']!,
                    onTap: () => widget.onOpen('assets'),
                  ),
                if ((me.waiting['dividends_to_approve'] ?? 0) > 0)
                  _WaitLine(
                    key: const Key('grp_wait_dividends'),
                    icon: Icons.savings_rounded,
                    label: sw ? 'Gawio la kuidhinisha' : 'Dividends to approve',
                    count: me.waiting['dividends_to_approve']!,
                    onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => DividendsScreen(api: widget.api, me: widget.me))),
                  ),
                if ((me.waiting['meetings_to_record'] ?? 0) > 0)
                  _WaitLine(
                    key: const Key('grp_wait_meetings'),
                    icon: Icons.fact_check_rounded,
                    label: sw ? 'Vikao vya kurekodi' : 'Meetings to record',
                    count: me.waiting['meetings_to_record']!,
                    onTap: () => widget.onOpen('community'),
                  ),
                if (me.waiting.containsKey('members_overdue'))
                  _WaitLine(
                    key: const Key('grp_wait_overdue'),
                    icon: Icons.warning_amber_rounded,
                    label: sw ? 'Wanachama wenye michango iliyopita muda' : 'Members with overdue contributions',
                    count: me.waiting['members_overdue']!,
                    onTap: () => widget.onOpen('contributions'),
                  ),
                if (me.waiting.containsKey('applications'))
                  _WaitLine(
                    key: const Key('grp_wait_applications'),
                    icon: Icons.how_to_reg_rounded,
                    label: sw ? 'Maombi ya uanachama' : 'Membership applications',
                    count: me.waiting['applications']!,
                    onTap: () => widget.onOpen('members'),
                  ),
              ],
            ),
          ],
    ];

    // What follows the figures' trend: next meeting and notices, then the person's own money and payments.
    final List<Widget> afterChart = <Widget>[
          if (me.nextMeetingTitle != null || me.notices > 0) ...<Widget>[
            const SizedBox(height: 12),
            GlowListCard(
              dividerKey: 'grp_news_div',
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: <Widget>[
                if (me.nextMeetingTitle != null)
                  ListTile(
                    key: const Key('grp_next_meeting'),
                    leading: const Icon(Icons.event_rounded, color: ThemeConstants.invAccent),
                    title: Text(me.nextMeetingTitle!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    subtitle: Text('${dateTimeLabel(me.nextMeetingAt ?? '')}${me.nextMeetingVenue == null ? '' : ' · ${me.nextMeetingVenue}'}',
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                    onTap: () => widget.onOpen('community'),
                  ),
                if (me.notices > 0)
                  ListTile(
                    key: const Key('grp_notices'),
                    leading: const Icon(Icons.campaign_rounded, color: ThemeConstants.invAccent),
                    title: Text(sw ? 'Matangazo' : 'Notices', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    trailing: Text('${me.notices}', style: const TextStyle(color: ThemeConstants.warningAmber, fontWeight: FontWeight.w800, fontSize: 16)),
                    onTap: () => widget.onOpen('community'),
                  ),
              ],
            ),
          ],
          if (m != null) ...<Widget>[
            GlowCard(
              title: sw ? 'Malipo yangu' : 'My payments',
              dividerKey: 'grp_mypay_div',
              children: <Widget>[
                _DueLine(label: categoryLabel(sw: sw, category: 'joining_fee'), paid: me.balances?['joining_fee'] ?? 0, due: me.joiningFee, sw: sw),
                _DueLine(label: categoryLabel(sw: sw, category: 'shares'), paid: me.balances?['shares'] ?? 0, due: me.shareAmount, sw: sw),
                GroupDetailRow(categoryLabel(sw: sw, category: 'savings'), tsh(me.balances?['savings'] ?? 0), valueColor: ThemeConstants.invAccent),
                if (me.owing.isNotEmpty)
                  GroupDetailRow(
                    sw ? 'Deni la michango' : 'Contributions owed',
                    tsh(me.owing.fold<double>(0, (final double a, final GroupObligation o) => a + o.remaining)),
                    valueColor: me.owing.any((final GroupObligation o) => o.state == 'overdue') ? ThemeConstants.errorText : ThemeConstants.warningAmber,
                  ),
                if (me.pending > 0)
                  GroupDetailRow(sw ? 'Yanasubiri uthibitisho' : 'Waiting for verification', '${me.pending}', valueColor: ThemeConstants.warningAmber),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        key: const Key('grp_pay_open'),
                        style: FilledButton.styleFrom(backgroundColor: ThemeConstants.primaryOrange),
                        onPressed: _pay,
                        icon: const Icon(Icons.payments_rounded),
                        label: Text(sw ? 'Lipa' : 'Pay'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('grp_statement_open'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                        onPressed: _statement,
                        icon: const Icon(Icons.receipt_long_rounded),
                        label: Text(sw ? 'Taarifa' : 'Statement'),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
            if (me.owing.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              GlowCard(
                title: sw ? 'Ninachodaiwa' : 'What I owe',
                dividerKey: 'grp_owe_div',
                children: <Widget>[
                  for (final GroupObligation o in me.owing) ObligationLine(o: o, sw: sw, onTap: () => _pay(o)),
                  TextButton.icon(
                    key: const Key('grp_promise_open'),
                    onPressed: _promise,
                    icon: const Icon(Icons.handshake_outlined, color: ThemeConstants.primaryOrange),
                    label: Text(sw ? 'Weka ahadi ya kulipa' : 'Promise to pay', style: const TextStyle(color: ThemeConstants.primaryOrange)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            GlowListCard(
              dividerKey: 'grp_help_div',
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: <Widget>[
                ListTile(
                  key: const Key('grp_my_loans'),
                  leading: const Icon(Icons.request_quote_rounded, color: ThemeConstants.invAccent),
                  title: Text(sw ? 'Mikopo yangu' : 'My loans', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: _myLoans,
                ),
                ListTile(
                  key: const Key('grp_invite'),
                  leading: const Icon(Icons.person_add_alt_1_rounded, color: ThemeConstants.invAccent),
                  title: Text(sw ? 'Alika mwanachama' : 'Invite a member', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => InviteScreen(api: widget.api, me: widget.me))),
                ),
                ListTile(
                  key: const Key('grp_my_branch'),
                  leading: const Icon(Icons.account_tree_rounded, color: ThemeConstants.invAccent),
                  title: Text(sw ? 'Niliowaleta' : 'Whom I brought in', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => ReferralTreeScreen(api: widget.api, whole: false))),
                ),
                ListTile(
                  key: const Key('grp_my_dividends'),
                  leading: const Icon(Icons.savings_rounded, color: ThemeConstants.invAccent),
                  title: Text(sw ? 'Gawio langu' : 'My dividends', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: _myDividends,
                ),
                ListTile(
                  key: const Key('grp_my_hires'),
                  leading: const Icon(Icons.chair_alt_rounded, color: ThemeConstants.invAccent),
                  title: Text(sw ? 'Kukodi mali ya kikundi' : 'Hire from the group', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: _myHires,
                ),
                ListTile(
                  key: const Key('grp_my_welfare'),
                  leading: const Icon(Icons.volunteer_activism_rounded, color: ThemeConstants.invAccent),
                  title: Text(sw ? 'Msaada (ustawi)' : 'Welfare', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                  onTap: _myWelfare,
                ),
              ],
            ),
            if (me.promises.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              GlowCard(
                title: sw ? 'Ahadi zangu' : 'My promises',
                children: <Widget>[for (final GroupPromise p in me.promises) PromiseLine(p: p, sw: sw)],
              ),
            ],
          ],
          if (m != null)
            GlowCard(
              title: sw ? 'Malipo yangu ya hivi karibuni' : 'My latest payments',
              dividerKey: 'grp_mine_div',
              children: <Widget>[
                if (_error != null) GroupEmpty(_error!),
                if (_mine.isEmpty && _error == null) GroupEmpty(sw ? 'Bado hujatuma malipo.' : 'No payments sent yet.'),
                for (final GroupTransaction t in _mine.take(20)) GroupTransactionTile(t: t, sw: sw),
              ],
            ),
    ];
    // The member's own figures in tiles (not a card), shown before the joined sections.
    final List<Widget> lead = <Widget>[if (m != null) _MyGlance(me: me, sw: sw, onStatement: _statement)];

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: <Widget>[
          // The officers: the group's figures, then ONE joined card (who I am, what waits, the trend, news, my money). Everyone else: the same
          // joined card without the trend. The person's own tiles come before it.
          if (officer)
            GroupOverviewDashboard(key: _overview, api: widget.api, me: me, onOpen: widget.onOpen, lead: lead, beforeChart: personal, afterChart: afterChart)
          else ...<Widget>[
            ...lead,
            if (lead.isNotEmpty) const SizedBox(height: 12),
            ...joinGlowCards(<Widget>[...personal, ...afterChart]),
          ],
        ],
      ),
    );
  }
}

/// A member's own money in four tiles, the same design as the group's: savings, shares, what is owed, what waits for verification.
class _MyGlance extends StatelessWidget {
  const _MyGlance({required this.me, required this.sw, required this.onStatement});

  final GroupMe me;
  final bool sw;
  final VoidCallback onStatement;

  @override
  Widget build(final BuildContext context) {
    final double owed = me.owing.fold<double>(0, (final double a, final GroupObligation o) => a + o.remaining);
    final bool late = me.owing.any((final GroupObligation o) => o.state == 'overdue');
    final double shares = me.balances?['shares'] ?? 0;
    final double savings = me.balances?['savings'] ?? 0;
    final String? number = me.member?.memberNumber ?? me.member?.applicationRef;
    return Column(key: const Key('grp_my_glance'), crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      // The member's account: what the group holds for them, with its number, opening the statement.
      Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const Key('grp_my_account'),
          borderRadius: BorderRadius.circular(20),
          onTap: onStatement,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.white.withValues(alpha: 0.03), border: Border.all(color: Colors.white.withValues(alpha: 0.06))),
            child: Row(children: <Widget>[
              Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: ThemeConstants.invAccent.withValues(alpha: 0.12), shape: BoxShape.circle), child: const Icon(Icons.account_balance_wallet_rounded, color: ThemeConstants.invAccent, size: 18)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(tsh(savings + shares), key: const Key('grp_my_account_total'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
                  Text('${sw ? 'Akaunti yangu' : 'My account'}${number == null ? '' : ' · $number'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
                ]),
              ),
              Text(sw ? 'Taarifa' : 'Statement', style: const TextStyle(color: ThemeConstants.invAccent, fontSize: 12, fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: <Widget>[
        Expanded(child: GroupBento(key: const Key('grp_my_savings'), icon: Icons.savings_rounded, color: ThemeConstants.successGreen, value: GroupOverviewDashboardState.short(me.balances?['savings'] ?? 0), label: sw ? 'Akiba yangu' : 'My savings')),
        const SizedBox(width: 10),
        Expanded(
          child: GroupBento(
            key: const Key('grp_my_shares'),
            icon: Icons.pie_chart_rounded,
            color: ThemeConstants.invAccent,
            value: me.shareAmount > 0 ? '${GroupOverviewDashboardState.short(shares)} / ${GroupOverviewDashboardState.short(me.shareAmount)}' : GroupOverviewDashboardState.short(shares),
            label: sw ? 'Hisa zangu' : 'My shares',
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: <Widget>[
        Expanded(
          child: GroupBento(
            key: const Key('grp_my_owed'),
            icon: owed > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
            color: owed <= 0 ? ThemeConstants.successGreen : (late ? ThemeConstants.errorRed : ThemeConstants.warningAmber),
            value: GroupOverviewDashboardState.short(owed),
            label: sw ? 'Deni langu' : 'Due from me',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: GroupBento(key: const Key('grp_my_pending'), icon: Icons.hourglass_bottom_rounded, color: ThemeConstants.warningAmber, value: '${me.pending}', label: sw ? 'Yanasubiri uthibitisho' : 'Waiting for verification')),
      ]),
    ]);
  }
}

/// "Joining fee · 80,000 of 80,000", green once all is paid.
class _DueLine extends StatelessWidget {
  const _DueLine({required this.label, required this.paid, required this.due, required this.sw});

  final String label;
  final double paid;
  final double due;
  final bool sw;

  @override
  Widget build(final BuildContext context) {
    final bool done = due <= 0 || paid + 0.001 >= due;
    return GroupDetailRow(
      label,
      due > 0 ? '${tsh(paid)} / ${tsh(due)}' : tsh(paid),
      valueColor: done ? ThemeConstants.successGreen : ThemeConstants.warningAmber,
    );
  }
}

class _WaitLine extends StatelessWidget {
  const _WaitLine({required this.icon, required this.label, required this.count, required this.onTap, super.key});

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: count > 0 ? ThemeConstants.warningAmber : Colors.white54),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text('$count', style: TextStyle(color: count > 0 ? ThemeConstants.warningAmber : Colors.white54, fontWeight: FontWeight.w800, fontSize: 16)),
          const Icon(Icons.chevron_right, color: Colors.white38),
        ]),
        onTap: onTap,
      );
}

/// A payment in a list: what it was for, who, how much, and where it stands.
class GroupTransactionTile extends StatelessWidget {
  const GroupTransactionTile({required this.t, required this.sw, super.key, this.showMember = false, this.onTap});

  final GroupTransaction t;
  final bool sw;
  final bool showMember;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) => ListTile(
        key: Key('grp_tx_${t.id}'),
        onTap: onTap,
        title: Text(
          '${t.isReversal ? (sw ? 'Marekebisho: ' : 'Reversal: ') : ''}'
          '${t.category == 'savings' && t.direction == 'out' && !t.isReversal ? (sw ? 'Kutoa akiba' : 'Savings withdrawal') : (t.obligationLabel ?? categoryLabel(sw: sw, category: t.category))}'
          '${showMember && t.memberName != null ? ' · ${t.memberName}' : ''}${t.payee != null ? ' · ${t.payee}' : ''}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          <String>[
            dateLabel(t.paidOn),
            methodLabel(sw: sw, method: t.method),
            if (t.externalRef != null) t.externalRef!,
            if (t.receiptNumber != null) t.receiptNumber!,
            if (t.rejectReason != null) t.rejectReason!,
            if (t.isReversed) (sw ? 'Imerekebishwa' : 'Reversed'),
          ].join(' · '),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              tsh(t.signedAmount),
              style: TextStyle(color: t.signedAmount < 0 ? ThemeConstants.errorText : Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            GroupPill(paymentStatusLabel(sw: sw, status: t.status), color: paymentStatusColor(t.status)),
          ],
        ),
      );
}

/// What waits for this person, most urgent first: only what has something in it, five lines until asked for the rest. When nothing waits it
/// says so, calmly, so the person knows the screen is not simply empty.
class _WaitingCard extends StatefulWidget with GlowSectionWidget {
  const _WaitingCard({required this.sw, required this.lines});

  final bool sw;
  final List<Widget> lines;

  @override
  State<_WaitingCard> createState() => _WaitingCardState();
}

class _WaitingCardState extends State<_WaitingCard> {
  static const int _shown = 5;
  bool _all = false;

  @override
  Widget build(final BuildContext context) {
    final bool sw = widget.sw;
    final List<Widget> live = widget.lines.where((final Widget w) => w is! _WaitLine || w.count > 0).toList();
    if (live.isEmpty) {
      return GlowCard(
        title: sw ? 'Yanayokusubiri' : 'Waiting for you',
        dividerKey: 'grp_wait_div',
        children: <Widget>[
          Row(children: <Widget>[
            const Icon(Icons.check_circle_rounded, color: ThemeConstants.successGreen, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(sw ? 'Hakuna kinachokusubiri. Kila kitu kiko sawa.' : 'Nothing is waiting for you. You are all caught up.', style: const TextStyle(color: Colors.white70))),
          ]),
        ],
      );
    }
    final bool more = live.length > _shown;
    return GlowCard(
      title: sw ? 'Yanayokusubiri' : 'Waiting for you',
      dividerKey: 'grp_wait_div',
      children: <Widget>[
        ...(_all || !more ? live : live.take(_shown)),
        if (more)
          TextButton(
            key: const Key('grp_wait_more'),
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? (sw ? 'Onyesha chache' : 'Show fewer') : (sw ? 'Onyesha zote (${live.length})' : 'Show all (${live.length})'), style: const TextStyle(color: ThemeConstants.primaryOrange)),
          ),
      ],
    );
  }
}
