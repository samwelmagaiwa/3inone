import 'package:boda_mapato/modules/inventory/screens/trash/trash_screen.dart';
import 'package:boda_mapato/modules/inventory/services/trash_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Trash: deleted records by kind, with Restore and Delete for good; cancelled sales listed for the record.
class _FakeTrash extends TrashApi {
  _FakeTrash();

  final Map<String, List<TrashItem>> byType = <String, List<TrashItem>>{
    'expenses': <TrashItem>[
      TrashItem(id: 1, type: 'expenses', title: 'Charcoal', subtitle: 'transport · 2026-10-28', amount: 6000, deletedAt: DateTime(2026, 10, 29, 9), deletedBy: 'Asha', reason: 'entered twice', canRestore: true, canRemove: true),
      TrashItem(id: 2, type: 'expenses', title: 'Rent', subtitle: 'rent · 2026-10-01', amount: 100000, deletedAt: DateTime(2026, 10, 28), canRestore: true, canRemove: true),
    ],
    'customers': <TrashItem>[TrashItem(id: 7, type: 'customers', title: 'Neema', subtitle: '0712000111', deletedAt: DateTime(2026, 10, 27), canRestore: true, canRemove: true)],
    'debts': <TrashItem>[],
    'products': <TrashItem>[TrashItem(id: 9, type: 'products', title: 'Soda 500ml', subtitle: 'SODA1', amount: 1000, deletedAt: DateTime(2026, 10, 26), canRestore: true, canRemove: true)],
    'sales': <TrashItem>[TrashItem(id: 30, type: 'sales', title: 'S-20261026-0001', subtitle: 'john', amount: 22000, deletedAt: DateTime(2026, 10, 26), reason: 'Wrong goods', canRestore: false, canRemove: false)],
  };

  final List<(String?, int)> asked = <(String?, int)>[];
  final List<(String, int, String?)> restored = <(String, int, String?)>[];
  final List<(String, int)> removed = <(String, int)>[];
  String? restoreFails;
  String? removeFails;
  bool listFails = false;
  int pages = 1;

  Map<String, int> get counts => <String, int>{for (final MapEntry<String, List<TrashItem>> e in byType.entries) e.key: e.value.length};

  @override
  Future<TrashPage> list({final String? type, final int page = 1}) async {
    asked.add((type, page));
    if (listFails) throw ApiException('Server busy');
    final List<TrashItem> rows = type == null ? <TrashItem>[] : (byType[type] ?? <TrashItem>[]);

    return TrashPage(items: page == 1 ? rows : <TrashItem>[TrashItem(id: 99, type: type ?? 'expenses', title: 'Second page', subtitle: '', canRestore: true, canRemove: true)], counts: counts, page: page, lastPage: pages, total: rows.length);
  }

  @override
  Future<void> restore(final String type, final int id, {final String? sku}) async {
    restored.add((type, id, sku));
    if (restoreFails != null && sku == null) throw ApiException(restoreFails!);
    byType[type]?.removeWhere((TrashItem i) => i.id == id);
  }

  @override
  Future<void> remove(final String type, final int id) async {
    removed.add((type, id));
    if (removeFails != null) throw ApiException(removeFails!);
    byType[type]?.removeWhere((TrashItem i) => i.id == id);
  }
}

