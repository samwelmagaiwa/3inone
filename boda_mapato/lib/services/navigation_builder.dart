import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../models/login_response.dart';
import '../config/navigation_config.dart';
import 'localization_service.dart';
import '../providers/auth_provider.dart';
import '../constants/theme_constants.dart';
import '../widgets/service_switcher_dialog.dart';
import '../screens/receipts/receipts_screen.dart';

// ignore_for_file: directives_ordering
/// Service for building navigation UI components dynamically
class NavigationBuilder {
  /// Build drawer items list for the sidebar navigation
  static List<Widget> buildDrawerItems({
    required LocalizationService localization,
    required Map<String, dynamic> badges,
    required UserData? user,
    required BuildContext context,
    required VoidCallback onLogout,
  }) {
    final List<Widget> items = [];

    // Get available navigation items based on permissions
    final availableItems = NavigationConfig.drawerItems
        .where(
            (item) => _hasPermission(item, user),
        )
        .toList();

    // Add main navigation items
    for (final item in availableItems) {
      items.add(_buildDrawerItem(
        item: item,
        localization: localization,
        badges: badges,
        context: context,
      ));
    }

    // Add divider before system items
    if (availableItems.isNotEmpty) {
      items.add(const Divider(color: Color(0xB3FFFFFF)));
    }

    // Add system items (settings, logout)
    for (final item in NavigationConfig.systemItems) {
      if (item.key == 'logout') {
        items.add(_buildLogoutItem(
          localization: localization,
          onLogout: onLogout,
          context: context,
        ));
      } else {
        items.add(_buildDrawerItem(
          item: item,
          localization: localization,
          badges: badges,
          context: context,
        ));
      }
    }

    return items;
  }

  /// Build quick action buttons
  static List<Widget> buildQuickActions({
    required LocalizationService localization,
    required UserData? user,
    required BuildContext context,
  }) {
    final availableActions = NavigationConfig.quickActions
        .where(
            (action) => _hasPermissionForAction(action, user),
        )
        .toList();

    return availableActions
        .map((action) => _buildActionButton(
              action: action,
              localization: localization,
              context: context,
            ))
        .toList();
  }

