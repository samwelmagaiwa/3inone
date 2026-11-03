import 'package:boda_mapato/modules/inventory/screens/widgets/inv_action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// The raised action button of the inventory screens: it shows its label, can be pressed, and is dead when it has nothing to do.
Future<void> _show(WidgetTester t, Widget child) async {
  await t.pumpWidget(ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => MaterialApp(home: Scaffold(body: Center(child: child)))));
}

void main() {
  testWidgets('shows the label and the arrow, and a press calls back', (t) async {
    int pressed = 0;
    await _show(t, InvActionButton(label: 'Customer account', icon: Icons.account_balance_wallet_rounded, color: Colors.amber, onPressed: () => pressed++));

    expect(find.text('Customer account'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    await t.tap(find.byType(InvActionButton));
    expect(pressed, 1);
  });

  testWidgets('a button that acts on the spot has no arrow', (t) async {
    await _show(t, InvActionButton(label: 'Receive payment', icon: Icons.payments_rounded, color: Colors.green, arrow: false, onPressed: () {}));

    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('without an action it is disabled and nothing happens on a press', (t) async {
    await _show(t, const InvActionButton(label: 'Merge', icon: Icons.merge_type_rounded, color: Colors.green, onPressed: null));

    await t.tap(find.byType(InvActionButton));
    expect(find.text('Merge'), findsOneWidget);
  });

  testWidgets('a long label shrinks instead of overflowing', (t) async {
    await _show(t, SizedBox(width: 330, child: InvActionButton(label: 'Customer report (week, month, year)', icon: Icons.insights_rounded, color: Colors.blue, onPressed: () {})));

    expect(t.takeException(), isNull);
  });
}