Future<void> _host(WidgetTester t, TrashApi api, {bool sw = false, String type = 'expenses'}) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<LocalizationService>.value(
      value: LocalizationService.instance,
      child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => MaterialApp(home: Scaffold(body: TrashScreen(api: api, initialType: type)))),
    ),
  );
  await _settle(t);
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('lists what was deleted, with the amount, when, by whom and why, and says what the Trash is', (t) async {
    await _host(t, _FakeTrash());

    expect(_key('trash_intro'), findsOneWidget);
    expect(find.text('Charcoal'), findsOneWidget);
    expect(find.text('TSH 6,000'), findsOneWidget);
    expect(find.textContaining('Deleted · 29/10/2026 · by Asha'), findsOneWidget);
    expect(find.text('Reason: entered twice'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Expenses (2)'), findsOneWidget, reason: 'the count of each kind is on its chip');
    expect(find.text('Customers (1)'), findsOneWidget);
    expect(find.text('Debts'), findsOneWidget, reason: 'no count when it is empty');
  });

  testWidgets('another kind opens when its chip is tapped, and an empty one says so', (t) async {
    final _FakeTrash api = _FakeTrash();
    await _host(t, api);

    await t.tap(find.text('Customers (1)'));
    await _settle(t);
    expect(api.asked.last.$1, 'customers');
    expect(find.text('Neema'), findsOneWidget);
    expect(find.text('Charcoal'), findsNothing);

    await t.ensureVisible(find.text('Debts'));
    await t.tap(find.text('Debts'));
    await _settle(t);
    expect(find.text('Nothing deleted here.'), findsOneWidget);
  });

  testWidgets('Restore brings the record back and the list follows', (t) async {
    final _FakeTrash api = _FakeTrash();
    await _host(t, api);

    await t.tap(_key('trash_restore_1'));
    await _settle(t);

    expect(api.restored.single, ('expenses', 1, null));
    expect(find.text('Charcoal'), findsNothing);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('"Charcoal" was restored.'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('a product whose SKU was taken is restored with a new SKU the owner gives', (t) async {
    final _FakeTrash api = _FakeTrash()..restoreFails = "The SKU 'SODA1' is used by another product now. Give it a new SKU.";
    await _host(t, api, type: 'products');

    await t.tap(_key('trash_restore_9'));
    await _settle(t);
    expect(find.text('Give it a new SKU'), findsOneWidget);

    await t.enterText(_key('trash_new_sku'), 'SODA-OLD');
    await t.tap(_key('trash_new_sku_ok'));
    await _settle(t);

    expect(api.restored, <(String, int, String?)>[('products', 9, null), ('products', 9, 'SODA-OLD')]);
    expect(find.text('Soda 500ml'), findsNothing);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('Delete for good asks first, and Keep it does nothing', (t) async {
    final _FakeTrash api = _FakeTrash();
    await _host(t, api);

    await t.tap(_key('trash_remove_1'));
    await _settle(t);
    expect(find.text('Delete for good?'), findsOneWidget);
    expect(find.textContaining('cannot be brought back'), findsOneWidget);
    await t.tap(_key('trash_remove_no'));
    await _settle(t);

    expect(api.removed, isEmpty);
    expect(find.text('Charcoal'), findsOneWidget);
  });

  testWidgets('Delete for good removes it once confirmed', (t) async {
    final _FakeTrash api = _FakeTrash();
    await _host(t, api);

    await t.tap(_key('trash_remove_1'));
    await _settle(t);
    await t.tap(_key('trash_remove_yes'));
    await _settle(t);

    expect(api.removed.single, ('expenses', 1));
    expect(find.text('Charcoal'), findsNothing);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets("when the server refuses (the record has history) the reason is shown and it stays", (t) async {
    final _FakeTrash api = _FakeTrash()..removeFails = 'It has been sold or stocked, so it stays in the Trash for your records.';
    await _host(t, api, type: 'products');

    await t.tap(_key('trash_remove_9'));
    await _settle(t);
    await t.tap(_key('trash_remove_yes'));
    await _settle(t);

    expect(find.text('It has been sold or stocked, so it stays in the Trash for your records.'), findsOneWidget);
    expect(find.text('Soda 500ml'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('cancelled sales are shown for the record, with the reason, and cannot be restored or removed', (t) async {
    await _host(t, _FakeTrash(), type: 'sales');

    expect(find.text('S-20261026-0001'), findsOneWidget);
    expect(find.text('Reason: Wrong goods'), findsOneWidget);
    expect(_key('trash_sales_note'), findsOneWidget);
    expect(_key('trash_restore_30'), findsNothing);
    expect(_key('trash_remove_30'), findsNothing);
    expect(find.textContaining('Cancelled · 26/10/2026'), findsOneWidget);
  });

  testWidgets('Show more adds the next page', (t) async {
    final _FakeTrash api = _FakeTrash()..pages = 2;
    await _host(t, api);

    await t.ensureVisible(_key('trash_more'));
    await t.tap(_key('trash_more'));
    await _settle(t);

    expect(api.asked.last.$2, 2);
    expect(find.text('Charcoal'), findsOneWidget);
    expect(find.text('Second page'), findsOneWidget);
    expect(_key('trash_more'), findsNothing);
  });

  testWidgets('a failed read says why and can be retried', (t) async {
    final _FakeTrash api = _FakeTrash()..listFails = true;
    await _host(t, api);
    expect(find.text('Server busy'), findsOneWidget);

    api.listFails = false;
    await t.tap(_key('trash_retry'));
    await _settle(t);
    expect(find.text('Charcoal'), findsOneWidget);
  });

  testWidgets('Swahili', (t) async {
    await _host(t, _FakeTrash(), sw: true);

    expect(find.text('Matumizi (2)'), findsOneWidget);
    expect(find.text('Rudisha'), findsWidgets);
    expect(find.text('Futa kabisa'), findsWidgets);
    expect(find.textContaining('Ilifutwa · 29/10/2026 · na Asha'), findsOneWidget);
  });
}
