// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes, avoid_dynamic_calls
/// User permissions model for role-based access control.
///
/// Resolution order (highest to lowest priority):
///   1. super_admin / fullAccess flag → unrestricted
///   2. Per-user explicit grants stored in `users.permissions` (DB column)
///   3. Role-default permission set
///
/// Use [UserPermissions.fromUser] whenever you have a full [UserData] object.
/// Use [UserPermissions.fromRole] only for role-only checks (no user context).
class UserPermissions {
  const UserPermissions({
    List<String>? permissions,
    this.role,
  }) : _permissions = permissions ?? const [];

  /// Create empty permissions (most restrictive)
  const UserPermissions.empty() : this();

  /// Create permissions from role defaults only.
  UserPermissions.fromRole(String userRole)
      : role = userRole,
        _permissions = _getPermissionsForRole(userRole);

  /// Create permissions from explicit list only (no role fallback).
  const UserPermissions.fromList(List<String> permissions)
      : _permissions = permissions,
        role = null;

  /// Hybrid constructor — role defaults UNION per-user explicit grants.
  /// This is the correct constructor to use for any real logged-in user.
  UserPermissions.fromUser({
    required String userRole,
    List<String>? explicitGrants,
  })  : role = userRole,
        _permissions = _merge(
          _getPermissionsForRole(userRole),
          explicitGrants ?? const [],
        );

  /// Merge two permission lists, deduplicating.
  static List<String> _merge(List<String> base, List<String> extra) {
    final Set<String> merged = {...base, ...extra};
    return merged.toList();
  }

  final List<String> _permissions;
  final String? role;

  /// super_admin is the top role: full access to every service, matching
  /// the backend's role_any middleware, which bypasses its role list
  /// entirely for super_admin rather than relying on a maintained list.
  bool get _isSuperAdmin =>
      role?.toLowerCase() == 'super_admin' || role?.toLowerCase() == 'superadmin';

  /// True only for super_admin — the one role that bypasses every gate
  /// across all services without needing explicit service bindings.
  bool get _isSuperAdminOrFullAccess => _isSuperAdmin;

  /// Check if user has a specific permission
  bool has(String permission) {
    return _isSuperAdminOrFullAccess || _permissions.contains(permission);
  }

  /// Check if user has all of the given permissions
  bool hasAll(List<String> permissions) {
    return _isSuperAdminOrFullAccess || permissions.every(_permissions.contains);
  }

  /// Check if user has any of the given permissions
  bool hasAny(List<String> permissions) {
    return _isSuperAdminOrFullAccess || permissions.any(_permissions.contains);
  }

  /// Get all permissions as a list
  List<String> get all => List.unmodifiable(_permissions);

  /// Check if user is an admin
  bool get isAdmin =>
      role?.toLowerCase() == 'admin' ||
      role?.toLowerCase() == 'administrator' ||
      role?.toLowerCase() == 'super_admin' ||
      role?.toLowerCase() == 'superadmin';

  /// Check if user is a manager
  bool get isManager => role?.toLowerCase() == 'manager';

  /// Check if user is an operator
  bool get isOperator => role?.toLowerCase() == 'operator';

  /// Check if user is a viewer
  bool get isViewer => role?.toLowerCase() == 'viewer';

  /// Check if permissions are empty
  bool get isEmpty => _permissions.isEmpty;

  /// Check if permissions are not empty
  bool get isNotEmpty => _permissions.isNotEmpty;

  @override
  String toString() {
    return 'UserPermissions(role: $role, permissions: $_permissions)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserPermissions &&
        other.role == role &&
        _listEquals(other._permissions, _permissions);
  }

  @override
  int get hashCode => role.hashCode ^ _permissions.hashCode;

