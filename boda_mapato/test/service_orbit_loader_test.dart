import 'package:boda_mapato/widgets/loading/service_orbit_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(WidgetTester t, Widget child) async {
  await t.pumpWidget(ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => MaterialApp(home: Scaffold(body: Center(child: child)))));
}

void main() {
  test('the waiting percentage climbs and never reaches 100', () {
    expect(orbitPercent(0), 0);
    expect(orbitPercent(2), greaterThan(orbitPercent(1)));
    expect(orbitPercent(1000), lessThan(100));
  });

  testWidgets('shows the four services, the message and a percentage that follows the real progress', (t) async {
    await _show(t, const ServiceOrbitLoader(message: 'SIGNING IN', progress: 0.42));

    expect(find.byKey(const ValueKey<String>('orbit_loader')), findsOneWidget);
    for (int i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey<String>('orbit_item_$i')), findsOneWidget);
    }
    expect(find.text('SIGNING IN'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('the services move round while waiting', (t) async {
    await _show(t, const ServiceOrbitLoader());
    final Offset before = t.getCenter(find.byKey(const ValueKey<String>('orbit_item_0')));
    await t.pump(const Duration(seconds: 1));
    final Offset after = t.getCenter(find.byKey(const ValueKey<String>('orbit_item_0')));
    expect(after, isNot(before));
    expect(find.byKey(const ValueKey<String>('orbit_message')), findsNothing);
  });
}
