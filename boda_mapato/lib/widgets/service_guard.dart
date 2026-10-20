import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/service_selection_screen.dart';
import '../utils/role_services.dart';

/// Wraps a service home screen. If the authenticated user has explicit service
/// bindings and [service] is NOT one of them, the user is redirected to the
/// service picker instead of seeing the protected screen.
///
/// Users with zero bound services (not yet assigned by admin) still see the
/// full picker — no lockout.
class ServiceGuard extends StatelessWidget {
  const ServiceGuard({
    super.key,
    required this.service,
    required this.child,
  });

  /// The service key this screen belongs to ('inventory', 'transport', 'rental', 'salon').
  final String service;

  /// The actual service home screen to show when access is granted.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    // Not logged in — AuthWrapper handles this; show child and let it be
    // replaced on the next frame.
    if (user == null) return child;

    // Only super_admin bypasses service binding enforcement entirely.
    // admin must be explicitly assigned services by a super_admin and is
    // checked through the same binding path as every other role.
    if (user.isSuperAdmin) return child;

    final bound = user.serviceTypes;

    // Determine the effective allowed list: explicit bindings take priority;
    // if none assigned yet, fall back to role-based access.
    final List<String> allowed =
        bound.isNotEmpty ? bound : servicesForRole(user.role ?? '');

    // Access granted.
    if (allowed.contains(service)) return child;

    // Access denied — redirect to the picker filtered to the effective
    // allowed list, with a warning banner explaining why.
    return ServiceSelectionScreen(
      allowedServices: allowed,
      deniedService: service,
    );
  }
}
