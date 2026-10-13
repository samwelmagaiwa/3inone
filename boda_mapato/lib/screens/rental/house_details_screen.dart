import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../providers/rental_provider.dart';
import '../../services/localization_service.dart';
import 'onboard_tenant_screen.dart';
import 'add_house_bottom_sheet.dart';

// ─────────────────────────────────────────────
// Color palette (consistent with tenant details)
// ─────────────────────────────────────────────
const _kGradientTop    = Color(0xFF04121A);
const _kGradientMid    = Color(0xFF092D3A);
const _kGradientBottom = Color(0xFF0D485A);
const _kOrange         = Color(0xFFF97316);
const _kGreen          = Color(0xFF10B981);
const _kAmber          = Color(0xFFF59E0B);
const _kRed            = Color(0xFFEF4444);

// ─────────────────────────────────────────────
class HouseDetailsScreen extends StatefulWidget {
  const HouseDetailsScreen({required this.house, super.key});
  final Map<String, dynamic> house;

  @override
  State<HouseDetailsScreen> createState() => _HouseDetailsScreenState();
}

class _HouseDetailsScreenState extends State<HouseDetailsScreen> {
  Map<String, dynamic>? _houseData;
  bool _isVacating = false;

  @override
  void initState() {
    super.initState();
    _houseData = Map<String, dynamic>.from(widget.house);
    _loadFullDetails();
  }

  Future<void> _loadFullDetails() async {
    final fullData = await context
        .read<RentalProvider>()
        .fetchHouseDetails(widget.house['id'].toString());
    if (fullData != null && mounted) {
      setState(() {
        _houseData = Map<String, dynamic>.from(fullData);
      });
    }
  }

