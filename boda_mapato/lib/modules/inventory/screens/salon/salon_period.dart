import 'package:flutter/material.dart';

/// The periods a salon report can be looked at for, the same on every page that offers them: a day (today or yesterday), a week (this one, last
/// one, or the last seven days), a month, the year so far, or any two days the person picks.
enum SalonPeriod { today, yesterday, last7, thisWeek, lastWeek, thisMonth, lastMonth, thisYear, custom }

/// The first and last day of [period] as of [today] (weeks run Monday to Sunday). [custom] is the range the person picked, used for
/// [SalonPeriod.custom]; without one it is the last seven days.
(DateTime, DateTime) salonRange(final SalonPeriod period, final DateTime today, {final DateTimeRange? custom}) {
  final DateTime t = DateTime(today.year, today.month, today.day);
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

      return (DateTime(custom.start.year, custom.start.month, custom.start.day), DateTime(custom.end.year, custom.end.month, custom.end.day));
  }
}

/// The chips, in the order they are shown. The last one says "Pick dates", or the two days once they are picked.
Map<SalonPeriod, String> salonPeriodOptions({required final bool sw, final DateTimeRange? custom}) {
  String d(final DateTime x) => '${x.day}/${x.month}';

  return <SalonPeriod, String>{
    SalonPeriod.today: sw ? 'Leo' : 'Today',
    SalonPeriod.yesterday: sw ? 'Jana' : 'Yesterday',
    SalonPeriod.last7: sw ? 'Siku 7' : 'Last 7 days',
    SalonPeriod.thisWeek: sw ? 'Wiki hii' : 'This week',
    SalonPeriod.lastWeek: sw ? 'Wiki iliyopita' : 'Last week',
    SalonPeriod.thisMonth: sw ? 'Mwezi huu' : 'This month',
    SalonPeriod.lastMonth: sw ? 'Mwezi uliopita' : 'Last month',
    SalonPeriod.thisYear: sw ? 'Mwaka huu' : 'This year',
    SalonPeriod.custom: custom == null ? (sw ? 'Chagua tarehe' : 'Pick dates') : '${d(custom.start)} - ${d(custom.end)}',
  };
}

/// Asks for two days: from any day in the past (not the future) up to [today]. Null when the person backs out.
Future<DateTimeRange?> pickSalonRange(final BuildContext context, final DateTime today, final DateTimeRange? current) {
  final DateTime t = DateTime(today.year, today.month, today.day);

  return showDateRangePicker(
    context: context,
    firstDate: DateTime(t.year - 5),
    lastDate: t,
    initialDateRange: current,
  );
}
