import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/api_service.dart';
import '../../../../services/localization_service.dart';
import '../../models/salon_models.dart';
import '../../services/salon_api.dart';
import 'salon_text.dart';
import 'services_report_screen.dart';
import 'stylists_screen.dart';

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
          if (ApiService.activeBranchName != null)
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Text(sw ? 'Tawi: ${ApiService.activeBranchName}' : 'Branch: ${ApiService.activeBranchName}', key: const ValueKey<String>('overview_branch'), style: ThemeConstants.captionStyle),
            ),
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
          SizedBox(height: 12.h),
          // The day in four numbers: two rows of two, each with its picture and its name.
          Row(children: <Widget>[
            Expanded(child: _fact(Icons.event_available_outlined, '${d.bookingsToday}', sw ? 'Miadi ya leo' : 'Bookings today', 'ov_bookings_today')),
            SizedBox(width: 8.w),
            Expanded(child: _fact(Icons.event_note_outlined, '${d.bookingsUpcoming}', sw ? 'Zinazokuja' : 'Coming up', 'ov_bookings_upcoming')),
          ]),
          SizedBox(height: 8.h),
          Row(children: <Widget>[
            Expanded(child: _fact(Icons.people_alt_outlined, '${d.month.clients}', sw ? 'Wateja wa mwezi' : 'Clients this month', 'ov_clients')),
            SizedBox(width: 8.w),
            Expanded(
              child: d.outstanding > 0
                  ? _fact(Icons.hourglass_bottom_rounded, tsh(d.outstanding), sw ? 'Madeni' : 'Owed', 'ov_outstanding', color: ThemeConstants.warningAmber)
                  : _fact(Icons.verified_outlined, sw ? 'Hakuna' : 'None', sw ? 'Madeni' : 'Owed', 'ov_no_debt', color: ThemeConstants.successGreen),
            ),
          ]),
          if (d.topStaff.isNotEmpty) ...<Widget>[
            _heading(Icons.emoji_events_outlined, sw ? 'Wahudumu 3 bora mwezi huu' : 'Top 3 stylists this month'),
            // The best three; the rest, with every service and client behind each total, is one tap away.
            for (int i = 0; i < _top && i < d.topStaff.length; i++)
              _ranked('ov_staff_$i', i + 1, d.topStaff[i].name.trim().isEmpty ? (sw ? 'Hakutajwa' : 'No stylist named') : d.topStaff[i].name, d.topStaff[i].revenue, d.topStaff.first.revenue,
                  muted: d.topStaff[i].name.trim().isEmpty),
            if (d.topStaff.length > _top)
              _more('ov_staff_more', sw ? 'Zaidi' : 'More', () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => ThemeConstants.buildScaffold(title: sw ? 'Wahudumu' : 'Stylists', body: StylistsScreen(api: _api))))),
          ],
          if (d.topServices.isNotEmpty) ...<Widget>[
            _heading(Icons.content_cut_rounded, sw ? 'Huduma 3 zinazouza zaidi' : 'Best 3 selling services'),
            for (int i = 0; i < _top && i < d.topServices.length; i++)
              _ranked('ov_service_$i', i + 1, d.topServices[i].name, d.topServices[i].revenue, d.topServices.first.revenue, times: d.topServices[i].times),
            if (d.topServices.length > _top)
              _more('ov_service_more', sw ? 'Zaidi' : 'More', () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => ServicesReportScreen(api: _api)))),
          ],
          if (d.collections.isNotEmpty) ...<Widget>[
            _heading(Icons.account_balance_wallet_outlined, sw ? 'Pesa zilizopokelewa mwezi huu' : 'Money received this month'),
            Row(
              children: <Widget>[
                for (int i = 0; i < d.collections.length; i++) ...<Widget>[
                  if (i > 0) SizedBox(width: 8.w),
                  Expanded(child: _collection(d.collections[i], sw)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// How many of a league table the dashboard shows; the rest is behind the More button.
  static const int _top = 3;

  /// "More >" under a league table: opens the page with everything.
  Widget _more(final String key, final String label, final VoidCallback onTap) => Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: ValueKey<String>(key),
          onPressed: onTap,
          icon: const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white),
          iconAlignment: IconAlignment.end,
          label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          style: TextButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.10),
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r), side: const BorderSide(color: Colors.white24)),
          ),
        ),
      );

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
            style: ThemeConstants.captionStyle.copyWith(color: profit ? ThemeConstants.successGreen : ThemeConstants.errorText),
          ),
        ],
      ),
    );
  }

  /// A number with its picture and its name, in a soft tile of its own.
  Widget _fact(final IconData icon, final String value, final String label, final String key, {final Color? color}) => Container(
        key: ValueKey<String>(key),
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        decoration: BoxDecoration(color: (color ?? Colors.white).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12.r)),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20.sp, color: color ?? Colors.white70),
            SizedBox(width: 8.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color ?? Colors.white, fontWeight: FontWeight.w800, fontSize: 15.sp)),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.captionStyle.copyWith(fontSize: 11.sp)),
                ],
              ),
            ),
          ],
        ),
      );

  /// A section title with its picture, with room above it, so the page reads as separate blocks.
  Widget _heading(final IconData icon, final String text) => Padding(
        padding: EdgeInsets.only(top: 16.h, bottom: 6.h),
        child: Row(children: <Widget>[
          Icon(icon, size: 16.sp, color: ThemeConstants.invAccent),
          SizedBox(width: 6.w),
          Expanded(child: Text(text, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700, fontSize: 13.sp))),
        ]),
      );

  /// One line of a league table: its place, its name, what it brought in, and a bar showing how it compares with the best.
  Widget _ranked(final String key, final int place, final String name, final double amount, final double best, {final int? times, final bool muted = false}) => Padding(
        key: ValueKey<String>(key),
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Container(
                width: 22.w,
                height: 22.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: place == 1 ? ThemeConstants.invAccent : Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Text('$place', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w800, color: place == 1 ? Colors.black87 : Colors.white)),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle.copyWith(color: muted ? Colors.white54 : null, fontStyle: muted ? FontStyle.italic : null)),
              ),
              if (times != null)
                Container(
                  margin: EdgeInsets.only(right: 8.w),
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 1.h),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8.r)),
                  child: Text('× $times', style: ThemeConstants.captionStyle.copyWith(color: Colors.white, fontSize: 11.sp)),
                ),
              Text(tsh(amount), style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800)),
            ]),
            SizedBox(height: 4.h),
            Padding(
              padding: EdgeInsets.only(left: 30.w),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3.r),
                child: LinearProgressIndicator(value: best <= 0 ? 0 : (amount / best).clamp(0.0, 1.0), minHeight: 4.h, backgroundColor: Colors.white10, valueColor: AlwaysStoppedAnimation<Color>(place == 1 ? ThemeConstants.invAccent : Colors.white38)),
              ),
            ),
          ],
        ),
      );

  /// How the money came in: the way it was paid with its picture, and the amount under it.
  Widget _collection(final Collection c, final bool sw) {
    final String m = c.method;
    final IconData icon = m == 'cash' ? Icons.payments_outlined : (m == 'bank_transfer' || m == 'bank' ? Icons.account_balance_outlined : Icons.smartphone_rounded);

    return Container(
      key: ValueKey<String>('ov_col_$m'),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12.r)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            Icon(icon, size: 15.sp, color: Colors.white70),
            SizedBox(width: 4.w),
            Expanded(child: Text(channelLabel(sw: sw, channel: m), maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.captionStyle.copyWith(fontSize: 11.sp))),
          ]),
          SizedBox(height: 2.h),
          Text(tsh(c.amount), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.sp)),
        ],
      ),
    );
  }
}
