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

/// Every service the salon sold in a period: how often, what it brought in, for how many clients, and (opened with a tap)
/// each time it was done: the day, the client's name, the stylist and what it was worth. The owner and managers see all of
/// it; a stylist only the services they did themselves (the server decides that).
class ServicesReportScreen extends StatefulWidget {
  const ServicesReportScreen({super.key, this.api, this.today});

  /// The server calls (a fake in tests).
  final SalonApi? api;

  /// What day it is (a fixed day in tests).
  final DateTime? today;

  @override
  State<ServicesReportScreen> createState() => _ServicesReportScreenState();
}

class _ServicesReportScreenState extends State<ServicesReportScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();

  _Period _period = _Period.thisMonth;
  ServiceReport? _report;
  String? _error;
  bool _loading = true;
  final Set<int> _open = <int>{};

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
      final ServiceReport report = await _api.serviceSales(from: from, to: to);
      if (!mounted || asked != _period) return; // the person already chose another period
      setState(() {
        _report = report;
        _loading = false;
        _open.clear();
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

    return ThemeConstants.buildScaffold(
      title: sw ? 'Huduma zinazouza' : 'Services sold',
      body: RefreshIndicator(
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
            key: const ValueKey<String>('services_retry'),
            onPressed: _load,
            child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white)),
          ),
        ),
      ];
    }
    final ServiceReport report = _report!;
    final double top = report.services.fold<double>(0, (double m, ServiceRow r) => r.revenue > m ? r.revenue : m);

    return <Widget>[
      Text('${dayLabel(report.from)} – ${dayLabel(report.to)}', key: const ValueKey<String>('services_period'), style: ThemeConstants.captionStyle),
      SizedBox(height: 8.h),
      Row(
        children: <Widget>[
          Expanded(child: InvStatTile(label: sw ? 'Mapato' : 'Revenue', value: tsh(report.revenue), icon: Icons.payments_outlined, accent: ThemeConstants.successGreen)),
          SizedBox(width: 8.w),
          Expanded(child: InvStatTile(label: sw ? 'Mara zilizofanywa' : 'Times done', value: '${report.times}', icon: Icons.content_cut_rounded)),
        ],
      ),
      SizedBox(height: 12.h),
      if (report.services.isEmpty)
        InvEmptyState(icon: Icons.content_cut_rounded, message: sw ? 'Hakuna huduma zilizouzwa kwa kipindi hiki.' : 'No services were sold in this period.')
      else
        for (int i = 0; i < report.services.length; i++) ...<Widget>[
          _ServiceCard(
            rank: i + 1,
            row: report.services[i],
            share: top <= 0 ? 0 : report.services[i].revenue / top,
            open: _open.contains(report.services[i].productId),
            sw: sw,
            onTap: () => setState(() {
              final int id = report.services[i].productId;
              if (!_open.remove(id)) _open.add(id);
            }),
          ),
          SizedBox(height: 8.h),
        ],
    ];
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.rank, required this.row, required this.share, required this.open, required this.sw, required this.onTap});

  final int rank;
  final ServiceRow row;
  final double share;
  final bool open;
  final bool sw;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final String name = row.name.trim().isEmpty ? (sw ? 'Huduma' : 'Service') : row.name;

    return InkWell(
      borderRadius: BorderRadius.circular(20.r),
      onTap: onTap,
      child: Container(
        key: ValueKey<String>('service_${row.productId}'),
        decoration: ThemeConstants.glassCardDecoration,
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 14.r,
                  backgroundColor: rank == 1 ? ThemeConstants.warningAmber : Colors.white24,
                  child: Text('$rank', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.sp)),
                ),
                SizedBox(width: 10.w),
                Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700))),
                SizedBox(width: 8.w),
                Text(tsh(row.revenue), style: TextStyle(color: ThemeConstants.invAccent, fontWeight: FontWeight.w800, fontSize: 14.sp)),
                Icon(open ? Icons.expand_less : Icons.expand_more, color: Colors.white70),
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
              sw ? 'Mara' : 'Times': '${row.times}',
              sw ? 'Wateja' : 'Clients': '${row.clients}',
            }),
            if (open) ...<Widget>[
              SizedBox(height: 8.h),
              Divider(color: Colors.white24, height: 1.h),
              for (int i = 0; i < row.sales.length; i++)
                Padding(
                  key: ValueKey<String>('service_${row.productId}_line_$i'),
                  padding: EdgeInsets.symmetric(vertical: 8.h),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              row.sales[i].client ?? (sw ? 'Mteja wa kawaida (hakutajwa)' : 'Walk-in client'),
                              style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700, fontStyle: row.sales[i].client == null ? FontStyle.italic : null),
                            ),
                            Text(
                              '${dayLabel(row.sales[i].date)} ${hm(row.sales[i].date)} • ${row.sales[i].number}'
                              '${row.sales[i].stylist == null ? '' : ' • ${row.sales[i].stylist}'}',
                              style: ThemeConstants.captionStyle,
                            ),
                          ],
                        ),
                      ),
                      Text(row.sales[i].qty > 1 ? '× ${row.sales[i].qty}   ${tsh(row.sales[i].net)}' : tsh(row.sales[i].net), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
            ] else
              Padding(
                padding: EdgeInsets.only(top: 6.h),
                child: Text(sw ? 'Gusa kuona wateja waliohudumiwa' : 'Tap to see the clients it was done for', style: ThemeConstants.captionStyle.copyWith(fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      ),
    );
  }
}
