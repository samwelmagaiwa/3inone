import 'package:boda_mapato/utils/localized_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a name written "Kiswahili / English" shows the half of the language', () {
    expect(localizedName('Kusuka / Braiding', sw: true), 'Kusuka');
    expect(localizedName('Kusuka / Braiding', sw: false), 'Braiding');
    expect(localizedName('Kope / Lashes & Brows', sw: false), 'Lashes & Brows');
  });

  test('any other name shows as it is', () {
    expect(localizedName('Soda', sw: true), 'Soda');
    expect(localizedName('A / B / C', sw: false), 'A / B / C');
    expect(localizedName(' / English', sw: true), ' / English');
    expect(localizedName('Wigi/Wig', sw: false), 'Wigi/Wig');
  });
}