  /// Build individual drawer item
  static Widget _buildDrawerItem({
    required NavigationItem item,
    required LocalizationService localization,
    required Map<String, dynamic> badges,
    required BuildContext context,
  }) {
    final badgeCount =
        item.badgeKey != null ? badges[item.badgeKey] as int? ?? 0 : null;

    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            item.icon,
            color: Colors.white,
            size: 24,
          ),
          if (badgeCount != null && badgeCount > 0)
            Positioned(
              right: -8,
              top: -8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: item.badgeColor ?? const Color(0xFFFF6B9D),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        localization.translate(item.key),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: badgeCount != null && badgeCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (item.badgeColor ?? const Color(0xFFFF6B9D))
                    .withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (item.badgeColor ?? const Color(0xFFFF6B9D))
                      .withOpacity(0.5),
                ),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : badgeCount.toString(),
                style: TextStyle(
                  color: item.badgeColor ?? const Color(0xFFFF6B9D),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      onTap: () {
        // Close the drawer first, then navigate
        Navigator.pop(context);
        _navigateTo(item, context);
      },
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 4,
      ),
    );
  }

  /// Build logout item with special handling
  static Widget _buildLogoutItem({
    required LocalizationService localization,
    required VoidCallback onLogout,
    required BuildContext context,
  }) {
    return ListTile(
      leading: const Icon(
        Icons.logout,
        color: Colors.white,
        size: 24,
      ),
      title: Text(
        localization.translate('logout'),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: () async {
        // Confirm logout dialog (localized)
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: ThemeConstants.primaryBlue,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              localization.translate('logout'),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
            content: Text(
              localization.translate('logout_confirm'),
              style: const TextStyle(color: Colors.white70),
            ),
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              // Cancel button (gray)
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(localization.translate('cancel')),
              ),
              // Yes button (red)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  onLogout();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(localization.translate('yes')),
              ),
            ],
          ),
        );
      },
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 4,
      ),
    );
  }

  /// Build individual quick action button
  static Widget _buildActionButton({
    required QuickActionItem action,
    required LocalizationService localization,
    required BuildContext context,
  }) {
    return GestureDetector(
      onTap: () => _handleQuickAction(action, context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double h =
              constraints.maxHeight.isFinite ? constraints.maxHeight : 72;
          // Responsive sizing to avoid overflow in tight spaces
          double side = h * 0.55; // icon button side
          if (side < 32) side = 32;
          if (side > 44) side = 44;
          double iconSize = side * 0.55;
          if (iconSize < 16) iconSize = 16;
          if (iconSize > 24) iconSize = 24;
          double spacing = (h - side) * 0.25;
          if (spacing < 4) spacing = 4;
          if (spacing > 8) spacing = 8;
          double fontSize = (h - side) * 0.35 + 9.5; // ~10-12
          if (fontSize < 10) fontSize = 10;
          if (fontSize > 12) fontSize = 12;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: side,
                height: side,
                decoration: BoxDecoration(
                  color: action.isHighlighted
                      ? const Color(0xFFFF6B9D)
                      : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(side / 2),
                ),
                child: Icon(
                  action.icon,
                  color: Colors.white,
                  size: iconSize,
                ),
              ),
              SizedBox(height: spacing),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth - 2),
                child: Text(
                  localization.translate(action.key),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xB3FFFFFF),
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static void _navigateTo(NavigationItem item, BuildContext context) {
    if (item.route == '/dashboard') {
      // Already on dashboard, do nothing
      return;
    }
    if (item.route == '/switch_service') {
      showDialog(
        context: context,
        builder: (context) => const ServiceSwitcherDialog(),
      );
      return;
    }
    Navigator.pushNamed(context, item.route);
  }

  /// Handle quick action taps
  static void _handleQuickAction(QuickActionItem action, BuildContext context) {
    if (action.customAction != null) {
      action.customAction!();
      return;
    }

    switch (action.route) {
      case '/menu':
        // Show drawer items as a 3-column grid menu on top of the main screen
        final auth = Provider.of<AuthProvider>(context, listen: false);
        _showGridMenu(
          context: context,
          localization: LocalizationService.instance,
          user: auth.user,
        );
        return;
      case '/receipts':
        // Navigate to receipts screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ReceiptsScreen(),
          ),
        );
        return;
      default:
        // Standard navigation
        Navigator.pushNamed(context, action.route);
        return;
    }
  }

  /// Present the drawer navigation options in a tabular (grid) format
  static Future<void> _showGridMenu({
    required BuildContext context,
    required LocalizationService localization,
    required UserData? user,
    List<NavigationItem>? customItems,
  }) async {
    // Determine which items to show: custom list or default drawer + system items
    final baseItems = customItems ??
        [
          ...NavigationConfig.drawerItems,
          ...NavigationConfig.systemItems,
        ];

    final items = baseItems
        // Exclude the logout action from the grid
        .where((item) => item.key != 'logout')
        .where((item) => _hasPermission(item, user))
        .toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              color: ThemeConstants.primaryBlue.withOpacity(0.85),
              borderRadius: BorderRadius.circular(24.r),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(localization.translate('menu'),
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20.sp,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5)),
                    IconButton(
                        icon: Icon(Icons.close,
                            color: Colors.white70, size: 22.sp),
                        onPressed: () => Navigator.of(ctx).pop()),
                  ],
                ),
                SizedBox(height: 20.h),
                _PaginatableGrid(
                  items: items,
                  localization: localization,
                  onItemTap: (item) {
                    Navigator.of(context).pop();
                    _navigateTo(item, context);
                  },
                ),
                SizedBox(height: 10.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Paginatable grid widget - splits items into multiple swipeable pages
  static const int _itemsPerPage = 9; // 3x3 grid

  /// Public helper to show the same grid menu used by quick action '/menu'
  static Future<void> showGridMenu(BuildContext context,
      {List<NavigationItem>? customItems}) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await _showGridMenu(
      context: context,
      localization: LocalizationService.instance,
      user: auth.user,
      customItems: customItems,
    );
  }

  /// Check if user has permission for navigation item
  static bool _hasPermission(NavigationItem item, UserData? user) {
    if (item.isSystemItem) return true;

    // Tenant-only items: Ensure non-tenants (even admins) do not see tenant-specific pages
    if (item.key == 'tenant_self_service' && user?.role != 'tenant') {
      return false;
    }

    // Role-based exclusion (Tenants should NOT see landlord-only features)
    if (user?.role == 'tenant') {
      const tenantAllowedKeys = [
        'rental_dashboard',
        'tenant_self_service',
        'maintenance',
        'vendors',
        'switch_service',
        'ai_assistant',
        'settings',
        'logout'
      ];
      if (!tenantAllowedKeys.contains(item.key)) {
        return false;
      }
    }

    if (item.requiredPermissions == null || item.requiredPermissions!.isEmpty) {
      return true;
    }
    // Check if any of the required permissions is granted
    for (final p in item.requiredPermissions!) {
      if (user?.hasPermission(p) ?? false) return true;
    }
    return false;
  }

  /// Check if user has permission for quick action
  static bool _hasPermissionForAction(
      QuickActionItem action, UserData? user) {
    if (user?.role == 'tenant') {
       // Tenants only allowed specific non-management quick actions
       const tenantAllowedActions = ['menu', 'receipts'];
       if (!tenantAllowedActions.contains(action.key)) {
         return false;
       }
    }

    if (action.requiredPermissions == null ||
        action.requiredPermissions!.isEmpty) {
      return true;
    }
    for (final p in action.requiredPermissions!) {
      if (user?.hasPermission(p) ?? false) return true;
    }
    return false;
  }

  /// Get navigation items for current user
  static List<NavigationItem> getAvailableNavigationItems(
      UserData? user) {
    return NavigationConfig.allNavigationItems
        .where(
          (item) => _hasPermission(item, user),
        )
        .toList();
  }

  /// Get quick actions for current user
  static List<QuickActionItem> getAvailableQuickActions(
      UserData? user) {
    return NavigationConfig.quickActions
        .where(
          (action) => _hasPermissionForAction(action, user),
        )
        .toList();
  }

  /// Get badge counts map from dashboard data
  static Map<String, dynamic> getBadgesFromDashboardData(
      Map<String, dynamic> dashboardData) {
    return {
      'drivers': _toInt(dashboardData['drivers_count'] ??
          dashboardData['total_drivers'] ??
          0),
      'vehicles': _toInt(dashboardData['devices_count'] ??
          dashboardData['total_vehicles'] ??
          0),
      'payments': _toInt(dashboardData['unpaid_debts_count'] ??
          dashboardData['pending_payments'] ??
          0),
      'reminders': _toInt(dashboardData['reminders_count'] ?? 0),
    };
  }
}

