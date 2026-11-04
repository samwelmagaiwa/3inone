import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/widgets/live_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dashboards keep their figures fresh by themselves: after a change made in the app, on a timer, and when shown again.
Future<int Function()> _show(WidgetTester t, {bool showing = true, Duration interval = const Duration(seconds: 45), Future<void> Function()? slow}) async {
  int reads = 0;
  await t.pumpWidget(
    MaterialApp(
      home: TickerMode(
        enabled: showing,
        child: LiveRefresh(
          interval: interval,
          onRefresh: () async {
            reads++;
            if (slow != null) await slow();
          },
          child: const Text('figures'),
        ),
      ),
    ),
  );

  return () => reads;
}

void main() {
  testWidgets('a change accepted by the server makes it read again, once for a burst of changes', (WidgetTester t) async {
    final int Function() reads = await _show(t);
    expect(reads(), 0);

    ApiService.changes.value++;
    ApiService.changes.value++;
    ApiService.changes.value++;
    await t.pump(const Duration(milliseconds: 300));
    expect(reads(), 0, reason: 'it waits a moment for the burst to finish');

    await t.pump(const Duration(milliseconds: 600));
    expect(reads(), 1);
  });

  testWidgets('it reads again every interval, for what other phones changed', (WidgetTester t) async {
    final int Function() reads = await _show(t, interval: const Duration(seconds: 10));

    await t.pump(const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 10));

    expect(reads(), 2);
  });

  testWidgets('a screen that is not showing does not read, and catches up when it is shown', (WidgetTester t) async {
    int reads = 0;
    Widget app(bool showing) => MaterialApp(
          home: TickerMode(
            enabled: showing,
            child: LiveRefresh(onRefresh: () async => reads++, child: const Text('figures')),
          ),
        );

    await t.pumpWidget(app(false));
    ApiService.changes.value++;
    await t.pump(const Duration(seconds: 1));
    expect(reads, 0, reason: 'another tab: nothing is read');

    await t.pumpWidget(app(true));
    await t.pump();
    expect(reads, 1, reason: 'shown again: it catches up at once');

    await t.pumpWidget(app(false));
    await t.pumpWidget(app(true));
    await t.pump();
    expect(reads, 1, reason: 'nothing changed while it was away');
  });

  testWidgets('coming back to the app reads again', (WidgetTester t) async {
    final int Function() reads = await _show(t);

    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();

    expect(reads(), 1);
  });

  testWidgets('reads never overlap: a change during a read waits for the next one', (WidgetTester t) async {
    bool finished = false;
    final int Function() reads = await _show(t, slow: () async {
      await Future<void>.delayed(const Duration(seconds: 2));
      finished = true;
    });

    ApiService.changes.value++;
    await t.pump(const Duration(seconds: 1));
    expect(reads(), 1);
    ApiService.changes.value++;
    await t.pump(const Duration(seconds: 1)); // the first read is still running
    expect(reads(), 1);

    await t.pump(const Duration(seconds: 2));
    expect(finished, isTrue);
    ApiService.changes.value++;
    await t.pump(const Duration(seconds: 1));
    expect(reads(), 2);
    await t.pump(const Duration(seconds: 3)); // let the last read finish
  });

  testWidgets('a failing read never breaks the screen and is tried again', (WidgetTester t) async {
    int reads = 0;
    await t.pumpWidget(
      MaterialApp(
        home: LiveRefresh(
          interval: const Duration(seconds: 5),
          onRefresh: () async {
            reads++;
            throw Exception('no signal');
          },
          child: const Text('figures'),
        ),
      ),
    );

    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 5));

    expect(reads, 2);
    expect(find.text('figures'), findsOneWidget);
  });
}
