import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/products/products_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/widgets/pager_bar.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A server with [count] products, ids count .. 1, 100 to a page like the real one.
class _Server extends ApiService {
  _Server(this.count);

  final int count;

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/products')) {
      final Uri u = Uri.parse(endpoint);
      final int page = int.tryParse(u.queryParameters['page'] ?? '1') ?? 1;
      final int per = (int.tryParse(u.queryParameters['per_page'] ?? '') ?? 20).clamp(1, 100);
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          for (int i = (page - 1) * per; i < page * per && i < count; i++)
            <String, dynamic>{'id': count - i, 'name': 'Bidhaa ${count - i}', 'sku': 'SKU-${count - i}', 'cost_price': 100, 'selling_price': 150, 'quantity': 5, 'min_stock': 1, 'status': 'active'},
        ],
        'meta': <String, dynamic>{'current_page': page, 'last_page': count == 0 ? 1 : (count / per).ceil(), 'per_page': per, 'total': count},
      };
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }
}

class _Auth extends AuthProvider {
  @override
  UserData? get user => UserData(id: 'u1', name: 'Owner', email: 'o@example.test', role: 'admin', isActive: true);

  @override
  UserPermissions get permissions => UserPermissions.fromRole('admin');
}

Future<void> _open(final WidgetTester t, final int count) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 6000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  final _Server server = _Server(count);
  final InventoryProvider inv = InventoryProvider(api: server);
  await inv.fetchProducts();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: server)),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(designSize: const Size(800, 6000), minTextAdapt: true, builder: (_, __) => const MaterialApp(home: Scaffold(body: ProductsScreen()))),
    ),
  );
  await t.pumpAndSettle();
}

String _showing(final WidgetTester t) => t.widget<Text>(find.byKey(const Key('pager_showing'))).data!;

/// The names 'Bidhaa 1' .. 'Bidhaa 47' as the app lists them: A to Z, so 'Bidhaa 10' comes before 'Bidhaa 2'.
List<String> _az(final int count) => <String>[for (int i = 1; i <= count; i++) 'Bidhaa $i']..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));

