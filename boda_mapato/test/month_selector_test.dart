import 'package:boda_mapato/widgets/month_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const double _phoneWidth = 360;

/// A phone-sized screen with the selector in a stateful parent, like the dashboards.
Future<ValueNotifier<int>> _pump(
  final WidgetTester tester, {
  required final int initialMonth,
  final List<int>? tapped,
}) async {
  tester.view.physicalSize = const Size(_phoneWidth, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final ValueNotifier<int> selected = ValueNotifier<int>(initialMonth);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<int>(
        valueListenable: selected,
        builder: (final BuildContext _, final int month, final Widget? __) =>
            MonthSelector(
          months: _months,
          selectedMonth: month,
          selectedColor: Colors.white,
          unselectedColor: Colors.grey,
          onSelected: (final int picked) {
            tapped?.add(picked);
            selected.value = picked;
          },
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();

  return selected;
}

bool _inView(final WidgetTester tester, final String month) {
  final Rect r = tester.getRect(find.text(month));

  return r.left >= 0 && r.right <= _phoneWidth;
}

void main() {
  testWidgets('opens with the selected month in view, not hidden off to the right',
      (final WidgetTester tester) async {
    await _pump(tester, initialMonth: 10);

    expect(_inView(tester, 'Oct'), isTrue, reason: 'the current month must be visible');
    expect(_inView(tester, 'Jan'), isFalse, reason: 'it scrolled, so January is off to the left');
  });

  testWidgets('January stays at the start when January is selected',
      (final WidgetTester tester) async {
    await _pump(tester, initialMonth: 1);

    expect(_inView(tester, 'Jan'), isTrue);
    expect(_inView(tester, 'Oct'), isFalse);
  });

  testWidgets('earlier months are a swipe away and the view does not snap back',
      (final WidgetTester tester) async {
    final ValueNotifier<int> selected = await _pump(tester, initialMonth: 10);
    expect(_inView(tester, 'Jan'), isFalse);

    // Swipe right, towards the earlier months.
    await tester.drag(find.byType(SingleChildScrollView), const Offset(900, 0));
    await tester.pumpAndSettle();

    expect(_inView(tester, 'Jan'), isTrue, reason: 'the user can reach January');
    expect(selected.value, 10, reason: 'looking at other months does not change the selection');
    // Settled again: still where the user left it.
    await tester.pump(const Duration(seconds: 1));
    expect(_inView(tester, 'Jan'), isTrue);
  });

  testWidgets('tapping a month reports its number and brings it into view',
      (final WidgetTester tester) async {
    final List<int> tapped = <int>[];
    final ValueNotifier<int> selected = await _pump(tester, initialMonth: 10, tapped: tapped);

    await tester.tap(find.text('Nov'));
    await tester.pumpAndSettle();

    expect(tapped, <int>[11]);
    expect(selected.value, 11);
    expect(_inView(tester, 'Nov'), isTrue);

    // Pick an early month from far away: it is scrolled to, too.
    await tester.drag(find.byType(SingleChildScrollView), const Offset(900, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feb'));
    await tester.pumpAndSettle();

    expect(tapped, <int>[11, 2]);
    expect(_inView(tester, 'Feb'), isTrue);
  });

  testWidgets('a month chosen elsewhere is scrolled into view',
      (final WidgetTester tester) async {
    final ValueNotifier<int> selected = await _pump(tester, initialMonth: 1);
    expect(_inView(tester, 'Dec'), isFalse);

    selected.value = 12;
    await tester.pumpAndSettle();

    expect(_inView(tester, 'Dec'), isTrue);
  });
}
