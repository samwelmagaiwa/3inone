/// The few sentences the salon screens build from numbers. Swahili agrees with the number ("wiki moja", "wiki 4";
/// "iliyopita" for one, "zilizopita" for more), and so does English ("one week", "4 weeks"): one place, tested.
library;

/// "wiki moja" / "wiki 4"  ·  "one week" / "4 weeks".
String weeksLabel({required final bool sw, required final int weeks}) =>
    sw ? (weeks == 1 ? 'wiki moja' : 'wiki $weeks') : (weeks == 1 ? 'one week' : '$weeks weeks');

/// How long ago something was: "Wiki moja iliyopita" / "Wiki 4 zilizopita"  ·  "One week ago" / "4 weeks ago".
String weeksAgo({required final bool sw, required final int weeks}) {
  if (weeks <= 0) return sw ? 'Wiki hii' : 'This week';
  return sw ? (weeks == 1 ? 'Wiki moja iliyopita' : 'Wiki $weeks zilizopita') : (weeks == 1 ? 'One week ago' : '$weeks weeks ago');
}

/// 5 Nov 2026 -> "05/11/2026", the way dates are written everywhere else in the app.
String dayLabel(final DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';

/// Money as the inventory shows it: "TSH 45,000".
String tsh(final num amount) {
  final String digits = amount.round().abs().toString();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return 'TSH ${amount < 0 ? '-' : ''}$out';
}

/// How a payment was made, as people say it: "M-Pesa", "Mixx by Yas", "Cash" / "Taslimu".
String channelLabel({required final bool sw, required final String channel}) {
  switch (channel) {
    case 'cash':
      return sw ? 'Taslimu' : 'Cash';
    case 'mpesa':
      return 'M-Pesa';
    case 'mixx':
      return 'Mixx by Yas';
    case 'airtel_money':
      return 'Airtel Money';
    case 'halopesa':
      return 'HaloPesa';
    case 'mobile_money':
      return sw ? 'Pesa za simu' : 'Mobile money';
    case 'bank_transfer':
      return sw ? 'Benki' : 'Bank';
    default:
      return channel;
  }
}

/// The kinds of spending a salon records, as the owner says them.
String expenseCategoryLabel({required final bool sw, required final String category}) {
  switch (category) {
    case 'rent':
      return sw ? 'Kodi ya fremu' : 'Rent';
    case 'salaries':
      return sw ? 'Mishahara na posho' : 'Salaries and allowances';
    case 'supplies':
      return sw ? 'Bidhaa na vifaa' : 'Products and supplies';
    case 'utilities':
      return sw ? 'Umeme, maji na intaneti' : 'Electricity, water, internet';
    case 'transport':
      return sw ? 'Usafiri na delivery' : 'Transport and delivery';
    case 'maintenance':
      return sw ? 'Matengenezo ya vifaa' : 'Repairs and maintenance';
    case 'marketing':
      return sw ? 'Matangazo' : 'Marketing';
    case 'licences':
      return sw ? 'Leseni na ada' : 'Licences and fees';
    case 'other':
      return sw ? 'Nyingine' : 'Other';
    default:
      return category;
  }
}

/// The order they are offered in.
const List<String> expenseCategories = <String>['rent', 'salaries', 'supplies', 'utilities', 'transport', 'maintenance', 'marketing', 'licences', 'other'];

/// "2026-10" -> "October 2026" / "Oktoba 2026".
String monthLabel({required final bool sw, required final String month}) {
  final List<String> parts = month.split('-');
  final int? y = parts.length == 2 ? int.tryParse(parts[0]) : null;
  final int? m = parts.length == 2 ? int.tryParse(parts[1]) : null;
  if (y == null || m == null || m < 1 || m > 12) return month;
  const List<String> en = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const List<String> swa = <String>['Januari', 'Februari', 'Machi', 'Aprili', 'Mei', 'Juni', 'Julai', 'Agosti', 'Septemba', 'Oktoba', 'Novemba', 'Desemba'];
  return '${(sw ? swa : en)[m - 1]} $y';
}

/// The month before / after "YYYY-MM".
String shiftMonth(final String month, final int by) {
  final List<String> p = month.split('-');
  final DateTime d = DateTime(int.parse(p[0]), int.parse(p[1]) + by);
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
}
