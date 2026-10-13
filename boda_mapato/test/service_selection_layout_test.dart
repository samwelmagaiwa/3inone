import 'package:boda_mapato/screens/service_selection_screen.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Select Service: the services sit in centred rows of up to three. A two-column grid left the third service alone
/// at the left of a second row.
const Map<String, IconData> _icons = <String, IconData>{
  'inventory': Icons.inventory_2_rounded,
  'rental': Icons.apartment_rounded,
  'transport': Icons.local_shipping_rounded,
};

Future<void> _open(WidgetTester t, List<String> services, {Size size = const Size(411, 860)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        builder: (_, __) => MaterialApp(home: ServiceSelectionScreen(allowedServices: services)),
      ),
    ),
  );
  await t.pump();
}

Rect _tile(WidgetTester t, String service) => t.getRect(find.ancestor(of: find.byIcon(_icons[service]!), matching: find.byType(InkWell)).first);

void main() {
  const double screenWidth = 411;

  testWidgets('three services sit side by side on ONE row, in the order inventory, rental, transport', (t) async {
    await _open(t, <String>['inventory', 'rental', 'transport']);

    final Rect inventory = _tile(t, 'inventory');
    final Rect rental = _tile(t, 'rental');
    final Rect transport = _tile(t, 'transport');

    expect(rental.top, inventory.top, reason: 'rental is on the same row');
    expect(transport.top, inventory.top, reason: 'transport is on the same row');
    expect(inventory.left < rental.left && rental.left < transport.left, isTrue);
    expect(transport.right, lessThanOrEqualTo(screenWidth));
    expect(inventory.left, greaterThanOrEqualTo(0));
  });

  testWidgets('the row of three is centred on the screen', (t) async {
    await _open(t, <String>['inventory', 'rental', 'transport']);

    final double left = _tile(t, 'inventory').left;
    final double right = _tile(t, 'transport').right;
    expect((left + right) / 2, closeTo(screenWidth / 2, 1.0));
  });

  testWidgets('three tiles are the same size', (t) async {
    await _open(t, <String>['inventory', 'rental', 'transport']);

    expect(_tile(t, 'rental').size, _tile(t, 'inventory').size);
    expect(_tile(t, 'transport').size, _tile(t, 'inventory').size);
  });

  testWidgets('two services are centred, not pushed to the left', (t) async {
    await _open(t, <String>['inventory', 'transport']);

    final Rect a = _tile(t, 'inventory');
    final Rect b = _tile(t, 'transport');
    expect(b.top, a.top);
    expect(((a.left + b.right) / 2), closeTo(screenWidth / 2, 1.0));
  });

  testWidgets('one service is centred', (t) async {
    await _open(t, <String>['rental']);

    final Rect only = _tile(t, 'rental');
    expect(only.center.dx, closeTo(screenWidth / 2, 1.0));
  });

  testWidgets('the tiles start right under the heading, not in the middle of the screen', (t) async {
    await _open(t, <String>['inventory', 'rental', 'transport']);

    expect(_tile(t, 'inventory').top, lessThan(260));
  });

  testWidgets('on a narrow phone nothing overflows and all three are still on one row', (t) async {
    await _open(t, <String>['inventory', 'rental', 'transport'], size: const Size(320, 640));

    expect(t.takeException(), isNull);
    expect(_tile(t, 'transport').top, _tile(t, 'inventory').top);
    expect(_tile(t, 'transport').right, lessThanOrEqualTo(320));
  });

  testWidgets('tapping a tile still selects that service', (t) async {
    await _open(t, <String>['inventory', 'rental', 'transport']);

    expect(find.byType(InkWell), findsNWidgets(3));
    for (final String s in _icons.keys) {
      expect(find.byIcon(_icons[s]!), findsOneWidget, reason: s);
    }
  });

  testWidgets('a person with no service sees the "no access" message, not tiles', (t) async {
    await _open(t, <String>[]);

    expect(find.byIcon(Icons.inventory_2_rounded), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsWidgets);
  });
}
