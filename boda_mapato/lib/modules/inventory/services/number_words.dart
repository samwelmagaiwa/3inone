/// A whole number written in words, so a voice reads an amount the way a person says it (a voice that is given "430000" reads it as digits
/// or as a long number, and neither is clear). Kiswahili uses the money words Tanzanians use: laki (100,000), elfu, milioni, bilioni.
///
///  - 430000   -> "laki nne na elfu thelathini"      / "four hundred thirty thousand"
///  - 5610000  -> "milioni tano na laki sita na elfu kumi"
///  - 1000     -> "elfu moja"                         / "one thousand"
String numberInWords(final int number, {required final bool sw}) {
  if (number < 0) return (sw ? 'hasi ' : 'minus ') + numberInWords(-number, sw: sw);
  if (number == 0) return sw ? 'sifuri' : 'zero';

  return sw ? _swahili(number) : _english(number);
}

// ---------------------------------------------------------------------------------------------- Kiswahili

const List<String> _swUnits = <String>['', 'moja', 'mbili', 'tatu', 'nne', 'tano', 'sita', 'saba', 'nane', 'tisa'];
const List<String> _swTens = <String>['', 'kumi', 'ishirini', 'thelathini', 'arobaini', 'hamsini', 'sitini', 'sabini', 'themanini', 'tisini'];

/// 1 to 99: "kumi", "kumi na moja", "ishirini na tano".
String _swUnder100(final int n) {
  final int t = n ~/ 10;
  final int u = n % 10;
  if (t == 0) return _swUnits[u];
  if (u == 0) return _swTens[t];

  return '${_swTens[t]} na ${_swUnits[u]}';
}

/// 1 to 999: "mia nne", "mia nne na thelathini", "mia tisa na tisini na tisa".
String _swUnder1000(final int n) {
  final int h = n ~/ 100;
  final int rest = n % 100;
  final List<String> parts = <String>[if (h > 0) 'mia ${_swUnits[h]}', if (rest > 0) _swUnder100(rest)];

  return parts.join(' na ');
}

String _swahili(final int n) {
  final List<String> parts = <String>[];
  int rest = n;

  if (rest >= 1000000000) {
    parts.add('bilioni ${_swUnder1000(rest ~/ 1000000000)}');
    rest %= 1000000000;
  }
  if (rest >= 1000000) {
    parts.add('milioni ${_swUnder1000(rest ~/ 1000000)}');
    rest %= 1000000;
  }
  if (rest >= 100000) {
    parts.add('laki ${_swUnits[rest ~/ 100000]}');
    rest %= 100000;
  }
  if (rest >= 1000) {
    parts.add('elfu ${_swUnder100(rest ~/ 1000)}');
    rest %= 1000;
  }
  if (rest > 0) parts.add(_swUnder1000(rest));

  return parts.join(' na ');
}

// ---------------------------------------------------------------------------------------------- English

const List<String> _enUnits = <String>['', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
const List<String> _enTens = <String>['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

String _enUnder1000(final int n) {
  final List<String> parts = <String>[];
  final int h = n ~/ 100;
  final int rest = n % 100;
  if (h > 0) parts.add('${_enUnits[h]} hundred');
  if (rest > 0) {
    if (rest < 20) {
      parts.add(_enUnits[rest]);
    } else {
      final int u = rest % 10;
      parts.add(u == 0 ? _enTens[rest ~/ 10] : '${_enTens[rest ~/ 10]} ${_enUnits[u]}');
    }
  }

  return parts.join(' ');
}

String _english(final int n) {
  final List<String> parts = <String>[];
  int rest = n;
  for (final (int size, String name) in <(int, String)>[(1000000000, 'billion'), (1000000, 'million'), (1000, 'thousand')]) {
    if (rest >= size) {
      parts.add('${_enUnder1000(rest ~/ size)} $name');
      rest %= size;
    }
  }
  if (rest > 0) parts.add(_enUnder1000(rest));

  return parts.join(' ');
}
