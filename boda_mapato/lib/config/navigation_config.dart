import 'package:flutter/material.dart';

/// Represents a single navigation item with its properties
class NavigationItem {
  // For items like settings, logout that appear in all roles

  const NavigationItem({
    required this.key,
    required this.icon,
    required this.route,
    this.requiredPermissions,
    this.badgeKey,
    this.badgeColor,
    this.isSystemItem = false,
  });
  final String key;
  final IconData icon;
  final String route;
  /// Any ONE of these grants access (see NavigationBuilder). A role default and
  /// the matching per-user toggle from the permission screen are both listed so
  /// either path shows the item.
  final List<String>? requiredPermissions;
  final String? badgeKey; // Key to get badge count from dashboard data
  final Color? badgeColor;
  final bool isSystemItem;
}

/// Represents a quick action item for dashboard
class QuickActionItem {
  // For special styling

  const QuickActionItem({
    required this.key,
    required this.icon,
    required this.route,
    this.requiredPermissions,
    this.customAction,
    this.isHighlighted = false,
  });
  final String key;
  final IconData icon;
  final String route;
  final List<String>? requiredPermissions;
  final VoidCallback? customAction;
  final bool isHighlighted;
}

/// Central configuration for all navigation items
class NavigationConfig {
  // Main drawer navigation items
  static const List<NavigationItem> drawerItems = [
    NavigationItem(
      key: 'dashboard',
      icon: Icons.dashboard,
      route: '/dashboard',
      isSystemItem: true, // Always visible
    ),
    NavigationItem(
      key: 'drivers',
      icon: Icons.people,
      route: '/admin/drivers',
      requiredPermissions: ['manage_drivers_transport'],
      badgeKey: 'drivers',
    ),
    NavigationItem(
      key: 'vehicles',
      icon: Icons.directions_car,
      route: '/admin/vehicles',
      requiredPermissions: ['manage_vehicles_transport'],
      badgeKey: 'vehicles',
    ),
    NavigationItem(
      key: 'payments',
      icon: Icons.payment,
      route: '/payments',
      requiredPermissions: ['manage_payments_transport'],
      badgeKey: 'payments',
      badgeColor: Colors.red,
    ),
    NavigationItem(
      key: 'debt_records',
      icon: Icons.assignment_turned_in,
      route: '/admin/debts',
      requiredPermissions: ['manage_debts_transport'],
    ),
    NavigationItem(
      key: 'analytics',
      icon: Icons.analytics,
      route: '/admin/analytics',
      requiredPermissions: ['view_analytics', 'view_reports_transport'],
    ),
    NavigationItem(
      key: 'reports',
      icon: Icons.receipt_long,
      route: '/admin/reports',
      requiredPermissions: ['view_reports_transport'],
    ),
    // Add Receipts to the grid menu so it moves inside "Menyu"
    NavigationItem(
      key: 'receipts',
      icon: Icons.receipt_long,
      route: '/receipts',
      requiredPermissions: ['manage_receipts_transport', 'manage_payments_transport'],
    ),
    NavigationItem(
      key: 'reminders',
      icon: Icons.notifications,
      route: '/admin/reminders',
      requiredPermissions: ['view_reminders', 'manage_reminders_transport'],
      badgeKey: 'reminders',
      badgeColor: Colors.orange,
    ),
    NavigationItem(
      key: 'communications',
      icon: Icons.chat,
      route: '/admin/communications',
      requiredPermissions: ['view_communications'],
    ),
    NavigationItem(
      key: 'ai_assistant',
      icon: Icons.auto_awesome,
      route: '/ai_assistant',
      isSystemItem: true, // For everyone: ask about the business, or how to use the app
    ),
    NavigationItem(
      key: 'switch_service',
      icon: Icons.sync_alt,
      route: '/switch_service', // Special route
      isSystemItem: true,
    ),
  ];

