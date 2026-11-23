import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../../widgets/month_selector.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../../inventory/screens/widgets/joined_sections.dart';
import '../models/group_models.dart';
import '../models/group_records_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';

/// The group at a glance for its officers, built from the other services' dashboards:
///
///   - the transport dashboard's glass balance card: the cash the records say the group holds, the month's money in and out;
///   - the rental dashboard's ring: how much of the month's contributions came in;
///   - the rental bento tiles: members, savings, loans owed, what is overdue;
///   - the inventory dashboard's glowing chart card with its months and the line / bars toggle: 12 months of money in and out, or the
///     month's money by kind;
///   - the rental wide rows: the year's welfare, dividends, hire income and spending;
///   - quick actions, each shown only to whoever may do it.
///
/// Money appears only for whoever sees the group's money; the secretary sees the membership part.
class GroupOverviewDashboard extends StatefulWidget {
  const GroupOverviewDashboard({required this.api, required this.me, required this.onOpen, super.key, this.between = const <Widget>[]});

  /// What the screen puts between the figures and the trend (who I am, what waits for me): the trend is the last thing on the page.
  final List<Widget> between;

  final GroupsApi api;
  final GroupMe me;
  final void Function(String section) onOpen;

  @override
  State<GroupOverviewDashboard> createState() => GroupOverviewDashboardState();
}

class GroupOverviewDashboardState extends State<GroupOverviewDashboard> {
  int _month = DateTime.now().month;
  GroupDashboardData? _d;
  String? _error;
  bool _bars = false;