class _MenuGridTile extends StatelessWidget {
  const _MenuGridTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double h =
                constraints.maxHeight.isFinite ? constraints.maxHeight : 90.h;

            // Compute sizes responsively to avoid overflows
            double side = h * 0.50; // icon container side
            if (side < 32.w) side = 32.w;
            if (side > 56.w) side = 56.w;

            final double iconSize = side * 0.5;
            final double spacing = h * 0.08;
            double fontSize = h * 0.14;
            if (fontSize < 10.sp) fontSize = 10.sp;
            if (fontSize > 12.sp) fontSize = 12.sp;

            return Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: side,
                      height: side,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Icon(icon, color: Colors.white, size: iconSize),
                    ),
                    SizedBox(height: spacing),
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

/// Helper method to safely convert dynamic values to int
int _toInt(value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

/// A paginatable grid that splits items into pages of 9 (3x3) with swipe/dots
class _PaginatableGrid extends StatefulWidget {

  const _PaginatableGrid({
    required this.items,
    required this.localization,
    required this.onItemTap,
  });
  final List<NavigationItem> items;
  final LocalizationService localization;
  final void Function(NavigationItem) onItemTap;
  static const int itemsPerPage = 9;

  @override
  State<_PaginatableGrid> createState() => _PaginatableGridState();
}

class _PaginatableGridState extends State<_PaginatableGrid> {
  late PageController _pageController;
  int _currentPage = 0;
  int get _totalPages =>
      ((widget.items.length - 1) ~/ _PaginatableGrid.itemsPerPage) + 1;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = _totalPages;
    final showPages = totalPages > 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 420.h,
          child: PageView(
            controller: _pageController,
            onPageChanged: (p) => setState(() => _currentPage = p),
            children: List.generate(totalPages, (pageIdx) {
              final start = pageIdx * _PaginatableGrid.itemsPerPage;
              final end = (start + _PaginatableGrid.itemsPerPage)
                  .clamp(0, widget.items.length);
              final pageItems = widget.items.sublist(start, end);

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: pageItems.length,
                  itemBuilder: (ctx, i) {
                    final item = pageItems[i];
                    return _MenuGridTile(
                      icon: item.icon,
                      label: widget.localization.translate(item.key),
                      onTap: () => widget.onItemTap(item),
                    );
                  },
                ),
              );
            }),
          ),
        ),
        if (showPages)
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(totalPages, (i) {
                final isActive = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: EdgeInsets.symmetric(horizontal: 3.w),
                  width: isActive ? 24.w : 8.w,
                  height: 8.h,
                  decoration: BoxDecoration(
                    color: isActive
                        ? ThemeConstants.primaryOrange
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}
