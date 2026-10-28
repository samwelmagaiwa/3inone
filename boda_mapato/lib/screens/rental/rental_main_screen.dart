import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../config/navigation_config.dart';
import '../../constants/theme_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/localization_service.dart';
import '../../services/navigation_builder.dart';
import '../../widgets/service_switcher_dialog.dart';
import 'billing_list_screen.dart';
import 'rental_arrears_screen.dart';
import 'rental_dashboard_screen.dart';
import 'rental_receipts_screen.dart';
import 'tenants_list_screen.dart';

class RentalMainScreen extends StatefulWidget {
  const RentalMainScreen({super.key});

  @override
  State<RentalMainScreen> createState() => _RentalMainScreenState();
}

class _RentalMainScreenState extends State<RentalMainScreen> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<Widget> _pages = [
    const RentalDashboardScreen(isSubView: true),
    const BillingListScreen(isSubView: true),
    // Arrears Screen (Index 2)
    const RentalArrearsScreen(),
    // Tenants List Screen (Index 3)
    const TenantsListScreen(isSubView: true),
    // Receipts Screen (Index 4)
    const RentalReceiptsScreen(isSubView: true),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizationService = LocalizationService.instance;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildRentalDrawer(context, localizationService),
      body: Stack(
        children: [
          // Background - use shared ThemeConstants gradient
          const DecoratedBox(
            decoration: ThemeConstants.dashboardBackground,
            child: SizedBox.expand(),
          ),
          // Content
          SafeArea(
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
          ),
          // Bottom Navigation Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildRentalFooter(context),
          ),
        ],
      ),
    );
  }

  /// Footer styled exactly like Transport module
  Widget _buildRentalFooter(BuildContext context) {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    return ColoredBox(
      color: ThemeConstants.footerBarColor,
      child: SafeArea(
        top: false,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28.r),
          child: Container(
            width: double.infinity,
            margin: EdgeInsets.symmetric(vertical: 8.h),
            padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: ThemeConstants.footerBarColor,
              borderRadius: BorderRadius.circular(28.r),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                // Left side: Rent Payments, Arrears
                Flexible(child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _FooterIcon(
                      icon: Icons.payments_rounded,
                      label: LocalizationService.instance
                          .translate('rent_payments'),
                      isSelected: _selectedIndex == 1,
                      onTap: () => _onItemTapped(1),
                    ),
                    SizedBox(width: 14.w),
                    _FooterIcon(
                      icon: Icons.pending_actions_rounded,
                      label: LocalizationService.instance.translate('arrears'),
                      isSelected: _selectedIndex == 2,
                      onTap: () => _onItemTapped(2),
                    ),
                  ],
                )),
                // Center: Menu
                _FooterIcon(
                  icon: Icons.apps_rounded,
                  label: LocalizationService.instance.translate('menu'),
                  isCenter: true,
                  onTap: () =>
                      NavigationBuilder.showGridMenu(context, customItems: [
                    ...NavigationConfig.rentalDrawerItems,
                    ...NavigationConfig.systemItems,
                  ]),
                ),
                // Right side: Tenants, Receipts
                Flexible(child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _FooterIcon(
                      icon: Icons.people_alt_rounded,
                      label: LocalizationService.instance.translate('tenants'),
                      isSelected: _selectedIndex == 3,
                      onTap: () => _onItemTapped(3),
                    ),
                    SizedBox(width: 14.w),
                    _FooterIcon(
                      icon: Icons.receipt_long_rounded,
                      label: LocalizationService.instance.translate('receipts'),
                      isSelected: _selectedIndex == 4,
                      onTap: () => _onItemTapped(4),
                    ),
                  ],
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRentalDrawer(BuildContext context, LocalizationService loc) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Drawer(
      backgroundColor: ThemeConstants.bgTop,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.1)),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: ThemeConstants.cardColor,
                    child: Text(user?.name.substring(0, 1).toUpperCase() ?? "L",
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(user?.name ?? loc.translate("welcome_landlord"),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  Text(user?.email ?? "landlord@allinone.com",
                      style: const TextStyle(
                          color: ThemeConstants.textSecondary, fontSize: 14)),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final item in NavigationConfig.rentalDrawerItems)
                  if (item.isSystemItem ||
                      NavigationBuilder.getAvailableNavigationItems(user)
                          .any((i) => i.key == item.key))
                    _DrawerItem(
                      icon: item.icon,
                      label: LocalizationService.instance.translate(item.key),
                      onTap: () {
                        final isTenant = user?.role == 'tenant';

                        if (item.key == 'rental_dashboard') {
                          _onItemTapped(0);
                        } else if (item.key == 'rent_payments' ||
                            item.key == 'tenant_self_service' ||
                            item.key == 'billing_reports') {
                          if (isTenant) {
                            Navigator.pushNamed(
                                context, '/rental/tenant-self-service');
                          } else if (item.key == 'rent_payments') {
                            _onItemTapped(1);
                          } else if (item.key == 'billing_reports') {
                            Navigator.pushNamed(context, item.route);
                          }
                        } else if (item.key == 'arrears') {
                          _onItemTapped(2);
                        } else if (item.key == 'tenants') {
                          _onItemTapped(3);
                        } else if (item.key == 'lease_agreements') {
                          Navigator.pushNamed(
                              context,
                              isTenant
                                  ? '/rental/tenant-self-service'
                                  : '/rental/agreements');
                        } else if (item.key == 'lease_templates') {
                          Navigator.pushNamed(
                              context, '/rental/lease-templates');
                        } else if (item.key == 'switch_service') {
                          showDialog(
                              context: context,
                              builder: (context) =>
                                  const ServiceSwitcherDialog());
                        } else {
                          Navigator.pushNamed(context, item.route);
                        }
                      },
                    ),
                const Divider(color: Colors.white10),
                _DrawerItem(
                  icon: Icons.logout,
                  label: loc.translate("logout"),
                  color: ThemeConstants.errorRed,
                  onTap: () async {
                    await auth.logout();
                    if (mounted) Navigator.pushReplacementNamed(context, "/");
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: 20.h),
        ],
      ),
    );
  }
}

class _FooterIcon extends StatelessWidget {
  const _FooterIcon({
    required this.icon,
    required this.onTap,
    required this.label,
    this.isSelected = false,
    this.isCenter = false,
  });
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isCenter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg = isCenter
        ? ThemeConstants.primaryOrange
        : (isSelected
            ? ThemeConstants.primaryOrange.withOpacity(0.5)
            : ThemeConstants.primaryBlue.withOpacity(0.22));

    // Flexible: on a very narrow screen the five buttons share the width instead of overflowing.
    return Flexible(
      child: InkResponse(
        onTap: onTap,
        radius: 28.r,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 64.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 42.w,
                height: 42.w,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon,
                    color: Colors.white, size: isCenter ? 24.sp : 21.sp),
              ),
              SizedBox(height: 3.h),
              // The name of what the button opens, so nobody has to guess from the picture.
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white
                        .withValues(alpha: (isSelected || isCenter) ? 1 : 0.85),
                    fontSize: 10.sp,
                    fontWeight: (isSelected || isCenter)
                        ? FontWeight.w800
                        : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color, size: 22.w),
      title: Text(label, style: TextStyle(color: color, fontSize: 14.sp)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}
