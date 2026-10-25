import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/salon/salon_sale_breakdown_card.dart';
import 'package:boda_mapato/modules/inventory/services/salon_api.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A salon sale shows what the service earned apart from the goods: each service (revenue, commission, goods used, profit),
/// each goods line (revenue, cost, profit) and the totals; to the people who see the money only, and never on a shop's sale.
class _Auth extends AuthProvider {
  _Auth(this.role);

  final String role;

  @override
  UserData? get user => UserData(id: 'u1', name: 'Someone', email: 's@example.test', role: role, isActive: true, serviceTypes: const <String>['salon']);
}

class _Api extends SalonApi {
  _Api(this.answer);

  final Map<String, dynamic> answer;
  int asked = 0;

  @override
  Future<Map<String, dynamic>> saleBreakdown(int saleId) async {
    asked++;
    return answer;
  }
}

final Map<String, dynamic> _both = <String, dynamic>{
  'services': <Map<String, dynamic>>[
    <String, dynamic>{
      'name': 'Braids', 'quantity': 1, 'stylist': 'Asha', 'revenue': 40000, 'commission': 4000, 'materials_cost': 6000, 'profit': 30000,
      'materials': <Map<String, dynamic>>[<String, dynamic>{'name': 'Shampoo', 'quantity': 2, 'cost': 6000}],
    },
  ],
  'goods': <Map<String, dynamic>>[
    <String, dynamic>{'name': 'Extensions', 'quantity': 2, 'revenue': 25000, 'cost': 15000, 'profit': 10000},
  ],
  'service_profit': 30000,
  'goods_profit': 10000,
  'profit': 40000,
};

Future<_Api> _open(WidgetTester t, {Map<String, dynamic>? answer, String role = 'admin', bool salon = true, bool sw = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await LocalizationService.instance.changeLanguage(sw ? 'sw' : 'en');
  addTearDown(() => LocalizationService.instance.changeLanguage('en'));
  addTearDown(() => ApiService.activeService = null);
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final InventoryProvider inv = InventoryProvider(api: ApiService())..setSalonMode(salon);
  addTearDown(inv.dispose);
  final _Api api = _Api(answer ?? _both);
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>.value(value: inv),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(role)),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SalonSaleBreakdownCard(saleId: 5, api: api)))),
    ),
  );
  await t.pump();
  await t.pump();

  return api;
}

void main() {
  testWidgets('shows each service and each goods line with what it earned, and the totals', (t) async {
    await _open(t);
    expect(find.byKey(const Key('sale_breakdown')), findsOneWidget);
    expect(find.text('Braids (Asha)'), findsOneWidget);
    expect(find.text('− Commission'), findsOneWidget);
    expect(find.text('− Shampoo ×2'), findsOneWidget);
    expect(find.text('Service profit'), findsOneWidget);
    expect(find.text('Extensions ×2'), findsOneWidget);
    expect(find.text('− Cost of the goods'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('sb_service')), matching: find.text('TSH 30,000')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('sb_goods')), matching: find.text('TSH 10,000')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('sb_total')), matching: find.text('TSH 40,000')), findsOneWidget);
  });

  testWidgets('a sale of services only has no goods section, and a goods-only sale has no services', (t) async {
    await _open(t, answer: <String, dynamic>{'services': _both['services'], 'goods': <dynamic>[], 'service_profit': 30000, 'goods_profit': 0, 'profit': 30000});
    expect(find.byKey(const Key('sb_goods')), findsNothing);
    expect(find.text('Goods'), findsNothing);
    expect(find.byKey(const Key('sb_service')), findsOneWidget);
  });

  testWidgets('in Swahili it is Swahili', (t) async {
    await _open(t, sw: true);
    expect(find.text('Mauzo haya yalipata faida gani'), findsOneWidget);
    expect(find.text('Faida ya huduma'), findsOneWidget);
    expect(find.text('Faida ya mauzo haya'), findsOneWidget);
  });

  testWidgets('a stylist, a shop sale and an empty answer see nothing (and a stylist does not even ask)', (t) async {
    final _Api stylist = await _open(t, role: 'hair_stylist');
    expect(find.byKey(const Key('sale_breakdown')), findsNothing);
    expect(stylist.asked, 0, reason: 'the profit is not asked for by someone who may not see it');
  });

  testWidgets('the shop sees nothing', (t) async {
    final _Api shop = await _open(t, salon: false);
    expect(find.byKey(const Key('sale_breakdown')), findsNothing);
    expect(shop.asked, 0);
  });

  testWidgets('an empty answer shows nothing', (t) async {
    await _open(t, answer: <String, dynamic>{});
    expect(find.byKey(const Key('sale_breakdown')), findsNothing);
  });
}
