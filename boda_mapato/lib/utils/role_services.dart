/// The services a person may PICK from (the service picker and the switcher): a super admin has every service, even
/// one added after their account was made (their saved list is only what they had then); anyone else has what a
/// super admin bound to them, else what their role implies.
List<String> pickableServices({required final List<String> bound, required final String role, required final bool isSuperAdmin}) {
  if (isSuperAdmin) return servicesForRole('super_admin');
  return bound.isNotEmpty ? bound : servicesForRole(role);
}

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
    case 'hair_stylist':
    case 'nail_technician':
    case 'lash_makeup_artist':
    case 'accountant':
      return ['salon'];
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