  static List<String> get _months => List<String>.generate(12, (final int i) => LocalizationService.instance.translate('month_short_${i + 1}'));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  /// Read again (pull to refresh on Home calls this too).
  Future<void> load() async {
    final String month = '${DateTime.now().year.toString().padLeft(4, '0')}-${_month.toString().padLeft(2, '0')}';
    try {
      final GroupDashboardData d = await widget.api.dashboard(month: month);
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  /// "1.2M", "350K", "900".
  static String short(final double v) {
    final double a = v.abs();
    if (a >= 1000000) return '${(v / 1000000).toStringAsFixed(a >= 10000000 ? 0 : 1)}M';
    if (a >= 1000) return '${(v / 1000).toStringAsFixed(a >= 10000 ? 0 : 1)}K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupDashboardData? d = _d;
    if (d == null) {
      // While it loads, only a spinner: the person's own cards wait for the figures, so the page appears once, in its final order. If the
      // figures cannot be loaded, the message shows and the person's own cards still appear under it.
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, style: const TextStyle(color: Colors.white70))),
        ),
        if (_error != null) ...joinGlowCards(widget.between),
      ]);
    }
    final GroupDashboardMoney? m = d.money;
    return Column(
      key: const Key('grp_overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 1. what can be done now
        _actions(sw),
        // 2. the month all the figures below are for
        if (m != null) ...<Widget>[
          const SizedBox(height: 18),
          _title(sw ? 'Hali ya kikundi' : 'The group at a glance'),
          const SizedBox(height: 8),
          MonthSelector(
            months: _months,
            selectedMonth: _month,
            selectedColor: Colors.white,
            unselectedColor: Colors.white60,
            onSelected: (final int month) {
              setState(() => _month = month);
              load();
            },
          ),
          const SizedBox(height: 10),
          // 3. the headline: cash and the month's collection, two tiles in one row
          IntrinsicHeight(
            key: const Key('grp_overview_joined'),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Expanded(child: _BalanceCard(cash: m.cash, monthIn: m.monthIn, monthOut: m.monthOut, pending: m.pendingCount, sw: sw, onTap: () => widget.onOpen('payments'))),
              const SizedBox(width: 10),
              Expanded(
                child: _RingTile(
                  key: const Key('grp_overview_ring'),
                  title: sw ? 'Michango iliyolipwa mwezi huu' : 'Contributions collected this month',
                  rate: m.collectionRate,
                  detail: '${tsh(m.collected)} / ${tsh(m.expected)}',
                  onTap: () => widget.onOpen('contributions'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ] else
          const SizedBox(height: 18),
        // 4. the four numbers to watch
        Row(children: <Widget>[
          Expanded(
            child: GroupBento(
              key: const Key('grp_overview_members'),
              icon: Icons.groups_rounded,
              color: ThemeConstants.invAccent,
              value: '${d.active}',
              label: d.applications > 0 ? '${sw ? 'Wanachama' : 'Members'} · ${d.applications} ${sw ? 'maombi' : 'applying'}' : (sw ? 'Wanachama hai' : 'Active members'),
              onTap: () => widget.onOpen('members'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: m == null
                ? GroupBento(icon: Icons.person_add_alt_1_rounded, color: ThemeConstants.successGreen, value: '${d.joinedInMonth}', label: sw ? 'Waliojiunga mwezi huu' : 'Joined this month')
                : GroupBento(
                    key: const Key('grp_overview_savings'),
                    icon: Icons.savings_rounded,
                    color: ThemeConstants.successGreen,
                    value: short(m.savings),
                    label: sw ? 'Akiba yote' : 'All savings',
                    onTap: () => widget.onOpen('payments'),
                  ),
          ),
        ]),
        if (m != null) ...<Widget>[
          const SizedBox(height: 10),
          Row(children: <Widget>[
            Expanded(
              child: GroupBento(
                key: const Key('grp_overview_loans'),
                icon: Icons.request_quote_rounded,
                color: ThemeConstants.primaryOrange,
                value: short(m.loanPrincipal + m.loanInterest),
                label: '${sw ? 'Mikopo inadaiwa' : 'Loans owed'} · ${m.loansRunning}',
                onTap: () => widget.onOpen('loans'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GroupBento(
                key: const Key('grp_overview_overdue'),
                icon: Icons.warning_amber_rounded,
                color: (m.overdueAmount + m.loanArrears) > 0 ? ThemeConstants.errorRed : ThemeConstants.successGreen,
                value: short(m.overdueAmount + m.loanArrears),
                label: sw ? 'Imepita muda' : 'Overdue',
                onTap: () => widget.onOpen('contributions'),
              ),
            ),
          ]),
          // 5. the year, in four short tiles instead of four long rows
          const SizedBox(height: 22),
          _title(sw ? 'Mwaka huu' : 'This year so far'),
          const SizedBox(height: 8),
          Row(children: <Widget>[
            Expanded(child: GroupBento(icon: Icons.volunteer_activism_rounded, color: ThemeConstants.invAccent, value: short(m.welfarePaid), label: sw ? 'Msaada' : 'Welfare paid', onTap: () => widget.onOpen('welfare'))),
            const SizedBox(width: 10),
            Expanded(child: GroupBento(icon: Icons.savings_outlined, color: ThemeConstants.successGreen, value: short(m.dividends), label: sw ? 'Gawio' : 'Dividends')),
          ]),
          const SizedBox(height: 10),
          Row(children: <Widget>[
            Expanded(child: GroupBento(icon: Icons.chair_alt_rounded, color: ThemeConstants.primaryOrange, value: short(m.hireIncome), label: sw ? 'Mapato ya kukodisha' : 'Hire income', onTap: () => widget.onOpen('assets'))),
            const SizedBox(width: 10),
            Expanded(child: GroupBento(icon: Icons.receipt_long_rounded, color: ThemeConstants.errorRed, value: short(m.expenses), label: sw ? 'Matumizi' : 'Spending', onTap: () => widget.onOpen('payments'))),
          ]),
        ],
        ..._desk(sw, d, hasMoney: m != null),
        if (widget.between.isNotEmpty) ...<Widget>[const SizedBox(height: 22), ...joinGlowCards(widget.between)],
        // 6. the trend: the last thing on the page, after who I am and what waits
        if (m != null) ...<Widget>[
          const SizedBox(height: 22),
          _title(sw ? 'Mwenendo wa fedha' : 'Money over time'),
          const SizedBox(height: 8),
          _chartCard(sw, m),
        ],
      ],
    );
  }

  /// What the person's office oversees, from the server's `desk`: only the sections their rights open.
  List<Widget> _desk(final bool sw, final GroupDashboardData d, {required final bool hasMoney}) {
    final Map<String, double>? pr = d.projectsDesk;
    final Map<String, double>? ln = d.loansDesk;
    final Map<String, double>? mt = d.meetingsDesk;
    int n(final Map<String, double> m, final String k) => (m[k] ?? 0).round();
    return <Widget>[
      if (pr != null) ...<Widget>[
        const SizedBox(height: 22),
        _title(sw ? 'Miradi' : 'Projects'),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(child: GroupBento(key: const Key('grp_desk_proposed'), icon: Icons.lightbulb_outline_rounded, color: ThemeConstants.warningAmber, value: '${n(pr, 'proposed')}', label: sw ? 'Mapendekezo' : 'Proposals', onTap: () => widget.onOpen('projects'))),
          const SizedBox(width: 10),
          Expanded(child: GroupBento(key: const Key('grp_desk_running'), icon: Icons.play_circle_outline_rounded, color: ThemeConstants.invAccent, value: '${n(pr, 'active')}', label: sw ? 'Inayoendelea' : 'Running', onTap: () => widget.onOpen('projects'))),
        ]),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          Expanded(child: GroupBento(key: const Key('grp_desk_spent'), icon: Icons.payments_rounded, color: ThemeConstants.errorRed, value: '${short(pr['spent'] ?? 0)} / ${short(pr['budget'] ?? 0)}', label: sw ? 'Imetumika / bajeti' : 'Spent / budget', onTap: () => widget.onOpen('projects'))),
          const SizedBox(width: 10),
          Expanded(child: GroupBento(key: const Key('grp_desk_done'), icon: Icons.task_alt_rounded, color: ThemeConstants.successGreen, value: '${n(pr, 'completed')}', label: sw ? 'Iliyokamilika' : 'Completed', onTap: () => widget.onOpen('projects'))),
        ]),
      ],
      if (ln != null && !hasMoney) ...<Widget>[
        const SizedBox(height: 22),
        _title(sw ? 'Mikopo' : 'Loans'),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(child: GroupBento(key: const Key('grp_desk_loan_review'), icon: Icons.thumb_up_alt_outlined, color: ThemeConstants.warningAmber, value: '${n(ln, 'under_review')}', label: sw ? 'Ya kupendekeza' : 'To recommend', onTap: () => widget.onOpen('loans'))),
          const SizedBox(width: 10),
          Expanded(child: GroupBento(key: const Key('grp_desk_loan_approve'), icon: Icons.verified_rounded, color: ThemeConstants.invAccent, value: '${n(ln, 'recommended')}', label: sw ? 'Ya kuidhinisha' : 'To approve', onTap: () => widget.onOpen('loans'))),
        ]),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          Expanded(child: GroupBento(key: const Key('grp_desk_loan_pay'), icon: Icons.payments_rounded, color: ThemeConstants.primaryOrange, value: '${n(ln, 'approved')}', label: sw ? 'Ya kutoa' : 'To pay out', onTap: () => widget.onOpen('loans'))),
          const SizedBox(width: 10),
          Expanded(child: GroupBento(key: const Key('grp_desk_loan_running'), icon: Icons.request_quote_rounded, color: ThemeConstants.successGreen, value: '${n(ln, 'active')}', label: sw ? 'Inayolipwa' : 'Running', onTap: () => widget.onOpen('loans'))),
        ]),
      ],
      if (mt != null) ...<Widget>[
        const SizedBox(height: 22),
        _title(sw ? 'Vikao na kumbukumbu' : 'Meetings and records'),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(child: GroupBento(key: const Key('grp_desk_to_record'), icon: Icons.edit_note_rounded, color: ThemeConstants.warningAmber, value: '${n(mt, 'to_record')}', label: sw ? 'Vikao vya kurekodi' : 'To record', onTap: () => widget.onOpen('community'))),
          const SizedBox(width: 10),
          Expanded(child: GroupBento(key: const Key('grp_desk_minutes'), icon: Icons.fact_check_rounded, color: ThemeConstants.invAccent, value: '${n(mt, 'minutes_open')}', label: sw ? 'Muhtasari haujaidhinishwa' : 'Minutes unapproved', onTap: () => widget.onOpen('community'))),
        ]),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          Expanded(child: GroupBento(key: const Key('grp_desk_actions'), icon: Icons.assignment_turned_in_rounded, color: ThemeConstants.successGreen, value: '${n(mt, 'open_actions')}', label: sw ? 'Kazi zilizo wazi' : 'Open actions', onTap: () => widget.onOpen('community'))),
          const SizedBox(width: 10),
          Expanded(child: GroupBento(key: const Key('grp_desk_late'), icon: Icons.assignment_late_rounded, color: ThemeConstants.errorRed, value: '${n(mt, 'overdue_actions')}', label: sw ? 'Zilizochelewa' : 'Overdue', onTap: () => widget.onOpen('community'))),
        ]),
      ],
    ];
  }

  /// A small heading that names the group of cards under it.
  Widget _title(final String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
      );

  /// The inventory dashboard's glowing chart card: the months above, the line (12 months of money in and out) or the bars (the month by kind).
  Widget _chartCard(final bool sw, final GroupDashboardMoney m) => DecoratedBox(
        key: const Key('grp_overview_chart'),
        decoration: joinedCardDecoration(),
        child: DecoratedBox(
          decoration: joinedCardBorder(),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Expanded(child: Text(_bars ? (sw ? 'Mwezi huu kwa aina' : 'This month, by kind') : (sw ? 'Miezi 12' : 'Last 12 months'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600))),
                _toggle(sw),
              ]),
              const SizedBox(height: 16),
              SizedBox(height: 220, child: _bars ? _mixBars(sw, m) : _trendLines(sw, m)),
              const SizedBox(height: 8),
              if (!_bars)
                Row(children: <Widget>[
                  _legend(ThemeConstants.successGreen, sw ? 'Zilizoingia' : 'In'),
                  const SizedBox(width: 16),
                  _legend(ThemeConstants.errorRed, sw ? 'Zilizotoka' : 'Out'),
                ]),
            ]),
          ),
        ),
      );

  Widget _legend(final Color c, final String label) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]);

  Widget _toggle(final bool sw) {
    Widget b(final String key, final IconData icon, final String tip, final VoidCallback onTap, {required final bool on}) => Tooltip(
          message: tip,
          child: InkWell(
            key: ValueKey<String>(key),
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: on ? Colors.white.withValues(alpha: 0.22) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 20, color: on ? Colors.white : Colors.white54),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        b('grp_chart_line', Icons.show_chart_rounded, sw ? 'Miezi 12' : '12 months', () => setState(() => _bars = false), on: !_bars),
        b('grp_chart_bars', Icons.bar_chart_rounded, sw ? 'Kwa aina' : 'By kind', () => setState(() => _bars = true), on: _bars),
      ]),
    );
  }

  Widget _trendLines(final bool sw, final GroupDashboardMoney m) {
    if (m.trend.every(((String, double, double) t) => t.$2 == 0 && t.$3 == 0)) {
      return Center(child: Text(sw ? 'Bado hakuna fedha zilizothibitishwa.' : 'No verified money yet.', style: const TextStyle(color: Colors.white70)));
    }
    final double top = m.trend.fold<double>(0, (final double a, final (String, double, double) t) => math.max(a, math.max(t.$2, t.$3)));
    final double maxY = top <= 0 ? 1 : top * 1.15;
    LineChartBarData line(final Color c, final double Function((String, double, double)) pick) => LineChartBarData(
          spots: <FlSpot>[for (int i = 0; i < m.trend.length; i++) FlSpot(i.toDouble(), pick(m.trend[i]))],
          isCurved: true,
          preventCurveOverShooting: true,
          color: c,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: <Color>[c.withValues(alpha: 0.28), c.withValues(alpha: 0.02)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        );
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (m.trend.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(drawVerticalLine: false, horizontalInterval: maxY / 4, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withValues(alpha: 0.12), strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: maxY / 4,
              getTitlesWidget: (final double v, final TitleMeta meta) => Text(short(v), style: const TextStyle(color: Colors.white60, fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 2,
              reservedSize: 24,
              getTitlesWidget: (final double v, final TitleMeta meta) {
                final int i = v.toInt();
                if (i < 0 || i >= m.trend.length) return const SizedBox.shrink();
                final int month = int.tryParse(m.trend[i].$1.substring(5)) ?? 1;
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(_months[month - 1], style: const TextStyle(color: Colors.white60, fontSize: 10)));
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (final List<LineBarSpot> spots) => <LineTooltipItem?>[
              for (final LineBarSpot s in spots)
                LineTooltipItem(tsh(s.y), TextStyle(color: s.bar.color ?? Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        lineBarsData: <LineChartBarData>[
          line(ThemeConstants.successGreen, ((String, double, double) t) => t.$2),
          line(ThemeConstants.errorRed, ((String, double, double) t) => t.$3),
        ],
      ),
    );
  }

  Widget _mixBars(final bool sw, final GroupDashboardMoney m) {
    final List<(String, double, double)> mix = m.mix.where(((String, double, double) x) => x.$2 > 0 || x.$3 > 0).toList();
    if (mix.isEmpty) {
      return Center(child: Text(sw ? 'Hakuna fedha mwezi huu.' : 'No money this month.', style: const TextStyle(color: Colors.white70)));
    }
    final double top = mix.fold<double>(0, (final double a, final (String, double, double) x) => math.max(a, math.max(x.$2, x.$3)));
    return BarChart(
      BarChartData(
        maxY: top * 1.15,
        gridData: FlGridData(drawVerticalLine: false, horizontalInterval: top * 1.15 / 4, getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withValues(alpha: 0.12), strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: top * 1.15 / 4,
              getTitlesWidget: (final double v, final TitleMeta meta) => Text(short(v), style: const TextStyle(color: Colors.white60, fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (final double v, final TitleMeta meta) {
                final int i = v.toInt();
                if (i < 0 || i >= mix.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 60,
                    child: Text(categoryLabel(sw: sw, category: mix[i].$1), maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 9)),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (final BarChartGroupData g, final int gi, final BarChartRodData rod, final int ri) =>
                BarTooltipItem(tsh(rod.toY), const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
        barGroups: <BarChartGroupData>[
          for (int i = 0; i < mix.length; i++)
            BarChartGroupData(x: i, barsSpace: 3, barRods: <BarChartRodData>[
              BarChartRodData(toY: mix[i].$2, color: ThemeConstants.successGreen, width: 10, borderRadius: BorderRadius.circular(3)),
              BarChartRodData(toY: mix[i].$3, color: ThemeConstants.errorRed, width: 10, borderRadius: BorderRadius.circular(3)),
            ]),
        ],
      ),
    );
  }

  /// The rental dashboard's action icons, each only for whoever may do it.
  Widget _actions(final bool sw) {
    final GroupMe me = widget.me;
    final List<(Key, IconData, Color, String, String)> items = <(Key, IconData, Color, String, String)>[
      if (me.can('record_payments')) (const Key('grp_qa_payment'), Icons.add_card_rounded, ThemeConstants.successGreen, sw ? 'Malipo' : 'Payment', 'payments'),
      if (me.can('manage_members')) (const Key('grp_qa_member'), Icons.person_add_alt_1_rounded, ThemeConstants.invAccent, sw ? 'Mwanachama' : 'Member', 'members'),
      if (me.can('manage_contributions')) (const Key('grp_qa_contribution'), Icons.campaign_rounded, ThemeConstants.primaryOrange, sw ? 'Mchango' : 'Contribution', 'contributions'),
      if (me.can('call_meetings') || me.can('send_texts')) (const Key('grp_qa_meeting'), Icons.forum_rounded, ThemeConstants.warningAmber, sw ? 'Vikao' : 'Meetings', 'community'),
      if (me.can('view_loans')) (const Key('grp_qa_loans'), Icons.request_quote_rounded, ThemeConstants.errorRed, sw ? 'Mikopo' : 'Loans', 'loans'),
      if (me.can('view_projects')) (const Key('grp_qa_projects'), Icons.business_center_rounded, ThemeConstants.invAccent, sw ? 'Miradi' : 'Projects', 'projects'),
      if (me.can('request_expenses') || me.can('view_expenses')) (const Key('grp_qa_expenses'), Icons.receipt_long_rounded, ThemeConstants.warningAmber, sw ? 'Matumizi' : 'Expenses', 'expenses'),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      alignment: WrapAlignment.spaceAround,
      runSpacing: 12,
      spacing: 8,
      children: <Widget>[
        for (final (Key, IconData, Color, String, String) a in items)
          InkResponse(
            key: a.$1,
            onTap: () => widget.onOpen(a.$5),
            radius: 32,
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: a.$3.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(color: a.$3.withValues(alpha: 0.5)),
                ),
                child: Icon(a.$2, color: a.$3, size: 22),
              ),
              const SizedBox(height: 4),
              Text(a.$4, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
      ],
    );
  }
}

/// The frame every tile on this screen shares.
BoxDecoration _tileFrame() => BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      color: Colors.white.withValues(alpha: 0.03),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    );

Widget _tileIcon(final IconData icon, final Color color) =>
    Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle), child: Icon(icon, color: color, size: 18));

/// Cash on record, with what came in and went out this month.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.cash, required this.monthIn, required this.monthOut, required this.pending, required this.sw, required this.onTap});

  final double cash;
  final double monthIn;
  final double monthOut;
  final int pending;
  final bool sw;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) => Material(
        key: const Key('grp_overview_balance'),
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: _tileFrame(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                _tileIcon(Icons.account_balance_wallet_rounded, ThemeConstants.invAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(tsh(cash), key: const Key('grp_overview_cash'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                    ),
                    Text(sw ? 'Fedha kwenye kumbukumbu' : 'Cash on record', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                const Icon(Icons.south_west_rounded, color: ThemeConstants.successGreen, size: 14),
                const SizedBox(width: 4),
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text('${sw ? 'Ndani' : 'In'} ${tsh(monthIn)}', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)))),
              ]),
              const SizedBox(height: 4),
              Row(children: <Widget>[
                const Icon(Icons.north_east_rounded, color: ThemeConstants.errorText, size: 14),
                const SizedBox(width: 4),
                Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text('${sw ? 'Nje' : 'Out'} ${tsh(monthOut)}', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)))),
              ]),
              if (pending > 0) ...<Widget>[
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: ThemeConstants.warningAmber.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                    child: Text('$pending ${sw ? 'zinasubiri' : 'waiting'}', style: const TextStyle(color: ThemeConstants.warningAmber, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ]),
          ),
        ),
      );
}

