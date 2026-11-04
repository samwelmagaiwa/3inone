import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../models/salon_models.dart';
import '../../services/salon_api.dart';
import '../widgets/inventory_widgets.dart';
import 'salon_text.dart';
import 'stylist_detail_screen.dart';
import 'stylist_targets_sheet.dart';
import '../widgets/glow_list_card.dart';

enum _Period { thisMonth, lastMonth, last7 }

/// How each stylist did: what the services they did brought in, how many services, visits and different clients,
/// for this month, last month or the last 7 days. The owner and managers see everyone; a stylist sees only their
/// own line (the server decides that).
class StylistsScreen extends StatefulWidget {
  const StylistsScreen({super.key, this.api, this.today});

  /// The server calls (a fake in tests).
  final SalonApi? api;

  /// What day it is (a fixed day in tests).
  final DateTime? today;

  @override
  State<StylistsScreen> createState() => _StylistsScreenState();
}

class _StylistsScreenState extends State<StylistsScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();

  _Period _period = _Period.thisMonth;
  StylistReport? _report;
  String? _error;
  bool _loading = true;

  DateTime get _today {
    final DateTime now = widget.today ?? DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  (DateTime, DateTime) get _range {
    final DateTime t = _today;
    switch (_period) {
      case _Period.thisMonth:
        return (DateTime(t.year, t.month), t);
      case _Period.lastMonth:
        return (DateTime(t.year, t.month - 1), DateTime(t.year, t.month, 0));
      case _Period.last7:
        return (t.subtract(const Duration(days: 6)), t);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final (DateTime from, DateTime to) = _range;
    final _Period asked = _period;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final StylistReport report = await _api.stylists(from: from, to: to);
      if (!mounted || asked != _period) return; // the person already chose another period
      setState(() {
        _report = report;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted || asked != _period) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  /// The targets of the month for each person, to set and save; the results are read again after.
  Future<void> _openTargets(final StylistReport report) async {
    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext _) => StylistTargetsSheet(api: _api, month: report.targetMonth),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return Material(
      color: ThemeConstants.primaryBlue,
      child: RefreshIndicator(
        onRefresh: _load,
        backgroundColor: Colors.white,
        color: ThemeConstants.primaryBlue,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
          children: <Widget>[
            InvFilterChips<_Period>(
              value: _period,
              options: <_Period, String>{
                _Period.thisMonth: sw ? 'Mwezi huu' : 'This month',
                _Period.lastMonth: sw ? 'Mwezi uliopita' : 'Last month',
                _Period.last7: sw ? 'Siku 7' : 'Last 7 days',
              },
              onSelected: (_Period p) {
                if (p == _period) return;
                setState(() => _period = p);
                _load();
              },
            ),
            SizedBox(height: 12.h),
            ..._body(sw),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(bool sw) {
    if (_loading && _report == null) {
      return <Widget>[SizedBox(height: 120.h), const Center(child: CircularProgressIndicator(color: Colors.white70))];
    }
    if (_error != null && _report == null) {
      return <Widget>[
        SizedBox(height: 60.h),
        InvEmptyState(icon: Icons.error_outline, message: _error!),
        Center(
          child: TextButton(
            key: const ValueKey<String>('stylists_retry'),
            onPressed: _load,
            child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)),
          ),
        ),
      ];
    }
    final StylistReport report = _report!;
    final double top = report.stylists.fold<double>(0, (double m, StylistRow r) => r.revenue > m ? r.revenue : m);

    return <Widget>[
      Row(
        children: <Widget>[
          Expanded(child: InvStatTile(label: sw ? 'Mapato' : 'Revenue', value: tsh(report.revenue), icon: Icons.payments_outlined, accent: ThemeConstants.successGreen)),
          SizedBox(width: 8.w),
          Expanded(child: InvStatTile(label: sw ? 'Huduma' : 'Services', value: '${report.services}', icon: Icons.content_cut_rounded)),
          SizedBox(width: 8.w),
          Expanded(child: InvStatTile(label: sw ? 'Ziara' : 'Visits', value: '${report.visits}', icon: Icons.people_alt_outlined)),
        ],
      ),
      SizedBox(height: 8.h),
      Row(
        children: <Widget>[
          Expanded(child: InvStatTile(label: sw ? 'Wastani kwa ziara' : 'Avg per visit', value: tsh(report.avgTicket), icon: Icons.receipt_long_outlined, accent: ThemeConstants.invAccent)),
          if (report.commission > 0) ...<Widget>[
            SizedBox(width: 8.w),
            Expanded(child: InvStatTile(label: sw ? 'Kamisheni ya wahudumu' : 'Stylists\' commission', value: tsh(report.commission), icon: Icons.percent_rounded, accent: ThemeConstants.warningAmber)),
          ],
        ],
      ),
      if (report.previousFrom != null && report.previousTo != null) ...<Widget>[
        SizedBox(height: 8.h),
        _CompareLine(report: report, sw: sw),
      ],
      if (report.canSetTargets) ...<Widget>[
        SizedBox(height: 8.h),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey<String>('stylists_targets'),
            onPressed: () => _openTargets(report),
            icon: Icon(Icons.flag_outlined, size: 18.sp, color: Colors.white),
            label: Text(sw ? 'Weka malengo ya mwezi' : 'Set monthly targets', style: const TextStyle(color: Colors.white)),
          ),
        ),
      ],
      SizedBox(height: 12.h),
      if (report.stylists.isEmpty)
        InvEmptyState(
          icon: Icons.content_cut_rounded,
          message: sw
              ? 'Hakuna huduma zilizorekodiwa kwa kipindi hiki. Chagua mhudumu kila unapouza huduma.'
              : 'No services recorded for this period. Choose a stylist each time you sell a service.',
        )
      else
        GlowListCard(
          dividerKey: 'stylist_divider',
          children: <Widget>[
        for (int i = 0; i < report.stylists.length; i++)
          _StylistCard(
            rank: i + 1,
            row: report.stylists[i],
            share: top <= 0 ? 0 : report.stylists[i].revenue / top,
            showMedal: report.seesEveryone,
            sw: sw,
            // The services behind the total, for the period the report covers.
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => StylistDetailScreen(
                  api: _api,
                  title: report.stylists[i].isUnassigned || report.stylists[i].name.trim().isEmpty ? (sw ? 'Hakutajwa mhudumu' : 'No stylist named') : report.stylists[i].name,
                  staffId: report.stylists[i].staffId,
                  from: report.from,
                  to: report.to,
                ),
              ),
            ),
          ),
          ],
        ),
    ];
  }
}

