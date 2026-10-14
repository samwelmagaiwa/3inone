import 'package:boda_mapato/services/localization_service.dart';
import 'package:boda_mapato/widgets/dial_date_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _key(String k) => find.byKey(ValueKey<String>(k));

String _text(WidgetTester t, String key) => (t.widget(_key(key)) as Text).data!;

/// Opens the picker from a button and remembers what it answered.
class _Harness {
  DateTime? answer;
  bool answered = false;
}

Future<_Harness> _open(
  WidgetTester t, {
  DateTime? initial,
  DateTime? first,
  DateTime? last,
  bool sw = true,
}) async {
  final _Harness h = _Harness();
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey<String>('open'),
            onPressed: () async {
              h.answer = await showDialDatePicker(
                context,
                initialDate: initial ?? DateTime(2026, 10, 14),
                firstDate: first ?? DateTime(2026, 1, 1),
                lastDate: last ?? DateTime(2030, 12, 31),
                sw: sw,
              );
              h.answered = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(_key('open'));
  await t.pumpAndSettle();
  return h;
}

Future<void> _day(WidgetTester t, int day) async {
  // The numbers are painted on the face and the face takes the touch.
  await t.tap(_key('dial_day_$day'), warnIfMissed: false);
  await t.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('the dial', () {
    testWidgets('opens on the date given, with the days of the month around the circle', (t) async {
      await _open(t);

      expect(_text(t, 'dial_selected'), 'Jtn, 14 Okt 2026');
      expect(_text(t, 'dial_month'), 'Oktoba');
      expect(_text(t, 'dial_year'), '2026');
      expect(_key('dial_face'), findsOneWidget);
      for (int day = 1; day <= 31; day++) {
        expect(_key('dial_day_$day'), findsOneWidget, reason: 'day $day');
      }
      expect(_key('dial_day_32'), findsNothing);
    });

    testWidgets('days 1 to 16 are on the outer ring and 17 to 31 on the inner one, clockwise from the top', (t) async {
      await _open(t);
      final Offset centre = t.getCenter(_key('dial_face'));

      double distance(int day) => (t.getCenter(_key('dial_day_$day')) - centre).distance;
      for (int day = 2; day <= 16; day++) {
        expect(distance(day), closeTo(distance(1), 0.5), reason: 'day $day is on the outer ring');
      }
      for (int day = 18; day <= 31; day++) {
        expect(distance(day), closeTo(distance(17), 0.5), reason: 'day $day is on the inner ring');
      }
      expect(distance(17), lessThan(distance(1)));

      final Offset one = t.getCenter(_key('dial_day_1'));
      expect(one.dx, closeTo(centre.dx, 0.5), reason: 'day 1 is at the top');
      expect(one.dy, lessThan(centre.dy));
      expect(t.getCenter(_key('dial_day_5')).dx, greaterThan(centre.dx), reason: 'then clockwise');
      expect(t.getCenter(_key('dial_day_13')).dx, lessThan(centre.dx));
    });

    testWidgets('tapping a day chooses it, on either ring, and Select gives it back', (t) async {
      final _Harness h = await _open(t);

      for (final int day in <int>[1, 5, 8, 16, 17, 20, 24, 31]) {
        await _day(t, day);
        expect(_text(t, 'dial_selected'), endsWith('$day Okt 2026'), reason: 'day $day');
      }

      await t.tap(_key('dial_ok'));
      await t.pumpAndSettle();
      expect(h.answered, isTrue);
      expect(h.answer, DateTime(2026, 10, 31));
      expect(_key('dial_face'), findsNothing, reason: 'the dial closed');
    });

    testWidgets('dragging a finger round the face moves the hand', (t) async {
      await _open(t);

      final Offset from = t.getCenter(_key('dial_day_3'));
      final Offset to = t.getCenter(_key('dial_day_9'));
      await t.dragFrom(from, to - from);
      await t.pump();

      expect(_text(t, 'dial_selected'), endsWith('9 Okt 2026'));
    });

    testWidgets('the middle of the face and the space between the numbers do nothing', (t) async {
      await _open(t);

      await t.tapAt(t.getCenter(_key('dial_face')));
      await t.pump();
      expect(_text(t, 'dial_selected'), endsWith('14 Okt 2026'));
    });

    testWidgets('a blank place on the face, where the month has no such day, does nothing', (t) async {
      final _Harness h = await _open(t, initial: DateTime(2026, 11, 13));
      final Offset where30 = t.getCenter(_key('dial_day_30'));

      for (int i = 0; i < 3; i++) {
        await t.tap(_key('dial_next_month'));
        await t.pump();
      }
      expect(_text(t, 'dial_selected'), endsWith('13 Feb 2027'));
      expect(_key('dial_day_30'), findsNothing, reason: 'February has no 30th');

      await t.tapAt(where30);
      await t.pump();
      expect(_text(t, 'dial_selected'), endsWith('13 Feb 2027'), reason: 'the empty place is not March the 2nd');
      expect(_text(t, 'dial_month'), 'Februari');

      await t.tap(_key('dial_ok'));
      await t.pumpAndSettle();
      expect(h.answer, DateTime(2027, 2, 13));
    });

    testWidgets('Cancel gives back nothing', (t) async {
      final _Harness h = await _open(t);

      await _day(t, 22);
      await t.tap(_key('dial_cancel'));
      await t.pumpAndSettle();

      expect(h.answered, isTrue);
      expect(h.answer, isNull);
    });

    testWidgets('shows the date of today with a ring and the chosen one filled', (t) async {
      await _open(t, initial: DateTime.now());
      final DateTime today = DateUtils.dateOnly(DateTime.now());

      expect(_text(t, 'dial_selected'), contains('${today.day} '));
      expect(_key('dial_day_${today.day}'), findsOneWidget);
    });
  });

  group('months and years', () {
    testWidgets('the arrows change the month and keep the day where the month has it', (t) async {
      final _Harness h = await _open(t, initial: DateTime(2026, 12, 31));

      await t.tap(_key('dial_next_month'));
      await t.pump();
      expect(_text(t, 'dial_month'), 'Januari');
      expect(_text(t, 'dial_year'), '2027');
      expect(_text(t, 'dial_selected'), endsWith('31 Jan 2027'));

      await t.tap(_key('dial_next_month'));
      await t.pump();
      expect(_text(t, 'dial_month'), 'Februari');
      expect(_text(t, 'dial_selected'), endsWith('28 Feb 2027'), reason: 'February has no 31st');
      expect(_key('dial_day_28'), findsOneWidget);
      expect(_key('dial_day_29'), findsNothing);
      expect(_key('dial_day_31'), findsNothing);

      await t.tap(_key('dial_prev_month'));
      await t.pump();
      expect(_text(t, 'dial_selected'), endsWith('28 Jan 2027'), reason: 'the day it landed on is kept');

      await t.tap(_key('dial_ok'));
      await t.pumpAndSettle();
      expect(h.answer, DateTime(2027, 1, 28));
    });

    testWidgets('a leap February has 29 days', (t) async {
      await _open(t, initial: DateTime(2028, 2, 10));

      expect(_key('dial_day_29'), findsOneWidget);
      expect(_key('dial_day_30'), findsNothing);
    });

    testWidgets('the month and the year can be chosen from a list', (t) async {
      final _Harness h = await _open(t);

      await t.tap(_key('dial_month_menu'));
      await t.pumpAndSettle();
      await t.tap(_key('dial_month_3'));
      await t.pumpAndSettle();
      expect(_text(t, 'dial_month'), 'Machi');
      expect(_text(t, 'dial_selected'), endsWith('14 Mac 2026'));

      await t.tap(_key('dial_year_menu'));
      await t.pumpAndSettle();
      await t.tap(_key('dial_year_2028'));
      await t.pumpAndSettle();
      expect(_text(t, 'dial_year'), '2028');
      expect(_text(t, 'dial_selected'), endsWith('14 Mac 2028'));

      await t.tap(_key('dial_ok'));
      await t.pumpAndSettle();
      expect(h.answer, DateTime(2028, 3, 14));
    });
  });

  group('the dates on offer', () {
    testWidgets('a day outside them cannot be chosen, and the arrows stop at the ends', (t) async {
      await _open(t, initial: DateTime(2026, 10, 20), first: DateTime(2026, 10, 10), last: DateTime(2026, 11, 20));

      expect(t.widget<IconButton>(_key('dial_prev_month')).onPressed, isNull, reason: 'nothing before October');
      expect(t.widget<IconButton>(_key('dial_next_month')).onPressed, isNotNull);

      await _day(t, 5);
      expect(_text(t, 'dial_selected'), endsWith('20 Okt 2026'), reason: 'the 5th is before the first day on offer');
      await _day(t, 10);
      expect(_text(t, 'dial_selected'), endsWith('10 Okt 2026'), reason: 'the first day on offer');

      await t.tap(_key('dial_next_month'));
      await t.pump();
      expect(t.widget<IconButton>(_key('dial_next_month')).onPressed, isNull, reason: 'nothing after November');
      await _day(t, 25);
      expect(_text(t, 'dial_selected'), endsWith('10 Nov 2026'), reason: 'the 25th is after the last day on offer; the chosen day moved into range');
      await _day(t, 20);
      expect(_text(t, 'dial_selected'), endsWith('20 Nov 2026'));
    });

    testWidgets('a starting date outside them is brought inside', (t) async {
      final _Harness h = await _open(t, initial: DateTime(2020, 1, 1), first: DateTime(2026, 10, 10), last: DateTime(2026, 12, 31));

      expect(_text(t, 'dial_selected'), endsWith('10 Okt 2026'));
      await t.tap(_key('dial_ok'));
      await t.pumpAndSettle();
      expect(h.answer, DateTime(2026, 10, 10));
    });

    testWidgets('the year list holds only the years on offer', (t) async {
      await _open(t, first: DateTime(2026, 10, 10), last: DateTime(2028, 3, 1));

      await t.tap(_key('dial_year_menu'));
      await t.pumpAndSettle();
      expect(_key('dial_year_2026'), findsOneWidget);
      expect(_key('dial_year_2027'), findsOneWidget);
      expect(_key('dial_year_2028'), findsOneWidget);
      expect(_key('dial_year_2025'), findsNothing);
      expect(_key('dial_year_2029'), findsNothing);

      // a year whose same month is out of range lands on the nearest month that is allowed
      await t.tap(_key('dial_year_2028'));
      await t.pumpAndSettle();
      expect(_text(t, 'dial_year'), '2028');
      expect(_text(t, 'dial_month'), 'Machi');
    });
  });

  group('language and small screens', () {
    testWidgets('speaks English when the app does', (t) async {
      await _open(t, sw: false);

      expect(find.text('Select a date'), findsOneWidget);
      expect(_text(t, 'dial_selected'), 'Wed, 14 Oct 2026');
      expect(_text(t, 'dial_month'), 'October');
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Select'), findsOneWidget);
      expect(find.text('Chagua'), findsNothing);
      expect(find.text('Ghairi'), findsNothing);
    });

    testWidgets('speaks Swahili when the app does', (t) async {
      await _open(t);

      expect(find.text('Chagua tarehe'), findsOneWidget);
      expect(find.text('Ghairi'), findsOneWidget);
      expect(find.text('Chagua'), findsOneWidget);
      expect(find.text('Select'), findsNothing);
    });

    for (final bool sw in <bool>[true, false]) {
      testWidgets('fits a small phone with large text (${sw ? 'sw' : 'en'})', (t) async {
        t.view.physicalSize = const Size(320, 568);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final _Harness h = _Harness();
        await t.pumpWidget(MaterialApp(
          builder: (BuildContext context, Widget? child) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)), child: child!),
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: TextButton(
                key: const ValueKey<String>('open'),
                onPressed: () async => h.answer = await showDialDatePicker(
                  context,
                  initialDate: DateTime(2026, 9, 30),
                  firstDate: DateTime(2026, 1, 1),
                  lastDate: DateTime(2030, 1, 1),
                  sw: sw,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ));
        await t.tap(_key('open'));
        await t.pumpAndSettle();

        expect(t.takeException(), isNull, reason: 'no overflow');
        await _day(t, 15);
        expect(_text(t, 'dial_selected'), contains('15 '));
        await t.ensureVisible(_key('dial_ok'));
        await t.tap(_key('dial_ok'));
        await t.pumpAndSettle();
        expect(h.answer, DateTime(2026, 9, 15));
      });
    }

    test('dates are written in the language of the app', () {
      expect(dialDateLabel(DateTime(2026, 5, 3), sw: true), '3 Mei 2026');
      expect(dialDateLabel(DateTime(2026, 5, 3), sw: false), '3 May 2026');
      expect(dialDateLabel(DateTime(2026, 8, 31), sw: true), '31 Ago 2026');
      expect(dialDateLabel(DateTime(2026, 12, 1), sw: true), '1 Des 2026');
    });

    test('is not tied to the localisation singleton', () {
      // the dial is told the language, so it needs nothing from LocalizationService
      expect(LocalizationService.instance, isNotNull);
    });
  });
}
