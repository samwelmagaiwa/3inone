/// Maps a user role to the list of services they are permitted to access.
/// Used both for routing (when no explicit service bindings exist) and for
/// the ServiceGuard widget that blocks cross-service navigation.
List<String> servicesForRole(String role) {
  switch (role.toLowerCase()) {
    // super_admin bypasses service bindings entirely (handled in ServiceGuard).
    // admin has NO default services — a super_admin must explicitly assign them.
    case 'super_admin':
      return ['inventory', 'rental', 'transport', 'salon'];
    case 'admin':
    case 'administrator':
      return []; // must be bound by super_admin — no implicit access
    case 'sales_officer':
    case 'manager':
    case 'operator':
      return ['inventory'];
    case 'driver':
      return ['transport'];
    case 'landlord':
    case 'caretaker':
    case 'tenant':
    case 'vendor':
      return ['rental'];
    default:
      return [];
  }
}
