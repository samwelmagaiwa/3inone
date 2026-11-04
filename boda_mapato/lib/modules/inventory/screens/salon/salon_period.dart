import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../constants/theme_constants.dart';
import '../widgets/glow_list_card.dart';

/// The periods a salon report can be looked at for, the same on every page that offers them: a day (today or yesterday), a week (this one, last
/// one, or the last seven days), a month, the year so far, or any days the person picks (a day, a week, a month, a year, or two dates).
enum SalonPeriod { today, yesterday, last7, thisWeek, lastWeek, thisMonth, lastMonth, thisYear, custom }

/// What the person chose: one of the usual periods, or (for [SalonPeriod.custom]) the exact days.
class SalonPeriodChoice {
  const SalonPeriodChoice(this.period, [this.custom]);

  final SalonPeriod period;
  final DateTimeRange? custom;
}

DateTime _day(final DateTime d) => DateTime(d.year, d.month, d.day);

/// The first and last day of [period] as of [today] (weeks run Monday to Sunday). [custom] is the range the person picked, used for
/// [SalonPeriod.custom]; without one it is the last seven days.
(DateTime, DateTime) salonRange(final SalonPeriod period, final DateTime today, {final DateTimeRange? custom}) {
  final DateTime t = _day(today);
  final DateTime monday = t.subtract(Duration(days: t.weekday - 1));
  switch (period) {
    case SalonPeriod.today:
      return (t, t);
    case SalonPeriod.yesterday:
      final DateTime y = t.subtract(const Duration(days: 1));
      return (y, y);
    case SalonPeriod.last7:
      return (t.subtract(const Duration(days: 6)), t);
    case SalonPeriod.thisWeek:
      return (monday, t);
    case SalonPeriod.lastWeek:
      return (monday.subtract(const Duration(days: 7)), monday.subtract(const Duration(days: 1)));
    case SalonPeriod.thisMonth:
      return (DateTime(t.year, t.month), t);
    case SalonPeriod.lastMonth:
      return (DateTime(t.year, t.month - 1), DateTime(t.year, t.month, 0));
    case SalonPeriod.thisYear:
      return (DateTime(t.year), t);
    case SalonPeriod.custom:
      if (custom == null) return (t.subtract(const Duration(days: 6)), t);

      return (_day(custom.start), _day(custom.end));
  }
}

const List<String> _monthsEn = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const List<String> _monthsSw = <String>['Januari', 'Februari', 'Machi', 'Aprili', 'Mei', 'Juni', 'Julai', 'Agosti', 'Septemba', 'Oktoba', 'Novemba', 'Desemba'];

/// "October" or "Oktoba" for month 1-12.
String salonMonthName(final int month, final bool sw) => (sw ? _monthsSw : _monthsEn)[(month - 1).clamp(0, 11)];

String _dmy(final DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// The days picked, in words a person can read: "October 2026" for a whole month, "2026" for a whole year, a week as its two days, else the two dates.
String salonRangeLabel(final DateTimeRange r, final DateTime today, {required final bool sw}) {
  final DateTime a = _day(r.start);
  final DateTime b = _day(r.end);
  final DateTime t = _day(today);
  if (a == b) return _dmy(a);
  // The end of a month or a year that has not finished yet is today.
  final bool monthEnd = b == DateTime(a.year, a.month + 1, 0) || (b == t && b.year == a.year && b.month == a.month);
  if (a.day == 1 && monthEnd && a.year == b.year && a.month == b.month) return '${salonMonthName(a.month, sw)} ${a.year}';
  final bool yearEnd = b == DateTime(a.year, 12, 31) || (b == t && b.year == a.year);
  if (a.month == 1 && a.day == 1 && yearEnd && a.year == b.year) return '${a.year}';

  return '${_dmy(a)} – ${_dmy(b)}';
}

/// The words for the usual periods.
String salonPeriodName(final SalonPeriod p, {required final bool sw}) => switch (p) {
      SalonPeriod.today => sw ? 'Leo' : 'Today',
      SalonPeriod.yesterday => sw ? 'Jana' : 'Yesterday',
      SalonPeriod.last7 => sw ? 'Siku 7' : 'Last 7 days',
      SalonPeriod.thisWeek => sw ? 'Wiki hii' : 'This week',
      SalonPeriod.lastWeek => sw ? 'Wiki iliyopita' : 'Last week',
      SalonPeriod.thisMonth => sw ? 'Mwezi huu' : 'This month',
      SalonPeriod.lastMonth => sw ? 'Mwezi uliopita' : 'Last month',
      SalonPeriod.thisYear => sw ? 'Mwaka huu' : 'This year',
      SalonPeriod.custom => sw ? 'Chagua tarehe' : 'Pick dates',
    };

/// What the period button says: the usual period's name, or the days picked.
String salonPeriodLabel(final SalonPeriod p, final DateTimeRange? custom, final DateTime today, {required final bool sw}) =>
    p == SalonPeriod.custom && custom != null ? salonRangeLabel(custom, today, sw: sw) : salonPeriodName(p, sw: sw);

/// One button for the whole choice of days: it says which days are shown, and opens the sheet where any day, week, month, year or two dates
/// can be picked. It replaces a long row of chips on every page that looks at a period.
class SalonPeriodButton extends StatelessWidget {
  const SalonPeriodButton({super.key, required this.period, required this.custom, required this.today, required this.sw, required this.onChanged});

  final SalonPeriod period;
  final DateTimeRange? custom;
  final DateTime today;
  final bool sw;
  final ValueChanged<SalonPeriodChoice> onChanged;

  @override
  Widget build(final BuildContext context) {
    final String label = salonPeriodLabel(period, custom, today, sw: sw);

    return InkWell(
      key: const ValueKey<String>('period_button'),
      borderRadius: BorderRadius.circular(14.r),
      onTap: () async {
        final SalonPeriodChoice? got = await showSalonPeriodSheet(context, today: today, sw: sw);
        if (got != null) onChanged(got);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14.r), border: Border.all(color: ThemeConstants.invAccent.withValues(alpha: 0.6))),
        child: Row(children: <Widget>[
          Icon(Icons.calendar_month_rounded, color: ThemeConstants.invAccent, size: 22.sp),
          SizedBox(width: 10.w),
          Expanded(child: Text(label, key: const ValueKey<String>('period_label'), maxLines: 1, overflow: TextOverflow.ellipsis, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800))),
          Text(sw ? 'Badilisha' : 'Change', style: ThemeConstants.captionStyle),
          Icon(Icons.expand_more_rounded, color: Colors.white70, size: 22.sp),
        ]),
      ),
    );
  }
}

