import 'package:boda_mapato/modules/inventory/screens/widgets/joined_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// A ListTile inside the joined card (the super admin's links on the shop Settings page are such tiles) must have a Material of its
/// own to paint on: without one Flutter throws "ListTile background color or ink splashes may be invisible" for every tile.
void main() {
  testWidgets('tappable ListTiles in a joined card raise no ink warning and still react to a tap', (t) async {
    int taps = 0;
    await t.pumpWidget(ScreenUtilInit(
      designSize: const Size(411, 900),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          body: JoinedSectionsCard(sections: <Widget>[
            FlushSection(
              child: Column(children: <Widget>[
                for (int i = 0; i < 7; i++)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    title: Text('Link $i'),
                    onTap: () => taps++,
                  ),
              ]),
            ),
          ]),
        ),
      ),
    ));
    await t.pump();

    expect(t.takeException(), isNull);
    await t.tap(find.text('Link 3'));
    await t.pump();
    expect(taps, 1);
  });
}
