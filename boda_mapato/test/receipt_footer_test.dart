import 'package:boda_mapato/modules/inventory/screens/sales/sale_receipt_screen.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A salon's receipt never carries the shop's "goods sold cannot be returned" line; a shop's does.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService.instance.changeLanguage('en');
  });
  tearDown(() {
    ApiService.activeService = null;
  });

  test('a salon with the shop line saved long ago, or nothing saved, says only Welcome again', () {
    ApiService.activeService = 'salon';
    expect(receiptFooterText(<String, String>{'receipt_footer_note': shopReturnLine}), 'Welcome again!');
    expect(receiptFooterText(<String, String>{'receipt_footer_note': ''}), 'Welcome again!');
    expect(receiptFooterText(<String, String>{}), 'Welcome again!');
    expect(receiptFooterText(<String, String>{'receipt_footer_note': 'null'}), 'Welcome again!');
    expect(receiptFooterText(<String, String>{'receipt_footer_note': shopReturnLine}, lines: true), isNot(contains('kurudishwa')));
  });

  test("a salon keeps a note the owner wrote, and Swahili says 'Karibu tena!'", () async {
    ApiService.activeService = 'salon';
    expect(receiptFooterText(<String, String>{'receipt_footer_note': 'Thank you for choosing Glow'}), 'Thank you for choosing Glow');
    await LocalizationService.instance.changeLanguage('sw');
    addTearDown(() => LocalizationService.instance.changeLanguage('en'));
    expect(receiptFooterText(<String, String>{}), 'Karibu tena!');
  });

  test('a shop keeps its own note, and the usual line when it wrote none', () {
    ApiService.activeService = 'inventory';
    expect(receiptFooterText(<String, String>{'receipt_footer_note': 'Come again'}), 'Come again');
    expect(receiptFooterText(<String, String>{}), contains('cannot be returned'));
    expect(receiptFooterText(<String, String>{'receipt_footer_note': shopReturnLine}), shopReturnLine);
  });
}
