import 'package:boda_mapato/models/login_response.dart';
import 'package:boda_mapato/modules/inventory/models/inv_depot_models.dart';
import 'package:boda_mapato/modules/inventory/providers/depot_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/inventory_provider.dart';
import 'package:boda_mapato/modules/inventory/providers/notifications_provider.dart';
import 'package:boda_mapato/providers/auth_provider.dart';
import 'package:boda_mapato/providers/dashboard_provider.dart';
import 'package:boda_mapato/providers/debts_provider.dart';
import 'package:boda_mapato/providers/device_provider.dart';
import 'package:boda_mapato/services/api_service.dart';
import 'package:boda_mapato/providers/maintenance_provider.dart';
import 'package:boda_mapato/providers/rental_provider.dart';
import 'package:boda_mapato/providers/transaction_provider.dart';
import 'package:boda_mapato/widgets/business_state_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Someone signing in, signing out or being replaced, driven by the test.
class _Auth extends AuthProvider {
  String? _id;

  @override
  bool get isAuthenticated => _id != null;

  @override
  UserData? get user => _id == null
      ? null
      : UserData(id: _id!, name: 'User $_id', email: '$_id@example.test', role: 'admin', isActive: true);

  void signInAs(String? id) {
    _id = id;
    notifyListeners();
  }

  /// A change that has nothing to do with who is signed in (a refreshed token, a loading flag).
  void unrelatedChange() => notifyListeners();
}

void main() {
  late _Auth auth;
  late Map<String, Object> seen;

  /// Reads every business provider from inside the scope on each build.
  Widget host() => ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          home: BusinessStateScope(
            child: Builder(
              builder: (BuildContext context) {
                seen = <String, Object>{
                  'transactions': context.read<TransactionProvider>(),
                  'devices': context.read<DeviceProvider>(),
                  'debts': context.read<DebtsProvider>(),
                  'dashboard': context.read<DashboardProvider>(),
                  'inventory': context.read<InventoryProvider>(),
                  'depot': context.read<DepotProvider>(),
                  'notifications': context.read<NotificationsProvider>(),
                  'rental': context.read<RentalProvider>(),
                  'maintenance': context.read<MaintenanceProvider>(),
                };

                return const SizedBox();
              },
            ),
          ),
        ),
      );

  setUp(() {
    auth = _Auth();
    BusinessStateScope.forgetWhoForTest();
    ApiService.clearBranch();
    ApiService.activeService = null;
  });
  tearDown(() {
    ApiService.clearBranch();
    ApiService.activeService = null;
  });

  testWidgets('every business provider is available inside the scope', (t) async {
    await t.pumpWidget(host());

    expect(seen.keys, hasLength(9));
  });

  testWidgets('the same person keeps the same providers, whatever else changes', (t) async {
    auth.signInAs('asha');
    await t.pumpWidget(host());
    final Map<String, Object> before = Map<String, Object>.of(seen);

    auth.unrelatedChange();
    await t.pump();
    auth.signInAs('asha'); // signing in "again" as the same person is not a change of person
    await t.pump();

    for (final String name in before.keys) {
      expect(identical(seen[name], before[name]), isTrue, reason: '$name was recreated for the same person');
    }
  });

  testWidgets('a different person gets brand-new providers, none of the previous one\'s', (t) async {
    auth.signInAs('asha');
    await t.pumpWidget(host());
    final Map<String, Object> asha = Map<String, Object>.of(seen);

    auth.signInAs('juma');
    await t.pump();

    for (final String name in asha.keys) {
      expect(identical(seen[name], asha[name]), isFalse, reason: '$name carried over from the previous person');
    }
  });

  testWidgets('signing out clears them too, and so does signing in afterwards', (t) async {
    auth.signInAs('asha');
    await t.pumpWidget(host());
    final Object ashaInventory = seen['inventory']!;

    auth.signInAs(null);
    await t.pump();
    final Object signedOut = seen['inventory']!;
    expect(identical(signedOut, ashaInventory), isFalse, reason: 'nothing of Asha\'s is left once she signs out');

    auth.signInAs('asha');
    await t.pump();
    expect(identical(seen['inventory'], ashaInventory), isFalse, reason: 'signing back in starts clean, not from stale lists');
    expect(identical(seen['inventory'], signedOut), isFalse);
  });

  testWidgets('what one business had loaded is gone when another business signs in', (t) async {
    auth.signInAs('asha');
    await t.pumpWidget(host());
    (seen['depot']! as DepotProvider).seedForTest(
      suppliers: const <InvSupplier>[InvSupplier(id: 1, name: 'Asha\'s Wholesaler')],
    );
    expect((seen['depot']! as DepotProvider).suppliers, hasLength(1));

    auth.signInAs('juma');
    await t.pump();

    expect((seen['depot']! as DepotProvider).suppliers, isEmpty, reason: 'Juma must not see Asha\'s suppliers, even for a moment');
  });

  testWidgets('the branch and the service one business had open are not the next business', (t) async {
    auth.signInAs('asha');
    await t.pumpWidget(host());
    ApiService.activeService = 'salon';
    ApiService.chooseBranch(7, 'Asha Kariakoo', service: 'salon');

    auth.signInAs('juma');
    await t.pump();

    expect(ApiService.activeBranch, isNull, reason: 'Juma looks at his whole business');
    expect(ApiService.activeBranchName, isNull);
    expect(ApiService.activeService, isNull, reason: 'Juma chooses his own service');
  });

  testWidgets('signing out forgets them too', (t) async {
    auth.signInAs('asha');
    await t.pumpWidget(host());
    ApiService.activeService = 'inventory';
    ApiService.chooseBranch(3, 'Main', service: 'inventory');

    auth.signInAs(null);
    await t.pump();

    expect(ApiService.activeBranch, isNull);
    expect(ApiService.activeService, isNull);
  });

  testWidgets('the same person keeps them, whatever else changes', (t) async {
    auth.signInAs('asha');
    await t.pumpWidget(host());
    ApiService.activeService = 'salon';
    ApiService.chooseBranch(7, 'Asha Kariakoo', service: 'salon');

    auth.unrelatedChange();
    await t.pump();

    expect(ApiService.activeBranch, 7);
    expect(ApiService.activeService, 'salon');
  });

  testWidgets('an app that starts with a session already restored keeps what that session chose', (t) async {
    ApiService.activeService = 'inventory';
    ApiService.chooseBranch(4, 'Restored', service: 'inventory');
    auth.signInAs('asha');

    await t.pumpWidget(host());

    expect(ApiService.activeBranch, 4);
    expect(ApiService.activeService, 'inventory');
  });
}
