import 'package:boda_mapato/modules/groups/models/group_models.dart';
import 'package:boda_mapato/modules/groups/screens/group_dashboard_screen.dart';
import 'package:boda_mapato/modules/groups/screens/widgets/group_tile_grid.dart';
import 'package:boda_mapato/modules/groups/services/groups_api.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/joined_sections.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends GroupsApi {
  _Api({this.empty = false});

  final bool empty;

  @override
  Future<List<GroupTransaction>> myTransactions() async => empty
      ? <GroupTransaction>[]
      : <GroupTransaction>[
          for (int i = 1; i <= 3; i++)
            GroupTransaction.fromJson(<String, dynamic>{
              'id': i, 'reference': 'TRX-$i', 'receipt_number': 'RC-00000$i', 'category': 'savings', 'direction': 'in', 'amount': 10000 * i, 'method': 'mpesa',
              'external_ref': 'MP$i', 'paid_on': '2026-11-2$i', 'status': 'verified', 'member_name': 'Asha Juma',
            }),
        ];
}

Future<void> _pump(final WidgetTester t, final Widget child) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(411, 1400), minTextAdapt: true, builder: (_, __) => MaterialApp(home: KeyedSubtree(key: UniqueKey(), child: child))),
    ),
  );
  await t.pumpAndSettle();
}

List<GroupGridTile> _tiles(final int n, {final List<String>? taps}) => <GroupGridTile>[
      for (int i = 1; i <= n; i++)
        GroupGridTile(tileKey: Key('tile_$i'), icon: Icons.star_rounded, color: Colors.orange, label: 'Tile $i', badge: i == 1 ? 7 : 0, onTap: () => taps?.add('tile_$i')),
    ];

void main() {
  testWidgets('the tiles are set out like the inventory dashboard: a thin vertical line between the tiles of a row, the glowing line between rows', (final WidgetTester t) async {
    final List<String> taps = <String>[];
    await _pump(t, Scaffold(body: SingleChildScrollView(child: GroupTileGrid(dividerKey: 'g', columns: 3, tiles: _tiles(9, taps: taps)))));

    // 3 rows of 3: two vertical lines in each row, two glowing lines between the rows.
    final Finder vertical = find.byWidgetPredicate((final Widget w) => w is Container && w.constraints?.minWidth == 1 && w.constraints?.maxWidth == 1);
    expect(vertical, findsNWidgets(6));
    expect(find.byType(SectionGlowDivider), findsNWidgets(2));
    expect(find.byKey(const ValueKey<String>('g_1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('g_2')), findsOneWidget);
    expect(find.text('7'), findsOneWidget, reason: 'the count badge on the first tile');

    await t.tap(find.byKey(const Key('tile_5')));
    expect(taps, <String>['tile_5']);
  });

  testWidgets('a last row that is not full keeps its columns, and a footer button sits under a glowing line', (final WidgetTester t) async {
    await _pump(
      t,
      Scaffold(
        body: SingleChildScrollView(
          child: GroupTileGrid(
            dividerKey: 'g',
            columns: 3,
            tiles: _tiles(4),
            footer: FilledButton(key: const Key('footer'), onPressed: () {}, child: const Text('Pay')),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('tile_4')), findsOneWidget);
    expect(find.byKey(const Key('footer')), findsOneWidget);
    expect(find.byType(SectionGlowDivider), findsNWidgets(2), reason: 'one between the two rows, one above the footer');
    expect(t.takeException(), isNull);
  });

  testWidgets('figure tiles show the value and what it counts', (final WidgetTester t) async {
    await _pump(
      t,
      Scaffold(body: GroupTileGrid(tiles: <GroupGridTile>[const GroupGridTile(icon: Icons.savings_rounded, color: Colors.green, label: 'My savings', value: '100K')])),
    );
    expect(find.text('100K'), findsOneWidget);
    expect(find.text('My savings'), findsOneWidget);
  });

  testWidgets('"My latest payments" is its own screen: what was sent, newest first, or a calm line when nothing was', (final WidgetTester t) async {
    await _pump(t, MyPaymentsScreen(api: _Api()));
    expect(find.text('My latest payments'), findsWidgets);
    expect(find.byKey(const Key('grp_tx_1')), findsOneWidget);
    expect(find.byKey(const Key('grp_tx_3')), findsOneWidget);

    await _pump(t, MyPaymentsScreen(api: _Api(empty: true)));
    expect(find.text('No payments sent yet.'), findsOneWidget);
  });

  testWidgets('the waiting screen lists what has a count, says so when nothing waits, and a tap closes it before opening the line', (final WidgetTester t) async {
    final List<String> opened = <String>[];
    List<Widget> lines(final void Function(VoidCallback go) go) => <Widget>[
          ListTile(key: const Key('line_a'), title: const Text('Payments to verify'), onTap: () => go(() => opened.add('payments'))),
        ];
    await _pump(
      t,
      Builder(builder: (final BuildContext c) => Scaffold(body: Center(child: TextButton(key: const Key('open'), onPressed: () => Navigator.push<void>(c, MaterialPageRoute<void>(builder: (_) => WaitingScreen(sw: false, linesFor: lines))), child: const Text('open'))))),
    );
    await t.tap(find.byKey(const Key('open')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('line_a')), findsOneWidget);
    await t.tap(find.byKey(const Key('line_a')));
    await t.pumpAndSettle();
    expect(opened, <String>['payments']);
    expect(find.byKey(const Key('line_a')), findsNothing, reason: 'the screen closed');

    await t.tap(find.byKey(const Key('open')));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    await _pump(
      t,
      Builder(builder: (final BuildContext c) => Scaffold(body: Center(child: TextButton(key: const Key('open'), onPressed: () => Navigator.push<void>(c, MaterialPageRoute<void>(builder: (_) => WaitingScreen(sw: false, linesFor: (_) => <Widget>[]))), child: const Text('open'))))),
    );
    await t.tap(find.byKey(const Key('open')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('grp_wait_none')), findsOneWidget);
  });
}