/// 1, 2 and 3 get gold, silver and bronze.
Color _medal(final int rank) => switch (rank) {
      1 => const Color(0xFFF5B301),
      2 => const Color(0xFF9AA5B1),
      _ => const Color(0xFFCD7F32),
    };

/// 47.0 as 47 and 47.5 as 47.5.
String _pct(final double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// "up 12.5%" (green) or "down 8%" (red) against the period just before; "new" when there was nothing before to compare with.
class ChangeChip extends StatelessWidget {
  const ChangeChip({super.key, required this.percent, required this.sw});

  final double? percent;
  final bool sw;

  @override
  Widget build(BuildContext context) {
    final double? p = percent;
    final bool up = p != null && p > 0;
    final bool flat = p != null && p == 0;
    final Color color = p == null || flat ? Colors.white60 : (up ? ThemeConstants.successGreen : ThemeConstants.errorText);
    final String text = p == null ? (sw ? 'mpya' : 'new') : flat ? '0%' : '${up ? '+' : '-'}${_pct(p.abs())}%';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10.r)),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (p != null && !flat) Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12.sp, color: color),
        Text(text, style: TextStyle(color: color, fontSize: 11.sp, fontWeight: FontWeight.w800)),
        SizedBox(width: 4.w),
        Text(sw ? 'dhidi ya kabla' : 'vs before', style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 10.sp)),
      ]),
    );
  }
}

/// The target for the month as a bar: what has been brought in, the percent of the target, and whether that is ahead of the days gone.
class TargetBar extends StatelessWidget {
  const TargetBar({super.key, required this.target, required this.sw});

  final StylistTarget target;
  final bool sw;