void main() {
  test('the numbers shown: the first and last always, the ones around the current page, "…" where pages are left out', () {
    List<int> w(final int total, final int page) => PagerBar(total: total, page: page, pageSize: 10, onPage: (_) {}, onPageSize: (_) {}).window();
    expect(w(0, 0), <int>[0], reason: 'an empty list is one page');
    expect(w(25, 0), <int>[0, 1, 2], reason: 'three pages: all of them');
    expect(w(100, 0), <int>[0, 1, -1, 9], reason: 'ten pages, the first: 1 2 … 10');
    expect(w(100, 5), <int>[0, -1, 4, 5, 6, -1, 9]);
    expect(w(100, 9), <int>[0, -1, 8, 9]);
    expect(w(60, 2), <int>[0, 1, 2, 3, 4, 5], reason: 'one missing page is shown, not "…"');
  });

  testWidgets('all 47 products are on the pages, 20 to a page: the old ones too, none left out', (final WidgetTester t) async {
    await _open(t, 47);
    final List<String> az = _az(47);
    expect(_showing(t), '1-20 of 47');
    expect(find.text(az.first), findsOneWidget, reason: 'A to Z: the first name in the alphabet is first');
    expect(find.text(az[19]), findsOneWidget);
    expect(find.text(az[20]), findsNothing);
    expect(t.widget<Text>(find.byKey(const Key('pager_page_of'))).data, 'Page 1 of 3');

    await t.tap(find.byKey(const Key('pager_page_2')));
    await t.pumpAndSettle();
    expect(_showing(t), '41-47 of 47');
    expect(find.text(az.last), findsOneWidget, reason: 'the last name in the alphabet is on the last page');
    expect(find.text(az[40]), findsOneWidget);
    // Every one of the 47 is on some page: none left out.
    expect(<String>{...az}.length, 47);
    expect(find.byKey(const Key('pager_next')), findsOneWidget);
    expect(t.widget<IconButton>(find.byKey(const Key('pager_next'))).onPressed, isNull, reason: 'no page after the last');
  });

  testWidgets('the numbers are in ONE row beside the arrows (never one under another), as many as the data has pages, also on a narrow phone', (final WidgetTester t) async {
    for (final (int count, int pages) in <(int, int)>[(30, 2), (47, 3), (250, 13)]) {
      await _open(t, count);
      final double row = t.getCenter(find.byKey(const Key('pager_next'))).dy;
      expect(t.getCenter(find.byKey(const Key('pager_first'))).dy, closeTo(row, 1), reason: '$count products: first and next on one line');
      expect(find.byKey(const Key('pager_page_0')), findsOneWidget);
      expect(find.byKey(Key('pager_page_${pages - 1}')), findsOneWidget, reason: 'the last page number is shown');
      expect(find.byKey(Key('pager_page_$pages')), findsNothing, reason: 'no number beyond the pages the data has');
      for (final Element e in find.byWidgetPredicate((Widget w) => w.key is Key && RegExp(r"pager_page_\d+").hasMatch('${w.key}')).evaluate()) {
        expect(t.getCenter(find.byWidget(e.widget)).dy, closeTo(row, 1), reason: '$count products: every number on the same line as the arrows');
      }
    }
    // The row is one row at every width.
    t.view.physicalSize = const Size(360, 3000);
    await t.pumpAndSettle();
    expect(t.getCenter(find.byKey(const Key('pager_first'))).dy, closeTo(t.getCenter(find.byKey(const Key('pager_last'))).dy, 1));
    expect(t.getSize(find.byKey(const Key('pager_row'))).width, lessThanOrEqualTo(360));
  });

  testWidgets('first, previous, next and last move between the pages', (final WidgetTester t) async {
    await _open(t, 47);
    await t.tap(find.byKey(const Key('pager_next')));
    await t.pumpAndSettle();
    expect(_showing(t), '21-40 of 47');
    await t.tap(find.byKey(const Key('pager_last')));
    await t.pumpAndSettle();
    expect(_showing(t), '41-47 of 47');
    await t.tap(find.byKey(const Key('pager_prev')));
    await t.pumpAndSettle();
    expect(_showing(t), '21-40 of 47');
    await t.tap(find.byKey(const Key('pager_first')));
    await t.pumpAndSettle();
    expect(_showing(t), '1-20 of 47');
    expect(t.widget<IconButton>(find.byKey(const Key('pager_prev'))).onPressed, isNull, reason: 'no page before the first');
  });

  testWidgets('the number to a page can be chosen (10, 20, 50, 100) and the list starts again from the first page', (final WidgetTester t) async {
    await _open(t, 47);
    await t.tap(find.byKey(const Key('pager_page_2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pager_size')));
    await t.pumpAndSettle();
    await t.tap(find.text('50').last);
    await t.pumpAndSettle();
    expect(_showing(t), '1-47 of 47', reason: 'all of them on one page, from the first page');
    expect(t.widget<Text>(find.byKey(const Key('pager_page_of'))).data, 'Page 1 of 1');
    expect(find.text('Bidhaa 1'), findsOneWidget);

    await t.tap(find.byKey(const Key('pager_size')));
    await t.pumpAndSettle();
    await t.tap(find.text('10').last);
    await t.pumpAndSettle();
    expect(_showing(t), '1-10 of 47');
    expect(t.widget<Text>(find.byKey(const Key('pager_page_of'))).data, 'Page 1 of 5');
  });

  testWidgets('searching narrows the list and the pages follow; the Swahili words are there too', (final WidgetTester t) async {
    await _open(t, 47);
    await t.tap(find.byKey(const Key('pager_page_2')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Bidhaa 4');
    await t.pumpAndSettle();
    // Bidhaa 4, 40..47: nine products, one page, and the page the person was on is gone: back to the first.
    expect(_showing(t), '1-9 of 9');
    expect(t.widget<Text>(find.byKey(const Key('pager_page_of'))).data, 'Page 1 of 1');

    await LocalizationService.instance.changeLanguage('sw');
    await t.pumpAndSettle();
    expect(_showing(t), '1-9 kati ya 9');
    expect(t.widget<Text>(find.byKey(const Key('pager_page_of'))).data, 'Ukurasa 1 wa 1');
    expect(find.text('Kwa ukurasa'), findsOneWidget);
    await LocalizationService.instance.changeLanguage('en');
  });

  testWidgets('an empty shop shows 0-0 of 0 and one empty page, nothing breaks', (final WidgetTester t) async {
    await _open(t, 0);
    expect(_showing(t), '0-0 of 0');
    expect(t.widget<Text>(find.byKey(const Key('pager_page_of'))).data, 'Page 1 of 1');
    expect(t.widget<IconButton>(find.byKey(const Key('pager_next'))).onPressed, isNull);
  });
}
