import 'package:boda_mapato/services/localization_service.dart';
import 'package:boda_mapato/widgets/place_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_places.dart';

/// Region, district, ward and street or village: each chosen from the imported locations (with a search box), each depending on the one
/// before, and each a box to type in when the list has nothing for the place or the person says it is not there.
Future<List<PlaceChoice>> _open(WidgetTester t, PlaceSource source) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final List<PlaceChoice> log = <PlaceChoice>[];
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(
        designSize: const Size(800, 1600),
        builder: (_, __) => MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: PlacePicker(source: source, onChanged: log.add)))),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();

  return log;
}

Finder _select(int level) => find.byKey(ValueKey<String>('place_select_$level'));
Finder _text(int level) => find.byKey(ValueKey<String>('place_text_$level'));

Future<void> _pick(WidgetTester t, int level, String name) async {
  await t.tap(_select(level));
  await t.pumpAndSettle();
  await t.tap(find.text(name));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the regions are on offer, and choosing one asks for its districts', (t) async {
    final FakePlaces places = FakePlaces();
    final List<PlaceChoice> log = await _open(t, places);

    expect(places.asked, <String>['regions']);
    expect(_select(0), findsOneWidget);

    await _pick(t, 0, 'Dar es Salaam');

    expect(log.last.region, 'Dar es Salaam');
    expect(places.asked, contains('districts:1'));
    expect(find.text('Dar es Salaam'), findsOneWidget, reason: 'the choice is shown in the field');
  });

  testWidgets('district, ward and street follow, each asked with the one chosen before it', (t) async {
    final FakePlaces places = FakePlaces();
    final List<PlaceChoice> log = await _open(t, places);

    await _pick(t, 0, 'Dar es Salaam');
    await _pick(t, 1, 'Kinondoni');
    await _pick(t, 2, 'Mikocheni');
    await _pick(t, 3, 'Mikocheni B');

    final PlaceChoice c = log.last;
    expect(<String?>[c.region, c.district, c.ward, c.street], <String?>['Dar es Salaam', 'Kinondoni', 'Mikocheni', 'Mikocheni B']);
    expect(places.asked, <String>['regions', 'districts:1', 'wards:11', 'streets:111']);
  });

  testWidgets('a level cannot be opened before the one above it has a value, and says which to choose first', (t) async {
    await _open(t, FakePlaces());

    expect(find.text('Choose the region first'), findsOneWidget);
    await t.tap(_select(1));
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('place_search')), findsNothing, reason: 'nothing opens');
  });

  testWidgets('changing the region clears the district, ward and street under it', (t) async {
    final FakePlaces places = FakePlaces();
    final List<PlaceChoice> log = await _open(t, places);
    await _pick(t, 0, 'Dar es Salaam');
    await _pick(t, 1, 'Kinondoni');
    await _pick(t, 2, 'Mikocheni');
    await _pick(t, 3, 'Mikocheni A');

    await _pick(t, 0, 'Arusha');

    final PlaceChoice c = log.last;
    expect(c.region, 'Arusha');
    expect(<String?>[c.district, c.ward, c.street], <String?>[null, null, null]);
    expect(find.text('Kinondoni'), findsNothing);
    expect(find.text('Mikocheni A'), findsNothing);
  });

  testWidgets('the search box narrows the list', (t) async {
    await _open(t, FakePlaces());
    await _pick(t, 0, 'Dar es Salaam');
    await _pick(t, 1, 'Kinondoni');

    await t.tap(_select(2));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('place_option_111')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('place_option_112')), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey<String>('place_search')), 'msa');
    await t.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('place_option_112')), findsOneWidget, reason: 'Msasani');
    expect(find.byKey(const ValueKey<String>('place_option_111')), findsNothing, reason: 'Mikocheni does not match');

    await t.enterText(find.byKey(const ValueKey<String>('place_search')), 'zzz');
    await t.pumpAndSettle();
    expect(find.textContaining('Nothing matches'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('place_type_it')), findsOneWidget, reason: 'the way out is still there');
  });

  testWidgets('a place that is not in the list is typed, and the levels under it are typed too', (t) async {
    final List<PlaceChoice> log = await _open(t, FakePlaces());

    await t.tap(_select(0));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('place_type_it')));
    await t.pumpAndSettle();

    expect(_text(0), findsOneWidget);
    await t.enterText(_text(0), 'Kigoma');
    await t.pump();
    expect(log.last.region, 'Kigoma');

    // there is no list for a region that was typed: the rest is typed as well
    expect(_text(1), findsOneWidget);
    await t.enterText(_text(1), 'Kigoma Ujiji');
    await t.pump();
    await t.enterText(_text(2), 'Mwanga');
    await t.pump();
    await t.enterText(_text(3), 'Katubuka');
    await t.pump();

    final PlaceChoice c = log.last;
    expect(<String?>[c.region, c.district, c.ward, c.street], <String?>['Kigoma', 'Kigoma Ujiji', 'Mwanga', 'Katubuka']);
  });

  testWidgets('a level the list has nothing for is a box to type in, without anyone asking for it', (t) async {
    final List<PlaceChoice> log = await _open(t, FakePlaces());
    await _pick(t, 0, 'Dar es Salaam');
    await _pick(t, 1, 'Ilala'); // Ilala has no wards in the data

    expect(_text(2), findsOneWidget);
    await t.enterText(_text(2), 'Gerezani');
    await t.pump();
    await t.enterText(_text(3), 'Mtaa wa Kariakoo');
    await t.pump();

    final PlaceChoice c = log.last;
    expect(<String?>[c.region, c.district, c.ward, c.street], <String?>['Dar es Salaam', 'Ilala', 'Gerezani', 'Mtaa wa Kariakoo']);
  });

  testWidgets('a list that cannot be loaded does not stop anyone: the place is typed', (t) async {
    final List<PlaceChoice> log = await _open(t, FakePlaces());
    await _pick(t, 0, 'Arusha'); // its districts fail to load

    expect(_text(1), findsOneWidget);
    await t.enterText(_text(1), 'Arusha CBD');
    await t.pump();

    expect(log.last.district, 'Arusha CBD');
  });

  testWidgets('with no lists at all every level is typed', (t) async {
    final List<PlaceChoice> log = await _open(t, const NoPlaces());

    expect(_text(0), findsOneWidget);
    await t.enterText(_text(0), 'Dodoma');
    await t.pump();
    await t.enterText(_text(1), 'Dodoma Urban');
    await t.pump();

    expect(<String?>[log.last.region, log.last.district], <String?>['Dodoma', 'Dodoma Urban']);
  });

  testWidgets('a typed level can go back to the list when there is one', (t) async {
    final List<PlaceChoice> log = await _open(t, FakePlaces());
    await _pick(t, 0, 'Dar es Salaam');
    await _pick(t, 1, 'Kinondoni');
    await t.tap(_select(2));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('place_type_it')));
    await t.pumpAndSettle();
    await t.enterText(_text(2), 'Somewhere');
    await t.pump();
    expect(log.last.ward, 'Somewhere');

    await t.tap(find.byKey(const ValueKey<String>('place_list_2')));
    await t.pumpAndSettle();

    expect(_select(2), findsOneWidget, reason: 'the list is back');
    expect(log.last.ward, isNull, reason: 'what was typed is dropped');
  });

  testWidgets('everything is optional: nothing chosen means nothing is kept', (t) async {
    final List<PlaceChoice> log = await _open(t, FakePlaces());

    await _pick(t, 0, 'Dar es Salaam');
    await t.tap(_select(1));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('place_type_it')));
    await t.pumpAndSettle();
    await t.enterText(_text(1), '   ');
    await t.pump();

    expect(log.last.district, isNull, reason: 'blanks are not a value');
  });

  testWidgets('in Swahili the fields are named Mkoa, Wilaya, Kata and Mtaa / Kijiji', (t) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalizationService.instance.changeLanguage('sw');
    addTearDown(() => LocalizationService.instance.changeLanguage('en'));
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<LocalizationService>.value(
        value: LocalizationService.instance,
        child: ScreenUtilInit(
          designSize: const Size(800, 1600),
          builder: (_, __) => MaterialApp(home: Scaffold(body: PlacePicker(source: FakePlaces(), onChanged: (_) {}))),
        ),
      ),
    );
    await t.pumpAndSettle();

    for (final String label in <String>['Mkoa', 'Wilaya', 'Kata', 'Mtaa / Kijiji']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Chagua mkoa kwanza'), findsOneWidget);
  });
}