/// Opens the sheet; null when the person closes it without choosing.
Future<SalonPeriodChoice?> showSalonPeriodSheet(final BuildContext context, {required final DateTime today, required final bool sw}) {
  return showModalBottomSheet<SalonPeriodChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext _) => _PeriodSheet(today: _day(today), sw: sw),
  );
}

class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet({required this.today, required this.sw});

  final DateTime today;
  final bool sw;

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  static const int _yearsBack = 5;

  late DateTime _dayPick = widget.today.subtract(const Duration(days: 1));
  late DateTime _weekMonday = widget.today.subtract(Duration(days: widget.today.weekday - 1));
  late DateTime _monthFirst = DateTime(widget.today.year, widget.today.month);
  late int _year = widget.today.year;
  DateTime? _from;
  DateTime? _to;

  bool get _sw => widget.sw;
  DateTime get _today => widget.today;
  DateTime get _earliest => DateTime(_today.year - _yearsBack);
  DateTime get _thisMonday => _today.subtract(Duration(days: _today.weekday - 1));

  /// The range, never running past today.
  void _show(final DateTime start, final DateTime end) {
    final DateTime last = end.isAfter(_today) ? _today : end;
    Navigator.pop(context, SalonPeriodChoice(SalonPeriod.custom, DateTimeRange(start: start, end: last)));
  }

  Future<void> _pick(final bool from) async {
    final DateTime start = (from ? _from : _to) ?? _today;
    final DateTime? got = await showDatePicker(
      context: context,
      initialDate: start.isAfter(_today) ? _today : start,
      firstDate: _earliest,
      lastDate: _today,
      helpText: from ? (_sw ? 'Tarehe ya kuanzia' : 'From which day') : (_sw ? 'Tarehe ya mwisho' : 'Up to which day'),
      builder: (BuildContext c, Widget? child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: ThemeConstants.invAccent, onPrimary: Colors.black, surface: ThemeConstants.primaryBlue, onSurface: Colors.white),
          dialogTheme: const DialogThemeData(backgroundColor: ThemeConstants.primaryBlue),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (got == null || !mounted) return;
    setState(() {
      if (from) {
        _from = got;
        if (_to != null && _to!.isBefore(got)) _to = got;
      } else {
        _to = got;
        if (_from != null && _from!.isAfter(got)) _from = got;
      }
    });
  }

  String _short(final DateTime d) => '${d.day} ${salonMonthName(d.month, _sw).substring(0, 3)} ${d.year}';

  /// One row that steps through days, weeks, months or years: ‹ value › and a button to look at it.
  Widget _stepper({required final String keyName, required final String title, required final String value, required final bool canBack, required final bool canForward, required final VoidCallback back, required final VoidCallback forward, required final VoidCallback show}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text(title, style: ThemeConstants.captionStyle),
      SizedBox(height: 2.h),
      Row(children: <Widget>[
        IconButton(key: ValueKey<String>('${keyName}_back'), visualDensity: VisualDensity.compact, onPressed: canBack ? back : null, icon: const Icon(Icons.chevron_left_rounded)),
        Expanded(child: Text(value, key: ValueKey<String>('${keyName}_value'), textAlign: TextAlign.center, style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w800))),
        IconButton(key: ValueKey<String>('${keyName}_forward'), visualDensity: VisualDensity.compact, onPressed: canForward ? forward : null, icon: const Icon(Icons.chevron_right_rounded)),
        SizedBox(width: 6.w),
        FilledButton(key: ValueKey<String>('${keyName}_show'), onPressed: show, style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), child: Text(_sw ? 'Onyesha' : 'Show')),
      ]),
    ]);
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = _sw;
    final DateTime weekEnd = _weekMonday.add(const Duration(days: 6));
    final bool both = _from != null && _to != null;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: BoxDecoration(color: ThemeConstants.primaryBlue, borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)), border: Border.all(color: Colors.white24)),
        padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 14.h),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Center(child: Container(width: 40.w, height: 4.h, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4.r)))),
          SizedBox(height: 10.h),
          Text(sw ? 'Chagua siku' : 'Choose the days', key: const ValueKey<String>('period_title'), style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w800)),
          SizedBox(height: 10.h),
          Flexible(
            child: ListView(shrinkWrap: true, children: <Widget>[
              GlowCard(
                title: sw ? 'Za haraka' : 'Quick',
                dividerKey: 'period_quick_divider',
                children: <Widget>[
                  Wrap(spacing: 8.w, runSpacing: 6.h, children: <Widget>[
                    for (final SalonPeriod p in SalonPeriod.values.where((SalonPeriod p) => p != SalonPeriod.custom))
                      ActionChip(key: ValueKey<String>('period_${p.name}'), label: Text(salonPeriodName(p, sw: sw)), onPressed: () => Navigator.pop(context, SalonPeriodChoice(p))),
                  ]),
                ],
              ),
              GlowCard(
                title: sw ? 'Siku, wiki, mwezi au mwaka' : 'A day, week, month or year',
                dividerKey: 'period_step_divider',
                children: <Widget>[
                  _stepper(
                    keyName: 'period_day',
                    title: sw ? 'Siku moja' : 'A day',
                    value: _short(_dayPick),
                    canBack: _dayPick.isAfter(_earliest),
                    canForward: _dayPick.isBefore(_today),
                    back: () => setState(() => _dayPick = _dayPick.subtract(const Duration(days: 1))),
                    forward: () => setState(() => _dayPick = _dayPick.add(const Duration(days: 1))),
                    show: () => _show(_dayPick, _dayPick),
                  ),
                  _stepper(
                    keyName: 'period_week',
                    title: sw ? 'Wiki (Jumatatu hadi Jumapili)' : 'A week (Monday to Sunday)',
                    value: '${_weekMonday.day} ${salonMonthName(_weekMonday.month, sw).substring(0, 3)} – ${weekEnd.day} ${salonMonthName(weekEnd.month, sw).substring(0, 3)} ${weekEnd.year}',
                    canBack: _weekMonday.isAfter(_earliest),
                    canForward: _weekMonday.isBefore(_thisMonday),
                    back: () => setState(() => _weekMonday = _weekMonday.subtract(const Duration(days: 7))),
                    forward: () => setState(() => _weekMonday = _weekMonday.add(const Duration(days: 7))),
                    show: () => _show(_weekMonday, _weekMonday.add(const Duration(days: 6))),
                  ),
                  _stepper(
                    keyName: 'period_month',
                    title: sw ? 'Mwezi' : 'A month',
                    value: '${salonMonthName(_monthFirst.month, sw)} ${_monthFirst.year}',
                    canBack: _monthFirst.isAfter(_earliest),
                    canForward: _monthFirst.isBefore(DateTime(_today.year, _today.month)),
                    back: () => setState(() => _monthFirst = DateTime(_monthFirst.year, _monthFirst.month - 1)),
                    forward: () => setState(() => _monthFirst = DateTime(_monthFirst.year, _monthFirst.month + 1)),
                    show: () => _show(_monthFirst, DateTime(_monthFirst.year, _monthFirst.month + 1, 0)),
                  ),
                  _stepper(
                    keyName: 'period_year',
                    title: sw ? 'Mwaka' : 'A year',
                    value: '$_year',
                    canBack: _year > _earliest.year,
                    canForward: _year < _today.year,
                    back: () => setState(() => _year--),
                    forward: () => setState(() => _year++),
                    show: () => _show(DateTime(_year), DateTime(_year, 12, 31)),
                  ),
                ],
              ),
              GlowCard(
                title: sw ? 'Kati ya tarehe mbili' : 'Between two dates',
                dividerKey: 'period_range_divider',
                bottom: 0,
                children: <Widget>[
                  Row(children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey<String>('period_from'),
                        onPressed: () => _pick(true),
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text(_from == null ? (sw ? 'Kuanzia' : 'From') : _short(_from!), overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey<String>('period_to'),
                        onPressed: () => _pick(false),
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text(_to == null ? (sw ? 'Hadi' : 'To') : _short(_to!), overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ]),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(key: const ValueKey<String>('period_range_show'), onPressed: both ? () => _show(_from!, _to!) : null, child: Text(sw ? 'Onyesha tarehe hizi' : 'Show these dates')),
                  ),
                ],
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