  @override
  void didUpdateWidget(covariant HouseDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.house != oldWidget.house) {
      setState(() {
        _houseData = Map<String, dynamic>.from(widget.house);
      });
    }
  }

  Future<void> _handleVacate() async {
    final loc = LocalizationService.instance;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _kGradientMid.withOpacity(0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Text(loc.translate("confirm_vacate"),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(loc.translate("vacate_message"),
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(loc.translate("cancel"), style: const TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc.translate("confirm"),
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && mounted) {
      setState(() => _isVacating = true);
      final tenantId = widget.house['current_tenant_id']?.toString();
      if (tenantId != null) {
        final success = await context
            .read<RentalProvider>()
            .terminateTenantAgreement(tenantId);
        if (mounted) {
          setState(() => _isVacating = false);
          if (success) {
            ThemeConstants.showSuccessSnackBar(
                context, loc.translate("vacate_success"));
            Navigator.pop(context);
          } else {
            ThemeConstants.showErrorSnackBar(
                context, loc.translate("vacate_failed"));
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _houseData ??= Map<String, dynamic>.from(widget.house);
    final h = _houseData!;
    final loc = LocalizationService.instance;
    final isOccupied = h['status'] == 'occupied';
    final status = h['status']?.toString() ?? 'vacant';

    return Scaffold(
      backgroundColor: _kGradientTop,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: EdgeInsets.all(6.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 14.sp),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "${loc.translate('house')} ${h['house_number']}",
          style: TextStyle(
            color: Colors.white,
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: _kGradientMid,
            offset: const Offset(0, 40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
            onSelected: (value) {
              if (value == 'edit') {
                _showEditHouseDialog();
              } else if (value == 'delete') {
                _showDeleteConfirmation();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                     const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
                     SizedBox(width: 12.w),
                     Text(loc.translate('edit'), style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                     const Icon(Icons.delete_outline, color: _kRed, size: 20),
                     SizedBox(width: 12.w),
                     Text(loc.translate('delete'), style: const TextStyle(color: _kRed)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Background gradient
          const _AnimatedBackground(),

          // ── Main scrollable content
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(12.w, 16.h, 12.w, 100.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusHeader(h),
                  SizedBox(height: 16.h),
                  _GlassCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _buildJoinedSections(context, h, loc, isOccupied),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom action button
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _BottomActionBar(
              isOccupied: isOccupied,
              status: status,
              isVacating: _isVacating,
              onVacate: _handleVacate,
              onOnboard: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OnboardTenantScreen(
                    preSelectedProperty: h['property'],
                    preSelectedHouse: _houseData,
                  ),
                ),
              ).then((_) {
                context.read<RentalProvider>().fetchPropertyDetails(
                    h['property_id']?.toString() ?? '');
                _loadFullDetails();
              }),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildJoinedSections(
    BuildContext context,
    Map<String, dynamic> h,
    LocalizationService loc,
    bool isOccupied,
  ) {
    final list = <Widget>[];

    Widget wrapSection(Widget child) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 16.h),
        child: child,
      );
    }

    // 1. Quick Stats
    list.add(wrapSection(_buildQuickStats(h)));

    // 2. Current Tenant (if occupied)
    if (isOccupied) {
      list.add(wrapSection(_buildTenantSection(h)));
    }

    // 3. Unit Details
    list.add(wrapSection(_buildDetailsSection(h)));

    // Join with dividers
    final joined = <Widget>[];
    for (int i = 0; i < list.length; i++) {
      joined.add(list[i]);
      if (i < list.length - 1) {
        joined.add(const _SectionDivider());
      }
    }
    return joined;
  }

  Widget _buildStatusHeader(Map<String, dynamic> h) {
    final loc = LocalizationService.instance;
    final status = h['status'] as String? ?? 'vacant';
    
    Color statusColor = _kGreen;
    if (status == 'occupied') statusColor = _kOrange;
    if (status == 'maintenance') statusColor = _kRed;

    final String propertyName = h['property']?['name'] ?? h['property_name'] ?? LocalizationService.instance.translate('rental_property');
    final String type = loc.translate(h['type']?.toString().toLowerCase() ?? 'room').toUpperCase();
    final String houseNumber = h['house_number'] ?? '';

    return _GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: _kOrange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: _kOrange.withOpacity(0.25)),
            ),
            child: Icon(Icons.home_work_rounded, color: _kOrange, size: 24.sp),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  propertyName,
                  style: TextStyle(
                    color: _kOrange,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                Text(
                  "${loc.translate('house')} $houseNumber",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2.h),
                Text(
                  type,
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 9.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: statusColor.withOpacity(0.55)),
              boxShadow: [
                BoxShadow(
                    color: statusColor.withOpacity(0.2),
                    blurRadius: 8)
              ],
            ),
            child: Text(
              loc.translate(status).toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontSize: 8.sp,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(dynamic value) {
    if (value == null) return '0';
    final String cleanVal = value.toString().split('.').first;
    final RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return cleanVal.replaceAllMapped(reg, (Match match) => '${match[1]},');
  }

  Widget _buildQuickStats(Map<String, dynamic> h) {
    final loc = LocalizationService.instance;
    return Row(
      children: [
        Expanded(
          child: _buildPriceStatItem(
            loc.translate("rent"),
            "Tsh ${_formatCurrency(h['rent_amount'])}",
            LocalizationService.instance.translate('month_2'),
            Icons.payments_outlined,
            _kOrange,
          ),
        ),
        Container(
          width: 1.5,
          height: 52.h,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
          ),
        ),
        Expanded(
          child: _buildPriceStatItem(
            loc.translate("deposit"),
            "Tsh ${_formatCurrency(h['deposit_amount'])}",
            " refundable",
            Icons.savings_outlined,
            Colors.tealAccent,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceStatItem(String label, String value, String subtitle, IconData icon, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 9.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Icon(icon, color: color.withOpacity(0.8), size: 16.sp),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9.sp,
            ),
          ),
        ],
      ),
    );
  }

  String _resolveTenantPhone(dynamic tenant) {
    if (tenant == null || tenant is! Map) return LocalizationService.instance.translate('no_phone_number');
    const phoneKeys = ['phone_number', 'phone', 'mobile', 'telephone'];

    String? _extract(Map m) {
      for (final k in phoneKeys) {
        final v = m[k];
        if (v != null && v.toString().trim().isNotEmpty && v.toString().trim() != 'N/A') {
          return v.toString().trim();
        }
      }
      return null;
    }

    final direct = _extract(tenant as Map);
    if (direct != null) return direct;

    for (final nestedKey in ['profile', 'tenant_profile', 'user']) {
      final nested = tenant[nestedKey];
      if (nested is Map) {
        final found = _extract(nested);
        if (found != null) return found;
      }
    }
    return LocalizationService.instance.translate('no_phone_number');
  }

  Widget _buildTenantSection(Map<String, dynamic> h) {
    final tenant = h['current_tenant'];
    final loc = LocalizationService.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.person_outline_rounded,
          label: loc.translate("current_tenant").toUpperCase(),
          trailing: tenant != null ? Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 11.sp) : null,
        ),
        SizedBox(height: 12.h),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (tenant != null) {
                Navigator.pushNamed(context, '/rental/tenant-details',
                    arguments: tenant);
              }
            },
            borderRadius: BorderRadius.circular(12.r),
            child: Ink(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44.w,
                    height: 44.w,
                    decoration: BoxDecoration(
                      color: _kOrange.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: _kOrange.withOpacity(0.2)),
                      image: tenant?['photo_url'] != null
                          ? DecorationImage(
                              image: NetworkImage(tenant['photo_url']),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: tenant?['photo_url'] == null
                        ? Center(
                            child: Text(
                              (tenant?['name'] ?? '?')[0].toString().toUpperCase(),
                              style: TextStyle(
                                color: _kOrange,
                                fontWeight: FontWeight.bold,
                                fontSize: 16.sp,
                              ),
                            ),
                          )
                        : null,
                  ),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tenant?['name'] ?? 'N/A',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Row(
                          children: [
                            Icon(Icons.phone_outlined, color: Colors.white38, size: 12.sp),
                            SizedBox(width: 4.w),
                            Text(
                              _resolveTenantPhone(tenant),
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12.sp,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsSection(Map<String, dynamic> h) {
    final loc = LocalizationService.instance;
    
    final bool hasFence = h['has_fence'] == true || h['has_fence'] == 1 || h['has_fence'] == '1';
    final bool hasTiles = h['has_tiles'] == true || h['has_tiles'] == 1 || h['has_tiles'] == '1';
    final bool hasSittingRoom = h['has_sitting_room'] == true || h['has_sitting_room'] == 1 || h['has_sitting_room'] == '1';
    final bool hasMasterBedroom = h['has_master_bedroom'] == true || h['has_master_bedroom'] == 1 || h['has_master_bedroom'] == '1';
    final bool hasKitchen = h['has_kitchen'] == true || h['has_kitchen'] == 1 || h['has_kitchen'] == '1';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: Icons.info_outline_rounded,
          label: loc.translate("unit_details").toUpperCase(),
        ),
        SizedBox(height: 12.h),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(
            children: [
              _buildInfoRow(loc.translate("electricity_meter"), h['electricity_meter'] ?? '-', Icons.electric_bolt_outlined, showBorder: true),
              _buildInfoRow(loc.translate("water_meter"), h['water_meter'] ?? '-', Icons.water_drop_outlined, showBorder: true),
              _buildInfoRow(loc.translate("bedrooms"), (h['bedrooms'] ?? 0).toString(), Icons.bed_outlined, showBorder: true),
              _buildInfoRow(loc.translate("bathrooms"), (h['bathrooms'] ?? 0).toString(), Icons.shower_outlined, showBorder: h['floor'] != null && h['floor'].toString() != '0' || h['square_meters'] != null && h['square_meters'].toString() != '0'),
              if (h['floor'] != null && h['floor'].toString() != '0')
                _buildInfoRow(LocalizationService.instance.translate('floor'), h['floor'].toString(), Icons.layers_outlined, showBorder: h['square_meters'] != null && h['square_meters'].toString() != '0'),
              if (h['square_meters'] != null && h['square_meters'].toString() != '0')
                _buildInfoRow(LocalizationService.instance.translate('square_meters'), "${h['square_meters']} m²", Icons.square_foot_outlined, showBorder: false),
            ],
          ),
        ),
        
        SizedBox(height: 16.h),
        Text(
          LocalizationService.instance.translate('house_features_2').toUpperCase(),
          style: TextStyle(
            color: Colors.white38,
            fontSize: 9.sp,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            _buildFeatureChip(LocalizationService.instance.translate('feature_tiles'), hasTiles, Icons.grid_view_rounded),
            _buildFeatureChip(LocalizationService.instance.translate('feature_fence'), hasFence, Icons.fence_outlined),
            _buildFeatureChip(LocalizationService.instance.translate('feature_kitchen'), hasKitchen, Icons.kitchen_outlined),
            _buildFeatureChip(LocalizationService.instance.translate('feature_sitting_room'), hasSittingRoom, Icons.chair_outlined),
            _buildFeatureChip(LocalizationService.instance.translate('master_bedroom'), hasMasterBedroom, Icons.king_bed_outlined),
          ],
        ),
        
        if (h['description'] != null && h['description'].toString().trim().isNotEmpty) ...[
          Divider(color: Colors.white10, height: 28.h),
          Text(
            loc.translate("notes").toUpperCase(),
            style: TextStyle(
              color: Colors.white38,
              fontSize: 9.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            h['description'],
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12.sp,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon, {bool showBorder = true}) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
      decoration: BoxDecoration(
        border: showBorder
            ? Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))
            : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: _kOrange.withOpacity(0.7), size: 15.sp),
          SizedBox(width: 12.w),
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: TextStyle(color: Colors.white54, fontSize: 12.sp),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureChip(String label, bool active, IconData icon) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: active ? _kOrange.withOpacity(0.08) : Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: active ? _kOrange.withOpacity(0.3) : Colors.white10,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.sp, color: active ? _kOrange : Colors.white24),
          SizedBox(width: 4.w),
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white30,
              fontSize: 10.sp,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditHouseDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddHouseBottomSheet(
        propertyId: _houseData!['property_id']?.toString() ?? '',
        existingHouse: _houseData,
        onSaved: _loadFullDetails,
      ),
    );
  }

  void _showDeleteConfirmation() {
    final loc = LocalizationService.instance;
    final h = _houseData!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kGradientMid.withOpacity(0.95),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 10.w),
            Text(loc.translate("confirm_delete_house"), style: TextStyle(color: Colors.white, fontSize: 18.sp)),
          ],
        ),
        content: Text(
          "${loc.translate("confirm_delete")} '${h['house_number']}'? ${loc.translate("cannot_be_undone")}",
          style: TextStyle(color: Colors.white70, fontSize: 13.sp),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.translate("cancel"), style: TextStyle(color: Colors.white54, fontSize: 13.sp)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final provider = context.read<RentalProvider>();
              final success = await provider.deleteHouse(h['id'].toString());
              if (mounted) {
                if (success) {
                  ThemeConstants.showSuccessSnackBar(context, loc.translate("house_delete_success"));
                  Navigator.pop(context);
                } else {
                  ThemeConstants.showErrorSnackBar(context, loc.translate("house_delete_failed"));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
            child: Text(loc.translate("delete"), style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Animated gradient background
// ─────────────────────────────────────────────
class _AnimatedBackground extends StatefulWidget {
  const _AnimatedBackground();
  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 8))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _kGradientTop,
                Color.lerp(_kGradientMid,
                    const Color(0xFF0A3A4A), t)!,
                _kGradientBottom,
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Glass card base
// ─────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20.r),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: Colors.white.withOpacity(0.13)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: padding ?? EdgeInsets.symmetric(horizontal: 12.w, vertical: 16.h),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Section title row
// ─────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label, this.trailing});
  final IconData icon;
  final String   label;
  final Widget?  trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(7.w),
          decoration: BoxDecoration(
            color: _kOrange.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: _kOrange.withOpacity(0.25)),
          ),
          child: Icon(icon, color: _kOrange, size: 14.sp),
        ),
        SizedBox(width: 10.w),
        Text(label,
            style: TextStyle(
                color: Colors.white,
                fontSize: 14.sp,
                fontWeight: FontWeight.bold)),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Section divider widget (premium gradient line)
// ─────────────────────────────────────────────
class _SectionDivider extends StatelessWidget {
  const _SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.5,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.0),
            Colors.white.withOpacity(0.08),
            _kOrange.withOpacity(0.35),
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.0),
          ],
          stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Bottom action bar
// ─────────────────────────────────────────────
class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.isOccupied,
    required this.status,
    required this.isVacating,
    required this.onVacate,
    required this.onOnboard,
  });
  final bool isOccupied;
  final String status;
  final bool isVacating;
  final VoidCallback onVacate;
  final VoidCallback onOnboard;

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    
    Widget button;
    if (isOccupied) {
      button = InkWell(
        onTap: isVacating ? null : onVacate,
        borderRadius: BorderRadius.circular(14.r),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _kRed.withOpacity(0.85),
                const Color(0xFFC62828).withOpacity(0.9),
              ],
            ),
            borderRadius: BorderRadius.circular(14.r),
            boxShadow: [
              BoxShadow(
                  color: _kRed.withOpacity(0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Center(
            child: isVacating
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.exit_to_app_rounded, color: Colors.white),
                      SizedBox(width: 10.w),
                      Text(loc.translate("vacate_house"),
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.sp,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
          ),
        ),
      );
    } else if (status == 'vacant') {
      button = InkWell(
        onTap: onOnboard,
        borderRadius: BorderRadius.circular(14.r),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF97316), Color(0xFFFF6B35)],
            ),
            borderRadius: BorderRadius.circular(14.r),
            boxShadow: [
              BoxShadow(
                  color: _kOrange.withOpacity(0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
                SizedBox(width: 10.w),
                Text(loc.translate("onboard_tenant"),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );
    } else {
      return const SizedBox();
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(12.w, 16.h,
              12.w, MediaQuery.of(context).padding.bottom + 16.h),
          decoration: BoxDecoration(
            color: _kGradientTop.withOpacity(0.75),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52.h,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14.r),
              child: button,
            ),
          ),
        ),
      ),
    );
  }
}
