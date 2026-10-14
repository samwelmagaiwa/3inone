import 'package:boda_mapato/widgets/scrolling_chip_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _key(String k) => find.byKey(ValueKey<String>(k));

/// A row of [count] chips in a screen [width] wide. The test font is wide, so a handful of chips never fit a phone.
Widget _host({required double width, int count = 8, ValueChanged<int>? onChosen, int selected = 0}) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: ScrollingChipRow(
              fadeColor: Colors.black,
              children: <Widget>[
                for (int i = 0; i < count; i++)
                  ScrollChoiceChip(
                    key: ValueKey<String>('chip_$i'),
                    label: 'Filter $i',
                    selected: selected == i,
                    onSelected: (bool _) => onChosen?.call(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

double _right(WidgetTester t, int i) => t.getRect(_key('chip_$i')).right;

double _left(WidgetTester t, int i) => t.getRect(_key('chip_$i')).left;

/// Touch a chip where a finger can reach it: the part of it that is on screen and not under the arrow at the edge.
Future<void> _touch(WidgetTester t, int i, {double screen = 360}) async {
  final Rect r = t.getRect(_key('chip_$i'));
  final double reach = screen - 44;
  await t.tapAt(Offset((r.left + (r.right < reach ? r.right : reach)) / 2, r.center.dy));
}

void main() {
  group('more chips than fit', () {
    testWidgets('an arrow at the end says there is more, and there is nothing at the start yet', (t) async {
      await t.pumpWidget(_host(width: 360));
      await t.pump();

      expect(_key('chips_more_after'), findsOneWidget);
      expect(_key('chips_more_before'), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('the arrow slides the row along and the arrow at the start appears', (t) async {
      await t.pumpWidget(_host(width: 360));
      await t.pump();
      final double before = _left(t, 0);

      await t.tap(_key('chips_more_after'));
      await t.pumpAndSettle();

      expect(_left(t, 0), lessThan(before), reason: 'the row moved');
      expect(_key('chips_more_before'), findsOneWidget);
    });

    testWidgets('at the end of the row the end arrow is gone and the last chip is fully in view', (t) async {
      await t.pumpWidget(_host(width: 360));
      await t.pump();

      for (int i = 0; i < 30 && _key('chips_more_after').evaluate().isNotEmpty; i++) {
        await t.tap(_key('chips_more_after'));
        await t.pumpAndSettle();
      }

      expect(_key('chips_more_after'), findsNothing);
      expect(_key('chips_more_before'), findsOneWidget);
      expect(_right(t, 7), lessThanOrEqualTo(360), reason: 'the last chip is wholly visible');
      expect(_right(t, 7), greaterThan(360 - 30), reason: 'and the row ends right after it');
    });

    testWidgets('the arrow at the start slides back, and then it is gone', (t) async {
      await t.pumpWidget(_host(width: 360));
      await t.pump();
      for (int i = 0; i < 30 && _key('chips_more_after').evaluate().isNotEmpty; i++) {
        await t.tap(_key('chips_more_after'));
        await t.pumpAndSettle();
      }

      for (int i = 0; i < 30 && _key('chips_more_before').evaluate().isNotEmpty; i++) {
        await t.tap(_key('chips_more_before'));
        await t.pumpAndSettle();
      }

      expect(_key('chips_more_before'), findsNothing);
      expect(_key('chips_more_after'), findsOneWidget);
      expect(_left(t, 0), lessThan(30), reason: 'back at the first chip');
    });

    testWidgets('dragging the row shows and hides the arrows as well', (t) async {
      await t.pumpWidget(_host(width: 360));
      await t.pump();

      await t.drag(find.byType(SingleChildScrollView), const Offset(-120, 0));
      await t.pumpAndSettle();
      expect(_key('chips_more_before'), findsOneWidget);
      expect(_key('chips_more_after'), findsOneWidget);

      await t.drag(find.byType(SingleChildScrollView), const Offset(3000, 0));
      await t.pumpAndSettle();
      expect(_key('chips_more_before'), findsNothing);
    });
  });

  group('choosing a chip', () {
    testWidgets('a chip that is cut off slides to the start, so the one after it comes into view', (t) async {
      final List<int> chosen = <int>[];
      await t.pumpWidget(_host(width: 420, onChosen: chosen.add));
      await t.pump();

      // the first chip that sticks out of the right edge
      int cut = 0;
      while (_right(t, cut) <= 420) {
        cut++;
      }
      expect(_left(t, cut), lessThan(420 - 44), reason: 'part of it can be touched');
      expect(_left(t, cut + 1), greaterThanOrEqualTo(420), reason: 'and the one after it is not on screen at all');

      await _touch(t, cut, screen: 420);
      await t.pumpAndSettle();

      expect(chosen, <int>[cut]);
      expect(_left(t, cut), lessThan(60), reason: 'the chip moved to the start of the row');
      expect(_left(t, cut + 1), lessThan(420 - 60), reason: 'so the next chip is now showing');
    });

    testWidgets('choosing the last chip stops at the end of the row, which can then be seen', (t) async {
      final List<int> chosen = <int>[];
      await t.pumpWidget(_host(width: 360, onChosen: chosen.add));
      await t.pump();
      for (int i = 0; i < 30 && _key('chips_more_after').evaluate().isNotEmpty; i++) {
        await t.tap(_key('chips_more_after'));
        await t.pumpAndSettle();
      }
      final double before = _left(t, 7);

      await t.tap(_key('chip_7'));
      await t.pumpAndSettle();

      expect(chosen, <int>[7]);
      expect(_left(t, 7), before, reason: 'the row is already at its end, so it does not move further');
      expect(_right(t, 7), lessThanOrEqualTo(360));
      expect(_key('chips_more_after'), findsNothing, reason: 'nothing hidden after the last chip');
    });

    testWidgets('choosing a chip calls its handler and shows it as chosen', (t) async {
      int selected = 0;
      late StateSetter update;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              update = setState;
              return ScrollingChipRow(
                children: <Widget>[
                  for (int i = 0; i < 3; i++)
                    ScrollChoiceChip(
                      key: ValueKey<String>('chip_$i'),
                      label: 'Filter $i',
                      selected: selected == i,
                      onSelected: (bool _) => update(() => selected = i),
                    ),
                ],
              );
            },
          ),
        ),
      ));

      await t.tap(_key('chip_2'));
      await t.pumpAndSettle();

      expect(selected, 2);
      expect(find.byType(ChoiceChip).evaluate().map((Element e) => (e.widget as ChoiceChip).selected).toList(), <bool>[false, false, true]);
    });
  });

  group('chips that all fit', () {
    testWidgets('show no arrows and do not move when chosen', (t) async {
      final List<int> chosen = <int>[];
      await t.pumpWidget(_host(width: 800, count: 3, onChosen: chosen.add));
      await t.pump();

      expect(_key('chips_more_after'), findsNothing);
      expect(_key('chips_more_before'), findsNothing);

      final double before = _left(t, 2);
      await t.tap(_key('chip_2'));
      await t.pumpAndSettle();
      expect(chosen, <int>[2]);
      expect(_left(t, 2), before);
    });
  });
}
