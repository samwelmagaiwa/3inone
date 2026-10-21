import 'package:boda_mapato/modules/inventory/models/inv_product.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/cashbook_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/insights_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/queue_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/salon_settings_screen.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/service_materials_screen.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends ApiService {
  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async => <String, dynamic>{'data': <dynamic>[]};
}

class _FakeSalon extends SalonApi {
  final List<(DateTime, DateTime)> asked = <(DateTime, DateTime)>[];
  final List<Map<String, dynamic>> moves = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> counts = <Map<String, dynamic>>[];
  final List<int> deletedMoves = <int>[];
  double countDifference = -500;

  @override
  Future<Map<String, dynamic>> cashbook(DateTime from, DateTime to) async {
    asked.add((from, to));
    return <String, dynamic>{
      'places': <String, dynamic>{
        'cash': <String, dynamic>{
          'opening': 1000, 'in': 13000, 'out': 2000, 'closing': 12000,
          'days': <Map<String, dynamic>>[
            <String, dynamic>{'date': '2026-11-02', 'in': 13000, 'out': 2000, 'closing': 12000, 'count': <String, dynamic>{'counted': 11500, 'expected': 12000, 'difference': -500}},
          ],
        },
        'mobile': <String, dynamic>{'opening': 0, 'in': 5000, 'out': 0, 'closing': 5000, 'days': <dynamic>[]},
        'bank': <String, dynamic>{'opening': 0, 'in': 0, 'out': 0, 'closing': 0, 'days': <dynamic>[]},
      },
      'total': <String, dynamic>{'opening': 1000, 'closing': 17000},
      'moves': <Map<String, dynamic>>[<String, dynamic>{'id': 4, 'kind': 'owner_deposit', 'method': 'cash', 'amount': 3000, 'moved_on': '2026-11-02', 'note': 'Float'}],
    };
  }

  @override
  Future<void> addCashMove({required String kind, required String method, required double amount, String? note}) async => moves.add(<String, dynamic>{'kind': kind, 'method': method, 'amount': amount});

  @override
  Future<void> deleteCashMove(int id) async => deletedMoves.add(id);

  @override
  Future<Map<String, dynamic>> countCash({required String method, required double counted, String? note}) async {
    counts.add(<String, dynamic>{'method': method, 'counted': counted});
    return <String, dynamic>{'expected': counted - countDifference, 'difference': countDifference};
  }

  // queue
  List<Map<String, dynamic>> queueRows = <Map<String, dynamic>>[
    <String, dynamic>{'id': 1, 'name': 'Neema', 'status': 'serving', 'arrived_at': '09:10', 'service': 'Braids'},
    <String, dynamic>{'id': 2, 'name': 'Rehema', 'status': 'waiting', 'arrived_at': '09:20', 'position': 1, 'wait_minutes': 90},
  ];
  final List<(int, String)> statuses = <(int, String)>[];
  final List<Map<String, dynamic>> arrivals = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> queue() async => <String, dynamic>{'queue': queueRows, 'waiting': 1, 'serving': 1, 'done': 0, 'left': 0};

  @override
  Future<void> setQueueStatus(int id, String status) async => statuses.add((id, status));

  @override
  Future<void> addToQueue({required String name, String? phone, int? productId, String? staffId, String? note}) async => arrivals.add(<String, dynamic>{'name': name, 'phone': phone, 'product_id': productId});

  // insights
  final List<int> monthsAsked = <int>[];

  @override
  Future<Map<String, dynamic>> analytics({int months = 6}) async {
    monthsAsked.add(months);
    return <String, dynamic>{
      'trend': <Map<String, dynamic>>[
        <String, dynamic>{'month': '2026-11', 'revenue': 126000, 'net_profit': 51000, 'visits': 12, 'clients': 8, 'new_clients': 3, 'returning_clients': 5},
      ],
      'retention': <String, dynamic>{'eligible': 10, 'came_back': 6, 'rate': 60.0, 'days': 60},
      'busiest': <String, dynamic>{
        'weekdays': <Map<String, dynamic>>[for (int d = 1; d <= 7; d++) <String, dynamic>{'day': d, 'visits': d == 6 ? 9 : 2}],
        'hours': <Map<String, dynamic>>[<String, dynamic>{'hour': 10, 'visits': 5}],
      },
      'top_services': <Map<String, dynamic>>[<String, dynamic>{'name': 'Braids', 'times': 7, 'total': 280000}],
    };
  }

  // materials
  List<Map<String, dynamic>> materials = <Map<String, dynamic>>[
    <String, dynamic>{'material_product_id': 8, 'name': 'Shampoo', 'quantity': 2},
  ];
  List<Map<String, dynamic>>? savedMaterials;

  @override
  Future<List<Map<String, dynamic>>> serviceMaterials(int serviceId) async => materials;

  @override
  Future<void> saveServiceMaterials(int serviceId, List<Map<String, dynamic>> items) async => savedMaterials = items;