  /// Helper method to get permissions for a role
  static List<String> _getPermissionsForRole(String userRole) {
    switch (userRole.toLowerCase()) {
      // super_admin has full access across all services — no restrictions.
      // The _isSuperAdmin bypass in has() makes this list irrelevant for
      // permission checks, but it is returned for completeness.
      case 'super_admin':
      case 'superadmin':
        return const [
          'view_drivers', 'manage_drivers', 'view_vehicles', 'manage_vehicles',
          'view_payments', 'manage_payments', 'view_debts', 'manage_debts',
          'view_analytics', 'view_reports', 'generate_reports', 'view_reminders',
          'manage_reminders', 'view_communications', 'manage_communications',
          'generate_receipts', 'manage_settings',
          'inv_view_products', 'inv_manage_products', 'inv_manage_stock',
          'inv_create_sales', 'inv_manage_sales', 'inv_view_reminders',
          'inv_view_purchasing', 'inv_view_credit', 'inv_view_cash',
          'inv_view_crates', 'inv_view_reports', 'inv_view_expenses',
          'inv_manage_expenses', 'inv_manage_settings',
          'view_tenants', 'view_properties', 'view_rent_payments', 'view_arrears',
          'view_rental_reports', 'view_sms_history', 'view_maintenance',
          'manage_maintenance', 'view_vendors', 'manage_vendors',
        ];

      // admin has full permissions within the service(s) assigned to them by a
      // super_admin, but service access is enforced via service bindings — not by
      // a bypass.  They see the same permission set as super_admin so every feature
      // inside their assigned service works; the service guard is what limits scope.
      case 'admin':
      case 'administrator':
        return const [
          'view_drivers', 'manage_drivers', 'view_vehicles', 'manage_vehicles',
          'view_payments', 'manage_payments', 'view_debts', 'manage_debts',
          'view_analytics', 'view_reports', 'generate_reports', 'view_reminders',
          'manage_reminders', 'view_communications', 'manage_communications',
          'generate_receipts', 'manage_settings',
          'inv_view_products', 'inv_manage_products', 'inv_manage_stock',
          'inv_create_sales', 'inv_manage_sales', 'inv_view_reminders',
          'inv_view_purchasing', 'inv_view_credit', 'inv_view_cash',
          'inv_view_crates', 'inv_view_reports', 'inv_view_expenses',
          'inv_manage_expenses', 'inv_manage_settings',
          'view_tenants', 'view_properties', 'view_rent_payments', 'view_arrears',
          'view_rental_reports', 'view_sms_history', 'view_maintenance',
          'manage_maintenance', 'view_vendors', 'manage_vendors',
        ];
      case 'manager':
        return const [
          'view_drivers',
          'view_vehicles',
          'view_payments',
          'manage_payments',
          'view_debts',
          'manage_debts',
          'view_analytics',
          'view_reports',
          'view_reminders',
          'view_communications',
          'generate_receipts',
          // Inventory — manager has full operational access
          'inv_view_products',
          'inv_manage_products',
          'inv_manage_stock',
          'inv_create_sales',
          'inv_manage_sales',
          'inv_view_reminders',
          'inv_view_purchasing',
          'inv_view_credit',
          'inv_view_cash',
          'inv_view_crates',
          'inv_view_reports',
          'inv_view_expenses',
          'inv_manage_expenses',
          // Rental
          'view_tenants',
          'view_properties',
          'view_rent_payments',
          'view_arrears',
          'view_rental_reports',
          'view_sms_history',
        ];
      case 'sales_officer':
        // Point-of-sale focused: sell against stock that already exists,
        // check a customer's credit standing before selling on debt, run
        // their own cash till, and see crate deposits when relevant.
        // Deliberately NOT included (admin/manager only): catalog
        // management (categories, product edits, past orders), physical
        // stock control (stock in/out/transfer, batches, stock counts,
        // write-offs), broader sales management/returns, purchasing,
        // reports, and the depot's own operating-expense ledger.
        return const [
          'inv_view_products',
          // May add NEW products only (no edit/delete/pricing/categories).
          'inv_create_products',
          'inv_create_sales',
          'inv_view_reminders',
          'inv_view_credit',
          'inv_view_cash',
          'inv_view_crates',
          // Can flag damaged/expired/broken stock without full
          // stock-management rights; approving still needs inv_manage_stock.
          'inv_report_damage',
        ];
      case 'operator':
        return const [
          'view_drivers',
          'view_vehicles',
          'view_payments',
          'view_debts',
          'generate_receipts',
          // Inventory
          'inv_view_products',
          'inv_manage_products',
          'inv_create_sales',
          'inv_view_reminders',
        ];
      // ---- The salon's roles (mirror User::$INV_ROLE_DEFAULTS on the server) ----
      case 'receptionist':
        // Customers, appointments, the queue and service orders; no money reports, no pay.
        return const ['inv_view_products', 'inv_create_sales', 'inv_view_reminders', 'inv_view_credit'];
      case 'cashier':
        // Payments, receipts, the cashbook and reconciliation.
        return const ['inv_view_products', 'inv_create_sales', 'inv_manage_sales', 'inv_view_credit', 'inv_view_cash', 'inv_view_reminders'];
      case 'hair_stylist':
      case 'nail_technician':
      case 'lash_makeup_artist':
        // Their own services, appointments and performance (the server shows them only their own).
        return const ['inv_view_products', 'inv_create_sales', 'inv_view_reminders'];
      case 'accountant':
        // Expenses, financial reports, payroll and reconciliation.
        return const ['inv_view_products', 'inv_view_reports', 'inv_view_expenses', 'inv_manage_expenses', 'inv_view_cash', 'inv_view_credit'];
      case 'stock_manager':
        // Goods, suppliers, purchases and stock adjustments.
        return const ['inv_view_products', 'inv_manage_products', 'inv_manage_stock', 'inv_view_purchasing', 'inv_report_damage', 'inv_view_reminders'];
      case 'viewer':
        return const [
          'view_drivers',
          'view_vehicles',
          'view_payments',
          'view_reports',
          // Inventory
          'inv_view_products',
        ];
      case 'customer':
        return const [
          // Inventory customer-facing
          'inv_view_products',
          'inv_view_reminders',
        ];
      default:
        return const [];
    }
  }

  /// Helper method to compare lists
  bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    if (identical(a, b)) return true;
    for (int index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}

/// Extension on dynamic (Map / UserData) to resolve the effective permissions.
/// Always prefer calling this over constructing UserPermissions directly.
extension UserDataPermissions on dynamic {
  UserPermissions get permissions {
    if (this is Map) {
      final String role = (this['role'] as String?) ?? '';
      final dynamic raw = this['permissions'];
      List<String>? explicit;
      if (raw is List) {
        explicit = List<String>.from(raw.map((e) => e.toString()));
      }
      // fullAccess / super_admin are handled inside UserPermissions._isSuperAdmin
      // and the has() method, so just pass them through.
      return UserPermissions.fromUser(
        userRole: role,
        explicitGrants: explicit,
      );
    }
    return UserPermissions.fromRole('viewer');
  }
}
