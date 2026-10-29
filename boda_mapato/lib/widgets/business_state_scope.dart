import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../modules/inventory/providers/depot_provider.dart';
import '../modules/inventory/providers/inventory_provider.dart';
import '../modules/inventory/providers/notifications_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/debts_provider.dart';
import '../providers/device_provider.dart';
import '../providers/maintenance_provider.dart';
import '../providers/rental_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/api_service.dart';

/// Everything in the app that holds one business's data (products, sales, customers, drivers,
/// properties, ...), created for ONE signed-in person and thrown away when that person changes.
///
/// These providers used to be created once, when the app started, and never cleared. On a phone
/// shared between depot staff -- or after an owner signs out and someone from another business
/// signs in -- the new person briefly saw the previous business's cached lists, and a provider
/// that loaded before sign-in kept its empty answer until someone refreshed.
///
/// Keyed by the signed-in user's id: a different person (or signing out) means brand-new
/// providers, which load with the NEW person's token. While the same person stays signed in
/// nothing is recreated.
class BusinessStateScope extends StatelessWidget {
  const BusinessStateScope({super.key, required this.child});

  final Widget child;

  /// Who the scope was last built for (null before the first build). What the app remembers outside the providers (the branch being
  /// looked at, the service open) belongs to that person and is forgotten when another one signs in or this one signs out.
  static String? _lastWho = '#none';

  /// For tests: the next build is the first one again.
  @visibleForTesting
  static void forgetWhoForTest() => _lastWho = '#none';

  /// The providers that hold business data. Anything new that caches a business's records
  /// belongs here, not above it.
  static List<SingleChildWidget> providers() => <SingleChildWidget>[
        ChangeNotifierProvider<TransactionProvider>(
          create: (final BuildContext _) => TransactionProvider(),
        ),
        ChangeNotifierProvider<DeviceProvider>(
          create: (final BuildContext _) => DeviceProvider(),
        ),
        ChangeNotifierProvider<DebtsProvider>(
          create: (final BuildContext _) => DebtsProvider(),
        ),
        ChangeNotifierProvider<DashboardProvider>(
          create: (final BuildContext _) => DashboardProvider()..loadAll(),
        ),
        ChangeNotifierProvider<InventoryProvider>(
          create: (final BuildContext _) => InventoryProvider()..bootstrap(),
        ),
        ChangeNotifierProvider<DepotProvider>(
          create: (final BuildContext _) => DepotProvider(),
        ),
        ChangeNotifierProvider<NotificationsProvider>(
          create: (final BuildContext _) => NotificationsProvider(),
        ),
        ChangeNotifierProvider<RentalProvider>(
          create: (final BuildContext _) => RentalProvider(),
        ),
        ChangeNotifierProvider<MaintenanceProvider>(
          create: (final BuildContext _) => MaintenanceProvider()..fetchRequests(),
        ),
      ];

  @override
  Widget build(final BuildContext context) {
    // Only the identity matters here, so an unrelated change to the auth provider
    // (a refreshed token, a loading flag) does not rebuild everything below.
    final String? who = context.select<AuthProvider, String?>(
      (final AuthProvider auth) => auth.isAuthenticated ? auth.user?.id : null,
    );
    // A business that was held back for an unpaid plan and is open again starts from fresh providers: whatever
    // they asked for while it was held back came back refused.
    final int reopened = context.select<AuthProvider, int>((final AuthProvider auth) => auth.subscriptionReopened);

    // Another person (or nobody): the branch and the service the previous one had open are not theirs. The first build after the
    // app starts keeps whatever the restored session chose.
    if (_lastWho != '#none' && _lastWho != who) {
      ApiService.clearBranch();
      ApiService.activeService = null;
    }
    _lastWho = who;

    return KeyedSubtree(
      key: ValueKey<String>('${who ?? 'signed-out'}#$reopened'),
      child: MultiProvider(providers: providers(), child: child),
    );
  }
}
