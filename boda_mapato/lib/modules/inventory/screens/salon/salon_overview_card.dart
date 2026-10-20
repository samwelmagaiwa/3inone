import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/salon_models.dart';
import '../../services/salon_api.dart';
import 'salon_text.dart';

/// The salon's dashboard at a glance, for the owner and managers: what came in today, this week, this month and this
/// year (with the profit under each), today's and coming bookings, who earned the most, what sells best, how the money
/// came in and what clients still owe. It sits inside the dashboard's own card and says nothing when it cannot load:
/// the dashboard below it still works.
class SalonOverviewCard extends StatefulWidget {
  const SalonOverviewCard({super.key, this.api});

  /// The server calls (a fake in tests).
  final SalonApi? api;

  @override
  State<SalonOverviewCard> createState() => _SalonOverviewCardState();
}

class _SalonOverviewCardState extends State<SalonOverviewCard> {
  late final SalonApi _api = widget.api ?? SalonApi();

  SalonOverview? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final SalonOverview d = await _api.overview();
      if (mounted) {
        setState(() {
          _data = d;
          _failed = false;
        });
      }
    } on Exception {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final SalonOverview? d = _data;

    if (d == null) {
      return _failed
          ? Padding(
              padding: EdgeInsets.all(12.w),
              child: Row(children: <Widget>[
                Expanded(child: Text(sw ? 'Muhtasari haukupatikana.' : 'The overview could not be loaded.', style: ThemeConstants.captionStyle)),
                TextButton(key: const ValueKey<String>('overview_retry'), onPressed: _load, child: Text(sw ? 'Jaribu tena' : 'Try again', style: const TextStyle(color: Colors.white))),
              ]),
            )
          : const SizedBox.shrink();
    }

    return Padding(
      key: const ValueKey<String>('salon_overview'),
      padding: EdgeInsets.all(14.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(sw ? 'Muhtasari wa biashara' : 'Business overview', style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800)),
          SizedBox(height: 10.h),
          Row(
            children: <Widget>[
              Expanded(child: _tile('today', sw ? 'Leo' : 'Today', d.today, sw)),
              SizedBox(width: 8.w),
              Expanded(child: _tile('week', sw ? 'Wiki' : 'Week', d.week, sw)),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: <Widget>[
              Expanded(child: _tile('month', sw ? 'Mwezi' : 'Month', d.month, sw)),
              SizedBox(width: 8.w),
              Expanded(child: _tile('year', sw ? 'Mwaka' : 'Year', d.year, sw)),
            ],
          ),
          SizedBox(height: 10.h),
          Wrap(
            spacing: 16.w,
            runSpacing: 4.h,
            children: <Widget>[
              _fact(Icons.event_available_outlined, sw ? 'Miadi ya leo: ${d.bookingsToday}' : 'Bookings today: ${d.bookingsToday}', 'ov_bookings_today'),
              _fact(Icons.event_note_outlined, sw ? 'Zinazokuja: ${d.bookingsUpcoming}' : 'Coming up: ${d.bookingsUpcoming}', 'ov_bookings_upcoming'),
              _fact(Icons.people_alt_outlined, sw ? 'Wateja wa mwezi: ${d.month.clients}' : 'Clients this month: ${d.month.clients}', 'ov_clients'),
              if (d.outstanding > 0) _fact(Icons.hourglass_bottom_rounded, sw ? 'Madeni: ${tsh(d.outstanding)}' : 'Owed: ${tsh(d.outstanding)}', 'ov_outstanding', color: ThemeConstants.warningAmber),
            ],
          ),
          if (d.topStaff.isNotEmpty) ...<Widget>[
            SizedBox(height: 12.h),
            Text(sw ? 'Wahudumu bora mwezi huu' : 'Top stylists this month', style: ThemeConstants.captionStyle),
            SizedBox(height: 4.h),
            for (int i = 0; i < d.topStaff.length; i++) _ranked('ov_staff_$i', '${i + 1}. ${d.topStaff[i].name.trim().isEmpty ? (sw ? 'Hakutajwa' : 'No stylist named') : d.topStaff[i].name}', d.topStaff[i].revenue),
          ],
          if (d.topServices.isNotEmpty) ...<Widget>[
            SizedBox(height: 12.h),
            Text(sw ? 'Huduma zinazouza zaidi' : 'Best-selling services', style: ThemeConstants.captionStyle),
            SizedBox(height: 4.h),
            for (int i = 0; i < d.topServices.length; i++) _ranked('ov_service_$i', '${d.topServices[i].name} × ${d.topServices[i].times}', d.topServices[i].revenue),
          ],
          if (d.collections.isNotEmpty) ...<Widget>[
            SizedBox(height: 12.h),
            Text(sw ? 'Pesa zilizopokelewa mwezi huu' : 'Money received this month', style: ThemeConstants.captionStyle),
            SizedBox(height: 4.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 4.h,
              children: <Widget>[
                for (final Collection c in d.collections)
                  Container(
                    key: ValueKey<String>('ov_col_${c.method}'),
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14.r)),
                    child: Text('${channelLabel(sw: sw, channel: c.method)} ${tsh(c.amount)}', style: ThemeConstants.captionStyle.copyWith(color: Colors.white)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile(final String key, final String label, final PeriodFigures f, final bool sw) {
    final bool profit = f.netProfit >= 0;

    return Container(
      key: ValueKey<String>('ov_$key'),
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14.r), border: Border.all(color: Colors.white12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: ThemeConstants.captionStyle),
          SizedBox(height: 2.h),
          Text(tsh(f.revenue), style: TextStyle(color: ThemeConstants.invAccent, fontWeight: FontWeight.w800, fontSize: 15.sp)),
          SizedBox(height: 2.h),
          Text(
            '${profit ? (sw ? 'Faida' : 'Profit') : (sw ? 'Hasara' : 'Loss')} ${tsh(f.netProfit)}',
            style: ThemeConstants.captionStyle.copyWith(color: profit ? ThemeConstants.successGreen : ThemeConstants.errorRed),
          ),
        ],
      ),
    );
  }

  Widget _fact(final IconData icon, final String text, final String key, {final Color? color}) => Row(
        key: ValueKey<String>(key),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16.sp, color: color ?? Colors.white70),
          SizedBox(width: 4.w),
          Text(text, style: ThemeConstants.captionStyle.copyWith(color: color ?? Colors.white)),
        ],
      );

  Widget _ranked(final String key, final String label, final double amount) => Padding(
        key: ValueKey<String>(key),
        padding: EdgeInsets.symmetric(vertical: 2.h),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle)),
            Text(tsh(amount), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