/// The month's collection as a ring with its figure.
class _RingTile extends StatelessWidget {
  const _RingTile({required this.title, required this.rate, required this.detail, required this.onTap, super.key});

  final String title;
  final double? rate;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final double r = rate ?? 0;
    final Color c = rate == null ? Colors.white38 : (r >= 0.8 ? ThemeConstants.successGreen : (r >= 0.5 ? ThemeConstants.warningAmber : ThemeConstants.errorRed));
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: _tileFrame(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Stack(alignment: Alignment.center, children: <Widget>[
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(value: r, strokeWidth: 4, backgroundColor: Colors.white.withValues(alpha: 0.08), valueColor: AlwaysStoppedAnimation<Color>(c), strokeCap: StrokeCap.round),
                ),
                Icon(Icons.savings_rounded, color: c, size: 14),
              ]),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(rate == null ? '—' : '${(r * 100).toStringAsFixed(0)}%', key: const Key('grp_overview_rate'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
            const Spacer(),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(detail, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
    );
  }
}

/// The rental dashboard's bento tile.
class GroupBento extends StatelessWidget {
  const GroupBento({required this.icon, required this.color, required this.value, required this.label, super.key, this.onTap});

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white.withValues(alpha: 0.03),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(children: <Widget>[
              Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle), child: Icon(icon, color: color, size: 18)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
                ]),
              ),
            ]),
          ),
        ),
      );
}