  // presets + settings
  Map<String, dynamic> presetAnswer = <String, dynamic>{'added': <String>['Hair', 'Nails'], 'already': 9};

  @override
  Future<Map<String, dynamic>> addCategoryPresets() async => presetAnswer;

  @override
  Future<Map<String, dynamic>> salonSettingsMap() async => <String, dynamic>{'cancel_hours': 24};

  bool loyaltyMissing = false;

  @override
  Future<Map<String, dynamic>> loyaltySettings() async {
    if (loyaltyMissing) throw Exception('API endpoint not found');

    return <String, dynamic>{'on': false, 'per': 1000, 'value': 50, 'referral': 5};
  }
}

InvProduct _goods(int id, String name) => InvProduct(id: id, name: name, sku: 'S-$id', category: '', costPrice: 100, sellingPrice: 200, unit: 'pcs', quantity: 5, minStock: 0, status: 'active', barcode: '', createdBy: 1);

Future<void> _pump(WidgetTester t, Widget screen) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage('en');
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final InventoryProvider inv = InventoryProvider(api: _Api());
  addTearDown(inv.dispose);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: MaterialApp(home: Scaffold(body: screen)),
    ),
  );
  await t.pump();
  await t.pump();
}

void main() {
  group('cashbook', () {
    testWidgets('shows each place with what should be held, and follows the period', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _pump(t, CashbookScreen(api: api, today: DateTime(2026, 11, 15)));
      expect(api.asked.single, (DateTime(2026, 11), DateTime(2026, 11, 15)));
      expect(find.text('Should be held: TSH 12,000'), findsOneWidget);
      expect(find.text('Should be held: TSH 5,000'), findsOneWidget);

      await t.tap(find.byKey(const Key('cb_last')));
      await t.pump();
      await t.pump();
      expect(api.asked.last, (DateTime(2026, 10), DateTime(2026, 10, 31)));
      await t.tap(find.byKey(const Key('cb_today')));
      await t.pump();
      await t.pump();
      expect(api.asked.last, (DateTime(2026, 11, 15), DateTime(2026, 11, 15)));
    });

    testWidgets('a day with a count shows the counted amount and the difference', (t) async {
      await _pump(t, CashbookScreen(api: _FakeSalon(), today: DateTime(2026, 11, 15)));
      await t.tap(find.byKey(const Key('cb_place_cash')));
      await t.pumpAndSettle();
      expect(find.textContaining('Counted TSH 11,500'), findsOneWidget);
      expect(find.text('− TSH 500'), findsOneWidget);
    });

    testWidgets('the owner puts money in, with the amount checked first', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _pump(t, CashbookScreen(api: api, today: DateTime(2026, 11, 15)));
      await t.tap(find.byKey(const Key('cb_move')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('mv_save')));
      await t.pump();
      expect(find.text('Enter an amount.'), findsOneWidget);
      await t.tap(find.byKey(const Key('mv_owner_withdrawal')));
      await t.tap(find.byKey(const Key('mv_place_bank')));
      await t.enterText(find.byKey(const Key('mv_amount')), '20,000');
      await t.tap(find.byKey(const Key('mv_save')));
      await t.pumpAndSettle();
      expect(api.moves.single, <String, dynamic>{'kind': 'owner_withdrawal', 'method': 'bank', 'amount': 20000.0});
    });

    testWidgets('counting tells the difference plainly', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _pump(t, CashbookScreen(api: api, today: DateTime(2026, 11, 15)));
      await t.tap(find.byKey(const Key('cb_count')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('ct_counted')), '11500');
      await t.tap(find.byKey(const Key('ct_save')));
      await t.pumpAndSettle();
      expect(api.counts.single, <String, dynamic>{'method': 'cash', 'counted': 11500.0});
      expect(find.textContaining('Difference: − TSH 500'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();

      api.countDifference = 0;
      await t.tap(find.byKey(const Key('cb_count')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('ct_counted')), '12000');
      await t.tap(find.byKey(const Key('ct_save')));
      await t.pumpAndSettle();
      expect(find.text('It matches the book.'), findsOneWidget);
    });

    testWidgets('an entry made by mistake is removed with a long press', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _pump(t, CashbookScreen(api: api, today: DateTime(2026, 11, 15)));
      await t.scrollUntilVisible(find.byKey(const Key('cb_move_4')), 200, scrollable: find.byType(Scrollable).first);
      await t.longPress(find.byKey(const Key('cb_move_4')));
      await t.pump();
      expect(api.deletedMoves, <int>[4]);
    });
  });

  group('walk-in queue', () {
    testWidgets('shows the order, the wait and the counts', (t) async {
      await _pump(t, QueueScreen(api: _FakeSalon()));
      expect(find.textContaining('Waiting 1'), findsOneWidget);
      expect(find.text('#1  Rehema'), findsOneWidget);
      expect(find.textContaining('~90 min'), findsOneWidget);
      expect(find.textContaining('Being served'), findsOneWidget);
    });

    testWidgets('start, finish and leave send the right status', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _pump(t, QueueScreen(api: api));
      await t.tap(find.byKey(const Key('queue_start_2')));
      await t.pump();
      await t.tap(find.byKey(const Key('queue_done_1')));
      await t.pump();
      await t.tap(find.byKey(const Key('queue_left_2')));
      await t.pump();
      expect(api.statuses, <(int, String)>[(2, 'serving'), (1, 'done'), (2, 'left')]);
    });

    testWidgets('a finished client has no buttons left', (t) async {
      final _FakeSalon api = _FakeSalon()
        ..queueRows = <Map<String, dynamic>>[<String, dynamic>{'id': 3, 'name': 'Zawadi', 'status': 'done', 'arrived_at': '08:00'}];
      await _pump(t, QueueScreen(api: api));
      expect(find.byKey(const Key('queue_left_3')), findsNothing);
      expect(find.byKey(const Key('queue_start_3')), findsNothing);
    });

    testWidgets('a client who arrived needs a name', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _pump(t, QueueScreen(api: api));
      await t.tap(find.byKey(const Key('queue_add')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('queue_save')));
      await t.pump();
      expect(find.text('Enter a name.'), findsOneWidget);
      await t.enterText(find.byKey(const Key('queue_name')), 'Mwajuma');
      await t.tap(find.byKey(const Key('queue_save')));
      await t.pumpAndSettle();
      expect(api.arrivals.single['name'], 'Mwajuma');
    });
  });

  group('insights', () {
    testWidgets('shows the months, retention, busiest day and best services; the range chips ask again', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _pump(t, InsightsScreen(api: api));
      expect(find.textContaining('2026-11  ·  TSH 126,000'), findsOneWidget);
      expect(find.text('60.0%'), findsOneWidget);
      expect(find.text('Braids'), findsOneWidget);
      expect(find.text('Sat'), findsOneWidget);

      await t.tap(find.byKey(const Key('ins_months_12')));
      await t.pump();
      await t.pump();
      expect(api.monthsAsked, <int>[6, 12]);
    });
  });

  group('goods a service uses', () {
    testWidgets('can be added, changed and saved', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _pump(t, ServiceMaterialsScreen(serviceId: 1, serviceName: 'Braids', api: api, goods: <InvProduct>[_goods(8, 'Shampoo'), _goods(9, 'Dye')]));
      expect(find.byKey(const Key('mat_8')), findsOneWidget);
      expect(find.byKey(const Key('mat_qty_8')), findsOneWidget);

      await t.tap(find.byKey(const Key('mat_plus_8')));
      await t.pump();
      await t.tap(find.byKey(const Key('mat_add')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('mat_pick_8')), findsNothing, reason: 'already in the list');
      await t.tap(find.byKey(const Key('mat_pick_9')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('mat_save')));
      await t.pump();
      expect(api.savedMaterials, <Map<String, dynamic>>[
        <String, dynamic>{'material_product_id': 8, 'quantity': 3},
        <String, dynamic>{'material_product_id': 9, 'quantity': 1},
      ]);
      await t.pump(const Duration(seconds: 4));
    });

    testWidgets('one can be taken off, and the count never goes below one', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _pump(t, ServiceMaterialsScreen(serviceId: 1, serviceName: 'Braids', api: api, goods: <InvProduct>[_goods(8, 'Shampoo')]));
      await t.tap(find.byKey(const Key('mat_minus_8')));
      await t.pump();
      expect(t.widget<Text>(find.byKey(const Key('mat_qty_8'))).data, '1');
      expect(t.widget<IconButton>(find.byKey(const Key('mat_minus_8'))).onPressed, isNull);
      await t.tap(find.byKey(const Key('mat_remove_8')));
      await t.pump();
      expect(find.byKey(const Key('mat_8')), findsNothing);
    });
  });

  group('settings on a server that does not know the loyalty page yet', () {
    testWidgets('the rest of the settings still show, without the loyalty section', (t) async {
      final _FakeSalon api = _FakeSalon()..loyaltyMissing = true;
      await _pump(t, SalonSettingsScreen(api: api));
      expect(find.byKey(const Key('set_cancel')), findsOneWidget);
      expect(find.byKey(const Key('set_presets')), findsOneWidget);
      expect(find.byKey(const Key('set_loyalty')), findsNothing);
      expect(find.byKey(const Key('set_per')), findsNothing);
    });
  });

  group('settings: standard categories', () {
    testWidgets('says how many were added, and that there is nothing new when all are there', (t) async {
      final _FakeSalon api = _FakeSalon();
      await _pump(t, SalonSettingsScreen(api: api));
      await t.ensureVisible(find.byKey(const Key('set_presets')));
      await t.tap(find.byKey(const Key('set_presets')));
      await t.pump();
      await t.pump();
      expect(find.text('2 categories added.'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));

      api.presetAnswer = <String, dynamic>{'added': <String>[], 'already': 11};
      await t.tap(find.byKey(const Key('set_presets')));
      await t.pump();
      await t.pump();
      expect(find.text('All the categories are already there.'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
    });
  });
}
