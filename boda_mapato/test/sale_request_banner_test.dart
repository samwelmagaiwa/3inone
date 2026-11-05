import 'package:boda_mapato/models/user_permissions.dart';
import 'package:boda_mapato/modules/inventory/models/inv_depot_models.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/screens/sales/sales_screen.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/services/localization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Canned answers: one sale, and the request the accountant wrote on it. Records what is posted.
class _FakeApi extends ApiService {
  final List<String> posted = <String>[];

  @override
  Future<Map<String, dynamic>?> getOrNull(String endpoint, {bool requireAuth = true}) async {
    if (endpoint.startsWith('/inventory/returns')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 9, 'reference': 'R-9', 'sale_id': 5, 'sale_number': 'S-20261105-0074', 'type': 'cancellation', 'amount': 80000, 'reason': 'nisaidie kufuta hili', 'status': 'pending', 'requested_by_name': 'ivan samwel', 'created_at': '2026-11-05 10:00:00'},
        ],
      };
    }
    if (endpoint.startsWith('/inventory/sales')) {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 5, 'number': 'S-20261105-0074', 'payment_status': 'partial', 'subtotal': 80000, 'discount': 0, 'tax': 0, 'total': 80000, 'paid_total': 50000, 'created_at': DateTime.now().toIso8601String(), 'customer_name': 'Sara Mfinanga', 'items': <dynamic>[]},
        ],
      };
    }
    return <String, dynamic>{'data': <dynamic>[]};
  }

  @override
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data, {bool requireAuth = true}) async {
    posted.add('$endpoint ${data['decision']}');
    return <String, dynamic>{'message': 'ok'};
  }
}

class _OwnerAuth extends AuthProvider {
  @override
  UserPermissions get permissions => const UserPermissions.fromList(<String>['inv_create_sales', 'inv_manage_sales', 'inv_cancel_sales', 'inv_return_sales']);
}

class _AccountantAuth extends AuthProvider {
  @override
  UserPermissions get permissions => const UserPermissions.fromList(<String>['inv_create_sales', 'inv_manage_sales']);
}

Future<_FakeApi> _pump(WidgetTester t, AuthProvider auth) async {
  final void Function(FlutterErrorDetails)? original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    if (d.exceptionAsString().contains('overflowed')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
  t.view.physicalSize = const Size(1170, 3200);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);

  final _FakeApi api = _FakeApi();
  await t.pumpWidget(
    MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<InventoryProvider>(create: (_) => InventoryProvider(api: api)),
        ChangeNotifierProvider<DepotProvider>(create: (_) => DepotProvider(api: api)),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<LocalizationService>.value(value: LocalizationService.instance),
      ],
      child: ScreenUtilInit(designSize: const Size(390, 844), builder: (_, __) => const MaterialApp(home: Scaffold(body: SalesScreen()))),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.text(LocalizationService.instance.translate('sales_history')));
  await t.pumpAndSettle();

  return api;
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  testWidgets('the owner sees the accountant\'s request on that sale, with who asked and the comment, and can approve it', (t) async {
    final _FakeApi api = await _pump(t, _OwnerAuth());

    expect(_key('sale_request_9'), findsOneWidget);
    expect(find.textContaining('nisaidie kufuta hili'), findsOneWidget);
    expect(find.textContaining('ivan samwel'), findsOneWidget);

    // A card asks first; saying no does nothing.
    await t.ensureVisible(_key('sale_request_approve_9'));
    await t.tap(_key('sale_request_approve_9'));
    await t.pumpAndSettle();
    expect(_key('sale_request_confirm'), findsOneWidget);
    expect(api.posted, isEmpty);
    await t.tap(_key('sale_request_confirm_no'));
    await t.pumpAndSettle();
    expect(api.posted, isEmpty);

    // Saying yes sends the decision.
    await t.tap(_key('sale_request_approve_9'));
    await t.pumpAndSettle();
    await t.tap(_key('sale_request_confirm_yes'));
    await t.pumpAndSettle();
    expect(api.posted, contains('/inventory/returns/9/decide approved'));
    await t.pump(const Duration(seconds: 6)); // the "it was deleted" message goes away
  });

  testWidgets('the accountant sees the request waiting but has no buttons to decide it, and no delete button', (t) async {
    await _pump(t, _AccountantAuth());

    expect(_key('sale_request_9'), findsOneWidget);
    expect(_key('sale_request_approve_9'), findsNothing);
    expect(_key('sale_request_reject_9'), findsNothing);
    expect(find.byIcon(Icons.cancel_outlined), findsNothing);
  });

  test('a request carries what the sale was for: customer, date, items and who asked', () {
    final InvSaleReturn r = InvSaleReturn.fromJson(<String, dynamic>{
      'id': 9, 'reference': 'R-9', 'sale_id': 5, 'sale_number': 'S-1', 'type': 'cancellation', 'amount': 80000, 'reason': 'nisaidie kufuta hili', 'status': 'pending',
      'requested_by_name': 'ivan samwel', 'customer_name': 'Sara Mfinanga', 'items_summary': 'Braids x1, Gel x2', 'sale_date': '2026-11-05 14:59:00', 'created_at': '2026-11-05 15:00:00',
    });

    expect(r.requestedByName, 'ivan samwel');
    expect(r.customerName, 'Sara Mfinanga');
    expect(r.itemsSummary, 'Braids x1, Gel x2');
    expect(r.saleDate?.day, 5);
    expect(r.isPending, isTrue);
  });
}