  @override
  Widget build(BuildContext context) {
    final (String, Color) pace = switch (target.pace) {
      'reached' => (sw ? 'Lengo limefikiwa' : 'Target reached', ThemeConstants.successGreen),
      'ahead' => (sw ? 'Mbele ya kasi' : 'Ahead of pace', ThemeConstants.successGreen),
      'on_track' => (sw ? 'Kwenye njia' : 'On track', ThemeConstants.warningAmber),
      _ => (sw ? 'Nyuma ya kasi' : 'Behind pace', ThemeConstants.errorText),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(children: <Widget>[
          Icon(Icons.flag_outlined, size: 14.sp, color: pace.$2),
          SizedBox(width: 4.w),
          Expanded(child: Text('${sw ? 'Lengo' : 'Target'} ${tsh(target.amount)}', style: ThemeConstants.captionStyle)),
          Text('${_pct(target.percent)}%', key: const ValueKey<String>('target_percent'), style: TextStyle(color: pace.$2, fontWeight: FontWeight.w800, fontSize: 12.sp)),
        ]),
        SizedBox(height: 4.h),
        Stack(children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(6.r),
            child: LinearProgressIndicator(value: (target.percent / 100).clamp(0, 1).toDouble(), minHeight: 8.h, backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation<Color>(pace.$2)),
          ),
          // Where the month stands: the share of its days that have gone.
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (target.expectedPercent / 100).clamp(0, 1).toDouble(),
              child: Align(alignment: Alignment.centerRight, child: Container(key: const ValueKey<String>('target_pace_mark'), width: 2, color: Colors.white)),
            ),
          ),
        ]),
        SizedBox(height: 2.h),
        Text(pace.$1, key: const ValueKey<String>('target_pace'), style: TextStyle(color: pace.$2, fontSize: 10.5.sp, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// "Compared with 12/10 - 31/10: up 5%": what the revenue and visits did against the period just before.
class _CompareLine extends StatelessWidget {
  const _CompareLine({required this.report, required this.sw});

  final StylistReport report;
  final bool sw;

  String _d(final DateTime d) => '${d.day}/${d.month}';

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('stylists_compare'),
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12.r)),
      child: Row(children: <Widget>[
        Expanded(
          child: Text(
            '${sw ? 'Ikilinganishwa na' : 'Compared with'} ${_d(report.previousFrom!)} - ${_d(report.previousTo!)}: ${tsh(report.previousRevenue)}',
            style: ThemeConstants.captionStyle,
          ),
        ),
        ChangeChip(key: const ValueKey<String>('stylists_total_change'), percent: report.revenueChange, sw: sw),
      ]),
    );
  }
}

class _StylistCard extends StatelessWidget {
  const _StylistCard({required this.rank, required this.row, required this.share, required this.sw, required this.onTap, this.showMedal = false});

  final int rank;

  /// The medals of the first three places are for a list of everyone, not for one person's own line.
  final bool showMedal;
  final StylistRow row;
  final double share;
  final bool sw;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String name = row.isUnassigned || row.name.trim().isEmpty ? (sw ? 'Hakutajwa mhudumu' : 'No stylist named') : row.name;

    return InkWell(
      onTap: onTap,
      child: KeyedSubtree(
      key: ValueKey<String>('stylist_${row.staffId ?? 'none'}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (showMedal && row.rank != null && row.rank! <= 3)
                Container(
                  key: ValueKey<String>('medal_${row.staffId}'),
                  width: 28.r,
                  height: 28.r,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _medal(row.rank!)),
                  child: Icon(Icons.emoji_events_rounded, size: 17.sp, color: Colors.white),
                )
              else
                CircleAvatar(
                  radius: 14.r,
                  backgroundColor: rank == 1 && !row.isUnassigned ? ThemeConstants.warningAmber : Colors.white24,
                  child: Text('$rank', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.sp)),
                ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
              ),
              SizedBox(width: 8.w),
              Text(tsh(row.revenue), style: TextStyle(color: ThemeConstants.invAccent, fontWeight: FontWeight.w800, fontSize: 14.sp)),
            ],
          ),
          if (row.revenueChange != null || row.previousRevenue > 0)
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Align(alignment: Alignment.centerRight, child: ChangeChip(key: ValueKey<String>('change_${row.staffId ?? 'none'}'), percent: row.revenueChange, sw: sw)),
            ),
          SizedBox(height: 8.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(6.r),
            child: LinearProgressIndicator(
              value: share.clamp(0, 1).toDouble(),
              minHeight: 6.h,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(ThemeConstants.invAccent),
            ),
          ),
          SizedBox(height: 8.h),
          InvKeyValueWrap(entries: <String, String>{
            sw ? 'Huduma' : 'Services': '${row.services}',
            sw ? 'Ziara' : 'Visits': '${row.visits}',
            sw ? 'Wateja' : 'Clients': '${row.clients}',
            if (row.visits > 0) sw ? 'Wastani kwa ziara' : 'Avg per visit': tsh(row.avgTicket),
            if (row.returnRate != null) sw ? 'Waliorudi' : 'Came back': '${_pct(row.returnRate!)}%',
            if (row.share > 0 && showMedal) sw ? 'Sehemu ya mapato' : 'Share': '${_pct(row.share)}%',
            if (row.discount > 0) sw ? 'Punguzo' : 'Discount': tsh(row.discount),
            if (row.commission > 0) sw ? 'Kamisheni' : 'Commission': tsh(row.commission),
          }),
          if (row.target != null) ...<Widget>[
            SizedBox(height: 8.h),
            TargetBar(key: ValueKey<String>('target_${row.staffId}'), target: row.target!, sw: sw),
          ],
        ],
      ),
      ),
    );
  }
}
