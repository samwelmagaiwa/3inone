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

    return KeyedSubtree(
      key: ValueKey<String>(who ?? 'signed-out'),
      child: MultiProvider(providers: providers(), child: child),
    );
  }
}