  // Specific navigation items for Rental Service
  static const List<NavigationItem> rentalDrawerItems = [
    NavigationItem(
      key: 'rental_dashboard',
      icon: Icons.dashboard,
      route: '/rental/dashboard',
      isSystemItem: true,
    ),
    NavigationItem(
      key: 'tenant_self_service',
      icon: Icons.account_circle,
      route: '/rental/tenant-self-service',
      requiredPermissions: ['tenant_self_service'],
    ),
    NavigationItem(
      key: 'tenants',
      icon: Icons.people_alt,
      route: '/rental/tenants',
      requiredPermissions: ['view_tenants', 'onboard_tenants_rental'],
    ),
    NavigationItem(
      key: 'properties',
      icon: Icons.business,
      route: '/rental/properties',
      requiredPermissions: ['manage_properties_rental'],
    ),
    NavigationItem(
      key: 'maintenance',
      icon: Icons.handyman,
      route: '/rental/maintenance',
      requiredPermissions: ['view_maintenance', 'manage_maintenance_rental'],
    ),
    NavigationItem(
      key: 'vendors',
      icon: Icons.person_search,
      route: '/rental/vendors',
      requiredPermissions: ['view_vendors'],
    ),
    NavigationItem(
      key: 'rent_payments',
      icon: Icons.payments,
      route: '/rental/billing',
      requiredPermissions: ['manage_properties_rental'], // Landlord only
    ),
    NavigationItem(
      key: 'arrears',
      icon: Icons.pending_actions,
      route: '/rental/arrears',
      requiredPermissions: ['manage_properties_rental'], // Changed to landlord-only
    ),
    NavigationItem(
      key: 'billing_reports',
      icon: Icons.receipt_long,
      route: '/rental/reports',
      requiredPermissions: ['manage_properties_rental'], // Landlord only
    ),
    NavigationItem(
      key: 'sms_history',
      icon: Icons.message_outlined,
      route: '/rental/sms',
      requiredPermissions: ['view_sms_history'],
    ),
    NavigationItem(
      key: 'lease_agreements',
      icon: Icons.description,
      route: '/rental/agreements',
      requiredPermissions: ['manage_agreements_rental'],
    ),
    NavigationItem(
      key: 'lease_templates',
      icon: Icons.file_copy,
      route: '/rental/lease-templates',
      requiredPermissions: ['manage_agreements_rental'],
    ),
    NavigationItem(
      key: 'helpdesk',
      icon: Icons.help_outline,
      route: '/rental/helpdesk',
      isSystemItem: true, // Always visible for guidance
    ),
    NavigationItem(
      key: 'ai_assistant',
      icon: Icons.auto_awesome,
      route: '/ai_assistant',
      isSystemItem: true, // For everyone: ask about the business, or how to use the app
    ),
    NavigationItem(
      key: 'switch_service',
      icon: Icons.sync_alt,
      route: '/switch_service', // Special route
      isSystemItem: true,
    ),
  ];

  // System navigation items (always visible)
  static const List<NavigationItem> systemItems = [
    NavigationItem(
      key: 'settings',
      icon: Icons.settings,
      route: '/settings',
      isSystemItem: true,
    ),
    NavigationItem(
      key: 'logout',
      icon: Icons.logout,
      route: '/logout', // Special route handled separately
      isSystemItem: true,
    ),
  ];

  // Quick action items for dashboard
  static const List<QuickActionItem> quickActions = [
    // Keep only the "Menyu" button on the dashboard quick actions bar
    QuickActionItem(
      key: 'menu',
      icon: Icons.apps,
      route: '/menu', // Special action to open grid menu
      isHighlighted: true,
    ),
  ];

  /// Get all navigation items (drawer + system)
  static List<NavigationItem> get allNavigationItems {
    return [...drawerItems, ...systemItems];
  }

  /// Get navigation items by permission level
  static List<NavigationItem> getItemsByPermissions(
      List<String> userPermissions) {
    return allNavigationItems.where((item) {
      if (item.isSystemItem) return true;
      if (item.requiredPermissions == null) return true;

      return item.requiredPermissions!.every(
        (permission) => userPermissions.contains(permission),
      );
    }).toList();
  }

  /// Get quick actions by permission level
  static List<QuickActionItem> getQuickActionsByPermissions(
      List<String> userPermissions) {
    return quickActions.where((action) {
      if (action.requiredPermissions == null) return true;

      return action.requiredPermissions!.every(
        (permission) => userPermissions.contains(permission),
      );
    }).toList();
  }
}

/// Default permission sets for different user roles
class DefaultPermissions {
  static const List<String> admin = [
    'view_drivers',
    'manage_drivers',
    'view_vehicles',
    'manage_vehicles',
    'view_payments',
    'manage_payments',
    'view_debts',
    'manage_debts',
    'view_analytics',
    'view_reports',
    'generate_reports',
    'view_reminders',
    'manage_reminders',
    'view_communications',
    'manage_communications',
    'generate_receipts',
    'manage_settings',
    // The transport drawer items (drivers/vehicles/payments/debt_records/
    // reports/receipts) actually gate on these _transport-suffixed names,
    // not the plain ones above -- without these, an admin with no explicit
    // permissions array (the common case) sees those items disappear even
    // though the plain-named equivalents are already granted.
    'manage_drivers_transport',
    'manage_vehicles_transport',
    'manage_payments_transport',
    'manage_debts_transport',
    'view_reports_transport',
    'manage_receipts_transport',
    // Rental permissions
    'view_tenants',
    'manage_properties_rental',
    'view_rent_payments',
    'view_arrears',
    'view_rental_reports',
    'view_sms_history',
    'view_maintenance',
    'manage_maintenance',
    'view_vendors',
    'manage_vendors',
    'manage_agreements_rental',
    'view_lease_templates', // Placeholder
    'manage_lease_templates', // Placeholder
  ];

  static const List<String> manager = [
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
  ];

  static const List<String> operator = [
    'view_drivers',
    'view_vehicles',
    'view_payments',
    'view_debts',
    'generate_receipts',
  ];

  static const List<String> viewer = [
    'view_drivers',
    'view_vehicles',
    'view_payments',
    'view_reports',
  ];

  /// Get permissions for a role
  static List<String> getPermissionsForRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'administrator':
        return admin;
      case 'manager':
        return manager;
      case 'operator':
        return operator;
      case 'viewer':
        return viewer;
      default:
        return viewer; // Default to most restrictive
    }
  }
}
