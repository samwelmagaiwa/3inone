import "package:intl/intl.dart";
import '../services/localization_service.dart';

mixin AppDateUtils {
  // Date formatters
  static final DateFormat _dateFormatter = DateFormat("dd/MM/yyyy");
  static final DateFormat _timeFormatter = DateFormat("HH:mm");
  static final DateFormat _dateTimeFormatter = DateFormat("dd/MM/yyyy HH:mm");
  static final DateFormat _monthYearFormatter = DateFormat("MMMM yyyy");
  static final DateFormat _dayMonthFormatter = DateFormat("dd MMM");
  static final DateFormat _fullDateFormatter = DateFormat("EEEE, dd MMMM yyyy");

  // Format date only
  static String formatDate(final DateTime date) => _dateFormatter.format(date);

  // Format time only
  static String formatTime(final DateTime date) => _timeFormatter.format(date);

  // Format date and time
  static String formatDateTime(final DateTime date) =>
      _dateTimeFormatter.format(date);

  // Format month and year
  static String formatMonthYear(final DateTime date) =>
      _monthYearFormatter.format(date);

  // Format day and month
  static String formatDayMonth(final DateTime date) =>
      _dayMonthFormatter.format(date);

  // Format full date
  static String formatFullDate(final DateTime date) =>
      _fullDateFormatter.format(date);

  // Get relative time (e.g., "2 hours ago", "Yesterday")
  static String getRelativeTime(final DateTime date) {
    final DateTime now = DateTime.now();
    final Duration difference = now.difference(date);

    if (difference.inDays > 365) {
      final int years = (difference.inDays / 365).floor();
      return years == 1 ? LocalizationService.instance.translate('one_year_ago') : LocalizationService.instance.translateWith('years_ago', <Object?>[years]);
    } else if (difference.inDays > 30) {
      final int months = (difference.inDays / 30).floor();
      return months == 1 ? LocalizationService.instance.translate('one_month_ago') : LocalizationService.instance.translateWith('months_ago', <Object?>[months]);
    } else if (difference.inDays > 7) {
      final int weeks = (difference.inDays / 7).floor();
      return weeks == 1 ? LocalizationService.instance.translate('one_week_ago') : LocalizationService.instance.translateWith('weeks_ago', <Object?>[weeks]);
    } else if (difference.inDays > 0) {
      return difference.inDays == 1
          ? LocalizationService.instance.translate('yesterday')
          : LocalizationService.instance.translateWith('days_ago', <Object?>[difference.inDays]);
    } else if (difference.inHours > 0) {
      return difference.inHours == 1
          ? LocalizationService.instance.translate('one_hour_ago')
          : LocalizationService.instance.translateWith('hours_ago', <Object?>[difference.inHours]);
    } else if (difference.inMinutes > 0) {
      return difference.inMinutes == 1
          ? LocalizationService.instance.translate('one_minute_ago')
          : LocalizationService.instance.translateWith('minutes_ago', <Object?>[difference.inMinutes]);
    } else {
      return LocalizationService.instance.translate('just_now');
    }
  }

  // Check if date is today
  static bool isToday(final DateTime date) {
    final DateTime now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  // Check if date is yesterday
  static bool isYesterday(final DateTime date) {
    final DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
    return date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day;
  }

  // Check if date is this week
  static bool isThisWeek(final DateTime date) {
    final DateTime now = DateTime.now();
    final DateTime startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final DateTime endOfWeek = startOfWeek.add(const Duration(days: 6));

    return date.isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
        date.isBefore(endOfWeek.add(const Duration(days: 1)));
  }

  // Check if date is this month
  static bool isThisMonth(final DateTime date) {
    final DateTime now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  // Check if date is this year
  static bool isThisYear(final DateTime date) {
    final DateTime now = DateTime.now();
    return date.year == now.year;
  }

  // Get start of day
  static DateTime startOfDay(final DateTime date) =>
      DateTime(date.year, date.month, date.day);

  // Get end of day
  static DateTime endOfDay(final DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  // Get start of week (Monday)
  static DateTime startOfWeek(final DateTime date) {
    final int daysFromMonday = date.weekday - 1;
    return startOfDay(date.subtract(Duration(days: daysFromMonday)));
  }

  // Get end of week (Sunday)
  static DateTime endOfWeek(final DateTime date) {
    final int daysToSunday = 7 - date.weekday;
    return endOfDay(date.add(Duration(days: daysToSunday)));
  }

  // Get start of month
  static DateTime startOfMonth(final DateTime date) =>
      DateTime(date.year, date.month);

  // Get end of month
  static DateTime endOfMonth(final DateTime date) {
    final DateTime nextMonth = date.month == 12
        ? DateTime(date.year + 1)
        : DateTime(date.year, date.month + 1);
    return nextMonth.subtract(const Duration(days: 1));
  }

  // Get start of year
  static DateTime startOfYear(final DateTime date) => DateTime(date.year);

  // Get end of year
  static DateTime endOfYear(final DateTime date) =>
      DateTime(date.year, 12, 31, 23, 59, 59, 999);

  // Get days in month
  static int getDaysInMonth(final int year, final int month) =>
      DateTime(year, month + 1, 0).day;

  // Get week number of year
  static int getWeekOfYear(final DateTime date) {
    final DateTime startOfYear = DateTime(date.year);
    final int days = date.difference(startOfYear).inDays;
    return ((days - date.weekday + 10) / 7).floor();
  }

  // Parse date string
  static DateTime? parseDate(final String dateString) {
    try {
      return _dateFormatter.parse(dateString);
    } on Exception {
      return null;
    }
  }

  // Parse time string
  static DateTime? parseTime(final String timeString) {
    try {
      final DateTime now = DateTime.now();
      final DateTime time = _timeFormatter.parse(timeString);
      return DateTime(now.year, now.month, now.day, time.hour, time.minute);
    } on Exception {
      return null;
    }
  }

  // Parse date time string
  static DateTime? parseDateTime(final String dateTimeString) {
    try {
      return _dateTimeFormatter.parse(dateTimeString);
    } on Exception {
      return null;
    }
  }

  // Get age from birth date
  static int getAge(final DateTime birthDate) {
    final DateTime now = DateTime.now();
    int age = now.year - birthDate.year;

    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }

    return age;
  }

  // Get time difference in human readable format
  static String getTimeDifference(final DateTime start, final DateTime end) {
    final Duration difference = end.difference(start);

    if (difference.inDays > 0) {
      return LocalizationService.instance.translateWith('days_2', <Object?>[difference.inDays]);
    } else if (difference.inHours > 0) {
      return LocalizationService.instance.translateWith('hours', <Object?>[difference.inHours]);
    } else if (difference.inMinutes > 0) {
      return LocalizationService.instance.translateWith('minutes', <Object?>[difference.inMinutes]);
    } else {
      return LocalizationService.instance.translateWith('seconds', <Object?>[difference.inSeconds]);
    }
  }

  // Check if date is in range
  static bool isDateInRange(
    final DateTime date,
    final DateTime start,
    final DateTime end,
  ) =>
      date.isAfter(start.subtract(const Duration(days: 1))) &&
      date.isBefore(end.add(const Duration(days: 1)));

  // Get next occurrence of weekday
  static DateTime getNextWeekday(final DateTime date, final int weekday) {
    final int daysUntilWeekday = (weekday - date.weekday) % 7;
    return date
        .add(Duration(days: daysUntilWeekday == 0 ? 7 : daysUntilWeekday));
  }

  // Get previous occurrence of weekday
  static DateTime getPreviousWeekday(final DateTime date, final int weekday) {
    final int daysSinceWeekday = (date.weekday - weekday) % 7;
    return date
        .subtract(Duration(days: daysSinceWeekday == 0 ? 7 : daysSinceWeekday));
  }

  // Format duration
  static String formatDuration(final Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return "${hours}h ${minutes}m";
    } else {
      return "${minutes}m";
    }
  }

  // Get business days between dates (excluding weekends)
  static int getBusinessDays(final DateTime start, final DateTime end) {
    int businessDays = 0;
    DateTime current = start;

    while (current.isBefore(end) || current.isAtSameMomentAs(end)) {
      if (current.weekday < 6) {
        // Monday = 1, Friday = 5
        businessDays++;
      }
      current = current.add(const Duration(days: 1));
    }

    return businessDays;
  }
}
