import 'package:boda_mapato/modules/inventory/models/inv_capabilities.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A business that never said what kind it is still BEHAVES as a depot, but is addressed in general words.
void main() {
  tearDown(() => ApiService.activeService = null);

  test('an unset kind behaves as a depot but does not use a depot\'s words', () {
    final InvCapabilities c = InvCapabilities.fromSettings(<String, String>{'inventory_type': 'depot', 'inventory_type_chosen': '0'});
    expect(c.isDepot, isTrue, reason: 'crates and the depot product form stay');
    expect(c.useCrates, isTrue);
    expect(c.kindChosen, isFalse);
    expect(c.depotWording, isFalse);
  });

  test('a depot that chose to be one keeps its words', () {
    final InvCapabilities c = InvCapabilities.fromSettings(<String, String>{'inventory_type': 'depot', 'inventory_type_chosen': '1'});
    expect(c.depotWording, isTrue);
  });

  test('an older server that does not say counts as chosen (nothing changes for it)', () {
    final InvCapabilities c = InvCapabilities.fromSettings(<String, String>{'inventory_type': 'depot'});
    expect(c.kindChosen, isTrue);
    expect(c.depotWording, isTrue);
  });

  test('any other kind never uses depot words', () {
    for (final String kind in <String>['retail', 'wholesale', 'mixed']) {
      expect(InvCapabilities.fromSettings(<String, String>{'inventory_type': kind, 'inventory_type_chosen': '1'}).depotWording, isFalse, reason: kind);
    }
  });

  test('the kind not being chosen is part of what makes two answers different', () {
    final InvCapabilities a = InvCapabilities.fromSettings(<String, String>{'inventory_type': 'depot', 'inventory_type_chosen': '0'});
    final InvCapabilities b = InvCapabilities.fromSettings(<String, String>{'inventory_type': 'depot', 'inventory_type_chosen': '1'});
    expect(a == b, isFalse, reason: 'so a screen redraws when the owner chooses');
  });
}
