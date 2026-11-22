import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../../widgets/month_selector.dart';
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
  const GroupOverviewDashboard({required this.api, required this.me, required this.onOpen, super.key});

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
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, style: const TextStyle(color: Colors.white70))),
      );
    }
    final GroupDashboardMoney? m = d.money;
    return Column(
      key: const Key('grp_overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (m != null) ...<Widget>[
          IntrinsicHeight(
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
        ],
        Row(children: <Widget>[
          Expanded(
            child: _Bento(
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
                ? _Bento(icon: Icons.person_add_alt_1_rounded, color: ThemeConstants.successGreen, value: '${d.joinedInMonth}', label: sw ? 'Waliojiunga mwezi huu' : 'Joined this month')
                : _Bento(
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
              child: _Bento(
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
              child: _Bento(
                key: const Key('grp_overview_overdue'),
                icon: Icons.warning_amber_rounded,
                color: (m.overdueAmount + m.loanArrears) > 0 ? ThemeConstants.errorRed : ThemeConstants.successGreen,
                value: short(m.overdueAmount + m.loanArrears),
                label: sw ? 'Imepita muda' : 'Overdue',
                onTap: () => widget.onOpen('contributions'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _chartCard(sw, m),
          const SizedBox(height: 12),
          _WideRow(icon: Icons.volunteer_activism_rounded, color: ThemeConstants.invAccent, label: sw ? 'Msaada uliolipwa mwaka huu' : 'Welfare paid this year', value: tsh(m.welfarePaid), onTap: () => widget.onOpen('welfare')),
          const SizedBox(height: 8),
          _WideRow(icon: Icons.savings_outlined, color: ThemeConstants.successGreen, label: sw ? 'Gawio mwaka huu' : 'Dividends this year', value: tsh(m.dividends)),
          const SizedBox(height: 8),
          _WideRow(icon: Icons.chair_alt_rounded, color: ThemeConstants.primaryOrange, label: sw ? 'Mapato ya kukodisha mwaka huu' : 'Hire income this year', value: tsh(m.hireIncome), onTap: () => widget.onOpen('assets')),
          const SizedBox(height: 8),
          _WideRow(icon: Icons.receipt_long_rounded, color: ThemeConstants.errorRed, label: sw ? 'Matumizi ya kikundi mwaka huu' : 'Group spending this year', value: tsh(m.expenses), onTap: () => widget.onOpen('payments')),
        ],
        const SizedBox(height: 12),
        _actions(sw),
      ],
    );
  }

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
                Expanded(
                  child: MonthSelector(
                    months: _months,
                    selectedMonth: _month,
                    selectedColor: Colors.white,
                    unselectedColor: Colors.white60,
                    onSelected: (final int month) {
                      setState(() => _month = month);
                      load();
                    },
                  ),
                ),
                const SizedBox(width: 8),
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
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
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

/// The transport dashboard's glass balance card.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.cash, required this.monthIn, required this.monthOut, required this.pending, required this.sw, required this.onTap});

  final double cash;
  final double monthIn;
  final double monthOut;
  final int pending;
  final bool sw;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) => DecoratedBox(
        key: const Key('grp_overview_balance'),
        decoration: joinedCardDecoration(),
        child: DecoratedBox(
          decoration: joinedCardBorder(),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Row(children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                      child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white),
                    ),
                    const Spacer(),
                    if (pending > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: ThemeConstants.warningAmber.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                        child: Text('$pending ${sw ? 'zinasubiri' : 'waiting'}', style: const TextStyle(color: ThemeConstants.warningAmber, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(tsh(cash), key: const Key('grp_overview_cash'), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                  ),
                  Text(sw ? 'Fedha kwenye kumbukumbu' : 'Cash on record', style: const TextStyle(color: Colors.white60)),
                  const SizedBox(height: 10),
                  Row(children: <Widget>[
                    const Icon(Icons.south_west_rounded, color: ThemeConstants.successGreen, size: 16),
                    const SizedBox(width: 4),
                    Flexible(child: Text('${sw ? 'Ndani' : 'In'} ${tsh(monthIn)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: <Widget>[
                    const Icon(Icons.north_east_rounded, color: ThemeConstants.errorText, size: 16),
                    const SizedBox(width: 4),
                    Flexible(child: Text('${sw ? 'Nje' : 'Out'} ${tsh(monthOut)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// The rental dashboard's ring tile: a rate as a ring with its figure.
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
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.white.withValues(alpha: 0.04),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Stack(alignment: Alignment.center, children: <Widget>[
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(value: r, strokeWidth: 5, backgroundColor: Colors.white.withValues(alpha: 0.06), valueColor: AlwaysStoppedAnimation<Color>(c), strokeCap: StrokeCap.round),
                ),
                const Icon(Icons.savings_rounded, color: Colors.white, size: 18),
              ]),
              const SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(rate == null ? '—' : '${(r * 100).toStringAsFixed(0)}%', key: const Key('grp_overview_rate'), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(detail, style: const TextStyle(color: Colors.white54, fontSize: 12))),
          ]),
        ),
      ),
    );
  }
}

/// The rental dashboard's bento tile.
class _Bento extends StatelessWidget {
  const _Bento({required this.icon, required this.color, required this.value, required this.label, super.key, this.onTap});

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

/// The rental dashboard's wide row with a chevron.
class _WideRow extends StatelessWidget {
  const _WideRow({required this.icon, required this.color, required this.label, required this.value, this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(final BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white.withValues(alpha: 0.03),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(children: <Widget>[
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
              if (onTap != null) ...<Widget>[const SizedBox(width: 4), const Icon(Icons.chevron_right, color: Colors.white24, size: 20)],
            ]),
          ),
        ),
      );
}
