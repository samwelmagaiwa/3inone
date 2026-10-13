import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../constants/theme_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/rental_provider.dart';
import '../../services/localization_service.dart';
import '../../utils/rental_flow_validator.dart';

class RentalDashboardScreen extends StatefulWidget {
  const RentalDashboardScreen({super.key, this.isSubView = false});
  final bool isSubView;

  @override
  State<RentalDashboardScreen> createState() => _RentalDashboardScreenState();
}

class _RentalDashboardScreenState extends State<RentalDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      final provider = context.read<RentalProvider>();

      // Dashboard summary is usually safe as it contains role-specific summary
      provider.fetchDashboard();

      // Management data should only be fetched if the user has permissions
      if (user?.hasPermission('manage_properties_rental') ?? false) {
        provider.fetchProperties();
      }

      if (user?.hasPermission('manage_billing_rental') ?? false) {
        provider.fetchBills();
      }
      // Fetch tenant house details for tenants (no property management permission)
      if (!(user?.hasPermission('manage_properties_rental') ?? false)) {
        provider.fetchCurrentTenantHouse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.bgTop,
      body: Stack(
        children: [
          _buildPremiumBackground(),
          SafeArea(
            child: Column(
              children: [
                if (widget.isSubView) _buildModernAppBar(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () =>
                        context.read<RentalProvider>().fetchDashboard(),
                    color: ThemeConstants.primaryOrange,
                    backgroundColor: Colors.white10,
                    child: _buildScrollableContent(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumBackground() {
    return Stack(
      children: [
        Container(decoration: ThemeConstants.dashboardBackground),
        Positioned(
          top: -150.h,
          right: -100.w,
          child: Container(
            width: 450.w,
            height: 450.h,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  ThemeConstants.primaryOrange.withOpacity(0.15),
                  ThemeConstants.primaryOrange.withOpacity(0),
                ],
              ),
            ),
          ).withBlur(100),
        ),
      ],
    );
  }

  Widget _buildModernAppBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon:
                    const Icon(Icons.menu_open, color: Colors.white, size: 26),
              ),
              SizedBox(width: 2.w),
              Text(
                "All In",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8),
              ),
              Text(
                " One",
                style: TextStyle(
                    color: ThemeConstants.primaryOrange,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -0.8),
              ),
            ],
          ),
          Icon(Icons.notifications_none, color: Colors.white60, size: 20.sp),
        ],
      ),
    );
  }

  Widget _buildScrollableContent() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 6.h),
          _buildPremiumWelcome(),
          SizedBox(height: 16.h),
          _buildBentoStats(),
          SizedBox(height: 20.h),
          _buildModernActions(),
          SizedBox(height: 16.h),
          _buildHouseDetailsCard(),
          SizedBox(height: 20.h),
          _buildCompactProperties(),
          SizedBox(height: 100.h),
        ],
      ),
    );
  }

  Widget _buildPremiumWelcome() {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final loc = auth.localization;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("${loc.translate('welcome')},",
            style: TextStyle(color: Colors.white60, fontSize: 13.sp)),
        Text(
          user?.name ?? LocalizationService.instance.translate('landlord'),
          style: TextStyle(
              color: Colors.white,
              fontSize: 24.sp,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5),
        ),
      ],
    );
  }

  Widget _buildBentoStats() {
    final rentalProvider = context.watch<RentalProvider>();
    final properties = rentalProvider.properties;
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final loc = auth.localization;

    double totalArrears = 0;
    int totalHouses = 0;
    int occupiedHouses = 0;

    for (final prop in properties) {
      final houses = prop['houses'] as List? ?? [];
      totalHouses += houses.length;
      for (final house in houses) {
        if (house['is_occupied'] == 1 || house['is_occupied'] == true) {
          occupiedHouses++;
        }
        totalArrears +=
            double.tryParse((house['current_balance'] ?? 0).toString()) ?? 0.0;
      }
    }

    final occupancyRate =
        totalHouses > 0 ? (occupiedHouses / totalHouses) : 0.0;
    final bool canManageProperties =
        user?.hasPermission('manage_properties_rental') ?? false;
    final bool canViewArrears =
        user?.hasPermission('manage_debts_transport') ?? false;

    return Column(
      children: [
        // Ultra-Compact Hero Card
        _buildHeroBentoHorizontal(
          loc.translate('occupancy'),
          "${(occupancyRate * 100).toStringAsFixed(0)}%",
          occupancyRate,
          Icons.donut_large,
          ThemeConstants.primaryOrange,
        ),

        if (canManageProperties) ...[
          SizedBox(height: 10.h),
          // Wider Secondary Grid
          Row(
            children: [
              Expanded(
                child: _buildStandardBentoHorizontal(
                  loc.translate('properties'),
                  properties.length.toString(),
                  Icons.business_center,
                  ThemeConstants.primaryBlue,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _buildStandardBentoHorizontal(
                  loc.translate('houses'),
                  totalHouses.toString(),
                  Icons.grid_view,
                  ThemeConstants.successGreen,
                ),
              ),
            ],
          ),
        ],

        SizedBox(height: 10.h),
        if (canViewArrears && canManageProperties)
          _buildWideBentoHorizontal(
            loc.translate('arrears'),
            "TSh ${_formatAmount(totalArrears)}",
            Icons.account_balance_wallet,
            ThemeConstants.errorRed,
          )
        else
          _buildWideBentoHorizontal(
            loc.translate('active_leases'),
            rentalProvider.agreements
                .where((a) => a['status'] == 'active')
                .length
                .toString(),
            Icons.verified_user,
            const Color(0xFF6366F1),
          ),
      ],
    );
  }

  Widget _buildHeroBentoHorizontal(String title, String value, double progress,
      IconData icon, Color accent) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.r),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 52.w,
                      height: 52.w,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 6,
                        backgroundColor: Colors.white.withOpacity(0.05),
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Icon(icon, color: Colors.white, size: 20.sp),
                  ],
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: Colors.white60,
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600)),
                      Text(value,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 30.sp,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                  decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10.r)),
                  child: Text(
                      LocalizationService.instance.isSwahili ? "Hai" : "Active",
                      style: TextStyle(
                          color: accent,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStandardBentoHorizontal(
      String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.r),
        color: Colors.white.withOpacity(0.03),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(6.w),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 16.sp),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(value,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w900)),
                      Text(title,
                          style: TextStyle(
                              color: Colors.white38,
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWideBentoHorizontal(
      String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.r),
        color: Colors.white.withOpacity(0.03),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20.sp),
                SizedBox(width: 12.w),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600)),
                      Text(value,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17.sp,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                Icon(Icons.chevron_right, color: Colors.white24, size: 20.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernActions() {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final loc = auth.localization;

    final bool canManageProperties =
        user?.hasPermission('manage_properties_rental') ?? false;
    final bool canManageAgreements =
        user?.hasPermission('manage_agreements_rental') ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loc.translate('quick_actions'),
            style: TextStyle(
                color: Colors.white70,
                fontSize: 16.sp,
                fontWeight: FontWeight.w800)),
        SizedBox(height: 12.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (canManageProperties)
              _buildActionIcon(
                  loc.translate('lipisha'),
                  Icons.send,
                  ThemeConstants.primaryOrange,
                  () => RentalFlowValidator.validateStep(
                        context: context,
                        fetchData: (p) => p.fetchBills(),
                        condition: RentalFlowValidator.hasUnpaidBills,
                        title: LocalizationService.instance.translate('no_open_bills_2'),
                        message: LocalizationService.instance.translate('no_bills_need_payment_right_now'),
                        actionLabel: LocalizationService.instance.translate('view_agreements'),
                        actionRoute: '/rental/agreements',
                      )),
            if (canManageProperties)
              _buildActionIcon(
                  loc.translate('mali'),
                  Icons.add,
                  ThemeConstants.primaryOrange,
                  () => Navigator.pushNamed(context, "/rental/add-property")),
            if (canManageAgreements)
              _buildActionIcon(
                  loc.translate('mkataba'),
                  Icons.edit,
                  ThemeConstants.primaryOrange,
                  () => RentalFlowValidator.validateStep(
                        context: context,
                        fetchData: (p) async {
                          await p.fetchTenants();
                          await p.fetchProperties();
                        },
                        condition: (p) => RentalFlowValidator.hasTenants(p) && RentalFlowValidator.hasVacantHouses(p),
                        title: LocalizationService.instance.translate('create_lease'),
                        message: LocalizationService.instance.translate('you_need_tenants_and_vacant_houses'),
                        actionLabel: LocalizationService.instance.translate('add_tenant'),
                        actionRoute: '/rental/onboard-tenant', // Fixed typo
                      )),
            _buildActionIcon(loc.translate('zaidi'), Icons.grid_view,
                ThemeConstants.primaryOrange, () {}),
          ],
        ),
      ],
    );
  }

  Widget _buildActionIcon(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 58.w,
            height: 58.w,
            decoration: BoxDecoration(
              color: color.withOpacity(0.9), // More vibrant solid-like color
              borderRadius: BorderRadius.circular(16.r),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(child: Icon(icon, color: Colors.white, size: 24.sp)),
          ),
          SizedBox(height: 6.h),
          Text(label,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // Displays details of the tenant's current house in a premium glassmorphic card
  Widget _buildHouseDetailsCard() {
    final rentalProvider = context.watch<RentalProvider>();
    final house = rentalProvider.currentTenantHouse as Map<String, dynamic>?;
    if (house == null) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: EdgeInsets.symmetric(vertical: 12.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.r),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(house['name'] ?? LocalizationService.instance.translate('house'),
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w900)),
              SizedBox(height: 8.h),
              _infoRow(LocalizationService.instance.translate('location'), house['location'] ?? ''),
              _infoRow(
                  LocalizationService.instance.translate('rent'),
                  house['rent'] != null
                      ? 'TSh ${_formatAmount(house["rent"])}'
                      : ''),
              _infoRow(
                  LocalizationService.instance.translate('status'),
                  (house['is_occupied'] == 1 || house['is_occupied'] == true)
                      ? LocalizationService.instance.translate('occupied')
                      : LocalizationService.instance.translate('vacant')),
            ],
          ),
        ),
      ),
    );
  }

  // Helper row for house info
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white70, fontSize: 13.sp)),
          Text(value,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildCompactProperties() {
    final rentalProvider = context.watch<RentalProvider>();
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final loc = auth.localization;

    final bool canManageProperties =
        user?.hasPermission('manage_properties_rental') ?? false;
    if (!canManageProperties) return const SizedBox.shrink();

    final properties = rentalProvider.properties;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(loc.translate('my_properties'),
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800)),
            TextButton(
              onPressed: () =>
                  Navigator.pushNamed(context, "/rental/properties"),
              child: Text(loc.translate('see_all'),
                  style: TextStyle(
                      color: ThemeConstants.primaryOrange, fontSize: 12.sp)),
            ),
          ],
        ),
        if (properties.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20.h),
            child: Text(loc.translate('no_properties'),
                style: TextStyle(color: Colors.white38, fontSize: 14.sp)),
          )
        else
          ...properties.take(3).map((prop) => _buildModernPropertyTile(prop)),
      ],
    );
  }

  Widget _buildModernPropertyTile(Map<String, dynamic> prop) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        color: Colors.white.withOpacity(0.03),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14.r,
            backgroundColor: ThemeConstants.primaryOrange.withOpacity(0.1),
            child: Icon(Icons.business,
                color: ThemeConstants.primaryOrange, size: 14.sp),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(prop['name'] ?? LocalizationService.instance.translate('property'),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.bold)),
                Text(
                  (prop['full_address']?.toString().trim().isNotEmpty == true
                      ? prop['full_address']
                      : (prop['address']?.toString().trim().isNotEmpty == true
                          ? prop['address']
                          : (prop['district']?.toString().trim().isNotEmpty ==
                                  true
                              ? '${prop['ward'] != null ? "${prop['ward']}, " : ""}${prop['district']}'
                              : prop['region'] ??
                                  prop['location'] ??
                                  '—'))) as String,
                  style: TextStyle(color: Colors.white38, fontSize: 10.sp),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 10.sp),
        ],
      ),
    );
  }

  String _formatAmount(dynamic val) {
    final double value = double.tryParse(val.toString()) ?? 0.0;
    if (value >= 1000000) return "${(value / 1000000).toStringAsFixed(1)}M";
    if (value >= 1000) return "${(value / 1000).toStringAsFixed(0)}K";
    return value.toStringAsFixed(0);
  }
}

extension BlurExtension on Widget {
  Widget withBlur(double sigma) => ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: this,
        ),
      );
}
