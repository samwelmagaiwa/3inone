import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The salon's lists look like the inventory's: one card of rows divided by the glowing line (GlowListCard / GlowCard), not a stack of separate
/// plain cards. This keeps the pages that were changed from slipping back.
const List<String> _converted = <String>[
  'salon_reports_screen', 'profit_loss_screen', 'payroll_screen', 'attendance_screen', 'shifts_screen', 'schedule_screen',
  'services_report_screen', 'salon_expenses_screen', 'stylists_screen', 'stylist_detail_screen', 'appointments_screen', 'rebook_screen',
  'queue_screen', 'equipment_screen', 'feedback_screen', 'insights_screen', 'cashbook_screen', 'client_history_screen',
  'salon_settings_screen', 'offers_screens', 'export_screen', 'branches_screen', 'service_materials_screen', 'client_extras',
];

String _source(String name) => File('lib/modules/inventory/screens/salon/$name.dart').readAsStringSync();

void main() {
  for (final String name in _converted) {
    test('$name draws its lists as one card divided by the glowing line', () {
      final String code = _source(name);

      expect(code.contains('GlowListCard') || code.contains('GlowCard'), isTrue, reason: 'a glowing card');
      expect(RegExp(r'[^A-Za-z]Card\(').hasMatch(code), isFalse, reason: 'no plain Material Card left');
      expect(code.contains('glassCardDecoration'), isFalse, reason: 'no separate glass card per row');
    });
  }

  test('the helper drops the old spacers and dividers, and keeps every real row', () {
    final String helper = File('lib/modules/inventory/screens/widgets/glow_list_card.dart').readAsStringSync();

    expect(helper.contains('List<Widget> glowRows'), isTrue);
    expect(helper.contains('w is! Divider'), isTrue, reason: 'a plain divider is replaced by the glowing line');
    expect(helper.contains('MaterialType.transparency'), isTrue, reason: 'a ListTile in a row can show its touch ripple');
  });
}
