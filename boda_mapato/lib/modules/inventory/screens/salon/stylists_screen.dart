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
      SizedBox(height: 12.h),
      if (report.stylists.isEmpty)
        InvEmptyState(
          icon: Icons.content_cut_rounded,
          message: sw
              ? 'Hakuna huduma zilizorekodiwa kwa kipindi hiki. Chagua mhudumu kila unapouza huduma.'
              : 'No services recorded for this period. Choose a stylist each time you sell a service.',
        )
      else
        for (int i = 0; i < report.stylists.length; i++) ...<Widget>[
          _StylistCard(rank: i + 1, row: report.stylists[i], share: top <= 0 ? 0 : report.stylists[i].revenue / top, sw: sw),
          SizedBox(height: 8.h),
        ],
    ];
  }
}

class _StylistCard extends StatelessWidget {
  const _StylistCard({required this.rank, required this.row, required this.share, required this.sw});

  final int rank;
  final StylistRow row;
  final double share;
  final bool sw;

  @override
  Widget build(BuildContext context) {
    final String name = row.isUnassigned || row.name.trim().isEmpty ? (sw ? 'Hakutajwa mhudumu' : 'No stylist named') : row.name;

    return Container(
      key: ValueKey<String>('stylist_${row.staffId ?? 'none'}'),
      decoration: ThemeConstants.glassCardDecoration,
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
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
          }),
        ],
      ),
    );
  }
}
