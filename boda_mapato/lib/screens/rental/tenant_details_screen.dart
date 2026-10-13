import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../constants/theme_constants.dart';
import '../../providers/rental_provider.dart';
import '../../services/localization_service.dart';
import 'property_details_screen.dart';
import 'record_payment_screen.dart';

// ─────────────────────────────────────────────
// Color palette (local)
// ─────────────────────────────────────────────
const _kGradientTop    = Color(0xFF04121A);
const _kGradientMid    = Color(0xFF092D3A);
const _kGradientBottom = Color(0xFF0D485A);
const _kOrange         = Color(0xFFF97316);
const _kGreen          = Color(0xFF10B981);
const _kAmber          = Color(0xFFF59E0B);
const _kRed            = Color(0xFFEF4444);
const _kCard           = Color(0x14FFFFFF); // 8 % white

// ─────────────────────────────────────────────
class TenantDetailsScreen extends StatefulWidget {
  const TenantDetailsScreen({required this.tenant, super.key});
  final Map<dynamic, dynamic> tenant;

  @override
  State<TenantDetailsScreen> createState() => _TenantDetailsScreenState();
}

class _TenantDetailsScreenState extends State<TenantDetailsScreen>
    with SingleTickerProviderStateMixin {
  bool _isTerminating = false;
  Map<String, dynamic>? _tenantData;
  bool _isLoading = false;

  late final AnimationController _animCtrl;
  late final Animation<double>    _fadeAnim;
  late final Animation<Offset>    _slideAnim;

  @override
  void initState() {
    super.initState();
    _tenantData = Map<String, dynamic>.from(widget.tenant);

    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));

    _loadFullDetails();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFullDetails() async {
    setState(() => _isLoading = true);
    final data = await context
        .read<RentalProvider>()
        .fetchTenantDetails(_tenantData!['id'].toString());
    if (data != null && mounted) {
      final Map<String, dynamic> merged = {};
      if (data['tenant'] is Map) {
        merged.addAll(Map<String, dynamic>.from(data['tenant'] as Map));
      } else {
        merged.addAll(_tenantData!);
      }
      merged['profile']   = data['profile'];
      merged['agreement'] = data['agreement'];

      if (data['house'] is Map) {
        final houseMap = Map<String, dynamic>.from(data['house'] as Map);
        if (houseMap['property'] is Map) {
          houseMap['property_name'] ??= houseMap['property']['name'];
          houseMap['property_id']   ??= houseMap['property']['id'];
        }
        merged['house'] = houseMap;
      }
      merged['bills']    = data['bills'];
      merged['payments'] = data['payments'];

      setState(() {
        _tenantData = merged;
        _isLoading  = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
    _animCtrl.forward();
  }

  // ── Terminate agreement ─────────────────────
  Future<void> _handleTerminate() async {
    final loc = LocalizationService.instance;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title:   loc.translate('confirm_termination'),
        message: loc.translate('termination_message'),
        confirmLabel: loc.translate('terminate'),
        confirmColor: _kRed,
      ),
    );
    if ((confirmed ?? false) && mounted) {
      setState(() => _isTerminating = true);
      final success = await context
          .read<RentalProvider>()
          .terminateTenantAgreement(_tenantData!['id'].toString());
      if (mounted) {
        setState(() => _isTerminating = false);
        if (success) {
          ThemeConstants.showSuccessSnackBar(
              context, loc.translate('termination_success'));
          Navigator.pop(context);
        } else {
          ThemeConstants.showErrorSnackBar(
              context, loc.translate('termination_failed'));
        }
      }
    }
  }

  bool _hasEmploymentData(Map<String, dynamic> profile) {
    final emp = profile['employment'] is Map
        ? Map<String, dynamic>.from(profile['employment'] as Map)
        : <String, dynamic>{};
    if (emp.isEmpty) return false;
    final status = emp['status']?.toString() ?? '';
    final employer = emp['employer']?.toString() ?? '';
    final title = emp['title']?.toString() ?? '';
    final length = emp['length']?.toString() ?? '';
    final workPhone = emp['work_phone']?.toString() ?? '';
    return status.isNotEmpty || employer.isNotEmpty || title.isNotEmpty || length.isNotEmpty || workPhone.isNotEmpty;
  }

  bool _hasRentalHistoryData(Map<String, dynamic> profile) {
    final hist = profile['history'] is Map
        ? Map<String, dynamic>.from(profile['history'] as Map)
        : <String, dynamic>{};
    if (hist.isEmpty) return false;
    final prevAddress = hist['prev_address']?.toString() ?? '';
    final duration = hist['duration']?.toString() ?? '';
    final reason = hist['reason']?.toString() ?? '';
    final landlordName = hist['landlord_name']?.toString() ?? '';
    final landlordPhone = hist['landlord_phone']?.toString() ?? '';
    return prevAddress.isNotEmpty || duration.isNotEmpty || reason.isNotEmpty || landlordName.isNotEmpty || landlordPhone.isNotEmpty;
  }

  bool _hasOccupantsPetsData(Map<String, dynamic> profile) {
    final occ = profile['occupants'] is Map
        ? Map<String, dynamic>.from(profile['occupants'] as Map)
        : <String, dynamic>{};
    final pets = profile['pets'] is Map
        ? Map<String, dynamic>.from(profile['pets'] as Map)
        : <String, dynamic>{};
    if (occ.isEmpty && pets.isEmpty) return false;
    final adults = occ['adults']?.toString() ?? '0';
    final children = occ['children']?.toString() ?? '0';
    final petType = pets['type']?.toString() ?? 'None';
    return adults != '0' || children != '0' || petType != 'None';
  }

  List<Widget> _buildJoinedSections(
    BuildContext context,
    Map<String, dynamic> agreement,
    Map<String, dynamic> house,
    Map<String, dynamic> profile,
    Map<String, dynamic> t,
  ) {
    final list = <Widget>[];

    Widget wrapSection(Widget child) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 16.h),
        child: child,
      );
    }

    list.add(wrapSection(_AgreementCard(
      agreement: agreement,
      house: house,
      tenant: widget.tenant,
    )));

    list.add(wrapSection(_PersonalInfoCard(profile: profile, t: t)));

    if (_hasEmploymentData(profile)) {
      list.add(wrapSection(_EmploymentCard(profile: profile)));
    }

    if (_hasRentalHistoryData(profile)) {
      list.add(wrapSection(_RentalHistoryCard(profile: profile)));
    }

    if (_hasOccupantsPetsData(profile)) {
      list.add(wrapSection(_OccupantsPetsCard(profile: profile)));
    }

    final joined = <Widget>[];
    for (int i = 0; i < list.length; i++) {
      joined.add(list[i]);
      if (i < list.length - 1) {
        joined.add(const _SectionDivider());
      }
    }
    return joined;
  }

  // ── Build ───────────────────────────────────
  @override
  Widget build(BuildContext context) {
    _tenantData ??= Map<String, dynamic>.from(widget.tenant);
    final t   = _tenantData!;
    final loc = LocalizationService.instance;

    final house = t['house'] is Map
        ? Map<String, dynamic>.from(t['house'] as Map)
        : <String, dynamic>{};
    final agreement = t['agreement'] is Map
        ? Map<String, dynamic>.from(t['agreement'] as Map)
        : <String, dynamic>{};
    final profile = t['profile'] is Map
        ? Map<String, dynamic>.from(t['profile'] as Map)
        : <String, dynamic>{};
    final status = agreement['status'] as String? ?? 'active';

    return Scaffold(
      backgroundColor: _kGradientTop,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Background gradient
          const _AnimatedBackground(),

          // ── Main scrollable content
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Hero app bar
              SliverAppBar(
                expandedHeight: 260.h,
                pinned: true,
                backgroundColor: _kGradientTop.withOpacity(0.85),
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
                actions: [
                  if (_isLoading)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: Center(
                        child: SizedBox(
                          width: 18.w,
                          height: 18.w,
                          child: const CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        ),
                      ),
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: _HeroHeader(tenant: t, status: status),
                ),
              ),

              // ── Cards
              SliverPadding(
                padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 100.h),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 20.h),
                            _GlassCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _buildJoinedSections(
                                  context,
                                  agreement,
                                  house,
                                  profile,
                                  t,
                                ),
                              ),
                            ),
                            SizedBox(height: 24.h),
                          ],
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),

          // ── Bottom terminate button
          if (status != 'terminated')
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _BottomActionBar(
                isLoading: _isTerminating,
                onTerminate: _handleTerminate,
              ),
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
// Hero header (flexible space)
// ─────────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.tenant, required this.status});
  final Map<String, dynamic> tenant;
  final String status;

  @override
  Widget build(BuildContext context) {
    final String name     = tenant['name'] ?? 'N/A';
    final String phone    = tenant['phone_number'] ?? '';
    final String email    = tenant['email'] ?? '';
    final String? photoUrl = tenant['photo_url'] as String?;
    final String initial  = name.isNotEmpty ? name[0].toUpperCase() : '?';

    Color statusColor = _kGreen;
    if (status == 'notice')     statusColor = _kAmber;
    if (status == 'defaulter')  statusColor = _kRed;
    if (status == 'terminated') statusColor = Colors.white38;

    return Stack(
      children: [
        // Background arc decoration
        Positioned.fill(
          child: CustomPaint(painter: _ArcPainter()),
        ),
        // Subtle radial glow behind avatar
        Positioned(
          top: 60.h, left: 0, right: 0,
          child: Center(
            child: Container(
              width: 120.w, height: 120.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  _kOrange.withOpacity(0.18),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        ),
        // Content
        Positioned(
          bottom: 24.h, left: 0, right: 0,
          child: Column(
            children: [
              // Avatar
              Container(
                width: 82.w, height: 82.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      _kOrange.withOpacity(0.9),
                      const Color(0xFFFF6B35),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.3), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: _kOrange.withOpacity(0.4),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                  image: photoUrl != null
                      ? DecorationImage(
                          image: NetworkImage(photoUrl), fit: BoxFit.cover)
                      : null,
                ),
                child: photoUrl == null
                    ? Center(
                        child: Text(initial,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 32.sp,
                                fontWeight: FontWeight.bold)),
                      )
                    : null,
              ),
              SizedBox(height: 12.h),
              // Name
              Text(name,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  )),
              SizedBox(height: 4.h),
              if (phone.isNotEmpty)
                Text(phone,
                    style: TextStyle(
                        color: Colors.white70, fontSize: 13.sp)),
              if (email.isNotEmpty)
                Text(email,
                    style: TextStyle(
                        color: Colors.white38, fontSize: 11.sp)),
              SizedBox(height: 10.h),
              // Status badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 5.h),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6.w, height: 6.w,
                      decoration: BoxDecoration(
                          color: statusColor, shape: BoxShape.circle),
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      LocalizationService.instance.translate(status).toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Arc painter for visual interest
// ─────────────────────────────────────────────
class _ArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          _kOrange.withOpacity(0.08),
          const Color(0xFF1BA3C7).withOpacity(0.10),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, size.height * 0.6)
      ..quadraticBezierTo(
          size.width * 0.5, size.height * 0.3,
          size.width, size.height * 0.55)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);

    final circlePaint = Paint()
      ..color = _kOrange.withOpacity(0.06)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 0.15),
        size.width * 0.18,
        circlePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
// Section divider widget (premium gradient line)
// ─────────────────────────────────────────────
class _SectionDivider extends StatelessWidget {
  const _SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          height: 2.h,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0.0),
                Colors.white.withOpacity(0.08),
                _kOrange.withOpacity(0.45),
                Colors.white.withOpacity(0.08),
                Colors.white.withOpacity(0.0),
              ],
              stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
            ),
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
// Agreement card
// ─────────────────────────────────────────────
class _AgreementCard extends StatelessWidget {
  const _AgreementCard({
    required this.agreement,
    required this.house,
    required this.tenant,
  });
  final Map<String, dynamic> agreement;
  final Map<String, dynamic> house;
  final Map<dynamic, dynamic> tenant;

  String _formatDate(dynamic raw) {
    if (raw == null || raw.toString().isEmpty) return '-';
    try {
      final dt = DateTime.parse(raw.toString());
      return '${dt.day.toString().padLeft(2, '0')} / '
          '${dt.month.toString().padLeft(2, '0')} / ${dt.year}';
    } catch (_) {
      return raw.toString();
    }
  }

  String _formatAmount(dynamic raw) {
    if (raw == null) return '0';
    final s = raw.toString().split('.').first;
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return s.replaceAllMapped(reg, (m) => '${m[1]},');
  }

  List<String> _parseSelectedUnits(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return [];
      
      // If it starts with [ and ends with ], try parsing as JSON or stripping brackets
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        final inner = trimmed.substring(1, trimmed.length - 1);
        if (inner.isEmpty) return [];
        return inner
            .split(',')
            .map((e) => e.replaceAll('"', '').replaceAll("'", '').replaceAll(r'\', '').trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      
      if (trimmed.contains(',')) {
        return trimmed.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      return [trimmed];
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    final selectedUnits = _parseSelectedUnits(agreement['selected_units']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          _SectionTitle(
            icon: Icons.description_rounded,
            label: loc.translate('rental_agreement'),
            trailing: _RecordPaymentButton(tenant: tenant),
          ),
          Divider(height: 24.h, color: Colors.white10),

          // Rent amount hero chip
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 16.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _kOrange.withOpacity(0.18),
                  const Color(0xFF1BA3C7).withOpacity(0.12),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: _kOrange.withOpacity(0.22)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loc.translate('rent_amount'),
                        style: TextStyle(
                            color: Colors.white54, fontSize: 10.sp,
                            letterSpacing: 0.5)),
                    SizedBox(height: 4.h),
                    Text(
                      'Tsh ${_formatAmount(agreement['rent_amount'])}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: _kOrange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(Icons.payments_outlined,
                      color: _kOrange, size: 22.sp),
                ),
              ],
            ),
          ),

          SizedBox(height: 16.h),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              children: [
                _ClickableRow(
                  label: loc.translate('house'),
                  value: house['house_number']?.toString() ?? '-',
                  icon: Icons.home_work_outlined,
                  onTap: () => Navigator.pushNamed(
                      context, '/rental/house-details',
                      arguments: house).then((_) {
                    if (context.mounted) context.read<RentalProvider>().fetchTenants();
                  }),
                  showBorder: true,
                ),
                _ClickableRow(
                  label: loc.translate('property'),
                  value: house['property_name']?.toString() ?? '-',
                  icon: Icons.apartment_rounded,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PropertyDetailsScreen(
                          propertyId: house['property_id']?.toString() ?? ''),
                    ),
                  ).then((_) {
                    if (context.mounted) context.read<RentalProvider>().fetchTenants();
                  }),
                  showBorder: true,
                ),
                _DetailTableRow(
                  label: loc.translate('start_date'),
                  value: _formatDate(agreement['start_date']),
                  icon: Icons.calendar_today_outlined,
                  showBorder: selectedUnits.isNotEmpty,
                ),
                if (selectedUnits.isNotEmpty)
                  _DetailTableRow(
                    label: loc.isSwahili ? 'Vyumba/Vipengele' : 'Rented Units',
                    value: selectedUnits.join(', '),
                    icon: Icons.grid_view_rounded,
                    showBorder: false,
                  ),
              ],
            ),
          ),
        ],
      );
  }
}

// ─────────────────────────────────────────────
// Record payment button
// ─────────────────────────────────────────────
class _RecordPaymentButton extends StatelessWidget {
  const _RecordPaymentButton({required this.tenant});
  final Map<dynamic, dynamic> tenant;

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RecordPaymentScreen(
              preSelectedTenant: Map<String, dynamic>.from(tenant),
            ),
          ),
        ).then((_) {
          if (context.mounted) context.read<RentalProvider>().fetchTenants();
        }),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF97316), Color(0xFFFF6B35)],
            ),
            borderRadius: BorderRadius.circular(10.r),
            boxShadow: [
              BoxShadow(
                  color: _kOrange.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline_rounded,
                  color: Colors.white, size: 12.sp),
              SizedBox(width: 5.w),
              Text(loc.translate('record_payment'),
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Personal info card
// ─────────────────────────────────────────────
class _PersonalInfoCard extends StatelessWidget {
  const _PersonalInfoCard(
      {required this.profile, required this.t});
  final Map<String, dynamic> profile;
  final Map<String, dynamic> t;

  String _formatDate(dynamic raw) {
    if (raw == null || raw.toString().isEmpty) return '-';
    try {
      final dt = DateTime.parse(raw.toString());
      return '${dt.day.toString().padLeft(2, '0')} / '
          '${dt.month.toString().padLeft(2, '0')} / ${dt.year}';
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;

    final nida = profile['nida'] ?? profile['id_number'] ?? '-';
    final gender = profile['gender'] ?? '-';
    final occupation = profile['occupation'] ??
        (profile['employment'] is Map
            ? profile['employment']['title']
            : null) ?? '-';
    final emName = (profile['emergency_contact'] is Map
        ? profile['emergency_contact']['name']
        : profile['emergency_contact_name']) ?? '-';
    final emPhone = (profile['emergency_contact'] is Map
        ? profile['emergency_contact']['phone']
        : profile['emergency_contact_phone']) ?? '-';
    final emRelationship = (profile['emergency_contact'] is Map
        ? profile['emergency_contact']['relationship']
        : profile['emergency_contact_relationship']) ?? '-';
    final notes = (profile['notes'] ?? '').toString();
    final photoUrl = profile['photo_url'] as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          _SectionTitle(
            icon: Icons.person_rounded,
            label: loc.translate('personal_info'),
          ),
          Divider(height: 24.h, color: Colors.white10),

          // Grid-style info pills (NIDA + gender)
          Row(children: [
            Expanded(child: _InfoPill(
              icon: Icons.fingerprint_rounded,
              label: 'NIDA / ID',
              value: nida.toString(),
              color: const Color(0xFF1BA3C7),
            )),
            SizedBox(width: 10.w),
            Expanded(child: _InfoPill(
              icon: Icons.wc_rounded,
              label: loc.translate('gender'),
              value: gender.toString(),
              color: _kAmber,
            )),
          ]),
          SizedBox(height: 10.h),
          _InfoPill(
            icon: Icons.work_outline_rounded,
            label: loc.translate('occupation'),
            value: occupation.toString().toUpperCase(),
            color: _kGreen,
            fullWidth: true,
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
                _DetailGridRow(
                  item1Label: loc.isSwahili ? 'Tarehe ya Kuzaliwa' : 'Birth Date',
                  item1Value: _formatDate(profile['dob']),
                  item1Icon: Icons.cake_outlined,
                  item2Label: loc.isSwahili ? 'Mkoa wa Kitambulisho' : 'ID State Issued',
                  item2Value: profile['id_state']?.toString() ?? '-',
                  item2Icon: Icons.map_outlined,
                  showBorder: true,
                ),
                _DetailTableRow(
                  label: loc.isSwahili ? 'Mwisho wa Kitambulisho' : 'ID Expiration Date',
                  value: _formatDate(profile['id_expiration']),
                  icon: Icons.event_busy_outlined,
                  showBorder: false,
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),

          // Emergency contact section
          Container(
            decoration: BoxDecoration(
              color: _kRed.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: _kRed.withOpacity(0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 6.h),
                  child: Row(children: [
                    Icon(Icons.emergency_outlined, color: _kRed.withOpacity(0.8), size: 14.sp),
                    SizedBox(width: 8.w),
                    Text(
                      loc.isSwahili ? 'MAWASILIANO YA DHARURA' : 'EMERGENCY CONTACT',
                      style: TextStyle(
                          color: _kRed.withOpacity(0.8),
                          fontSize: 9.sp,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5),
                    ),
                  ]),
                ),
                Divider(height: 1, color: _kRed.withOpacity(0.15)),
                _DetailTableRow(
                  label: loc.translate('emergency_contact'),
                  value: emName.toString(),
                  icon: Icons.person_outline_rounded,
                  showBorder: true,
                ),
                _DetailGridRow(
                  item1Label: loc.isSwahili ? 'Uhusiano' : 'Relationship',
                  item1Value: emRelationship.toString(),
                  item1Icon: Icons.family_restroom_outlined,
                  item2Label: loc.translate('emergency_phone'),
                  item2Value: emPhone.toString(),
                  item2Icon: Icons.phone_outlined,
                  showBorder: false,
                ),
              ],
            ),
          ),

          if (notes.isNotEmpty) ...[
            SizedBox(height: 14.h),
            Text(LocalizationService.instance.translate('description').toUpperCase(),
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 9.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
            SizedBox(height: 6.h),
            Text(notes,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 12.sp,
                    height: 1.5)),
          ],

          if (photoUrl != null) ...[
            SizedBox(height: 12.h),
            Row(children: [
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: _kGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: _kGreen.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded,
                      color: _kGreen, size: 13.sp),
                  SizedBox(width: 5.w),
                  Text(LocalizationService.instance.translate('photo_uploaded'),
                      style: TextStyle(
                          color: _kGreen,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ],
        ],
      );
  }
}

// ─────────────────────────────────────────────
// Employment card
// ─────────────────────────────────────────────
class _EmploymentCard extends StatelessWidget {
  const _EmploymentCard({required this.profile});
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    final isSw = loc.isSwahili;
    final emp = profile['employment'] is Map
        ? Map<String, dynamic>.from(profile['employment'] as Map)
        : <String, dynamic>{};

    if (emp.isEmpty) return const SizedBox();

    final status = emp['status']?.toString() ?? '';
    final employer = emp['employer']?.toString() ?? '';
    final title = emp['title']?.toString() ?? '';
    final length = emp['length']?.toString() ?? '';
    final workPhone = emp['work_phone']?.toString() ?? '';

    if (status.isEmpty && employer.isEmpty && title.isEmpty && length.isEmpty && workPhone.isEmpty) {
      return const SizedBox();
    }

    String statusLabel = status;
    if (status == 'Employed') {
      statusLabel = isSw ? 'Ameajiriwa' : 'Employed';
    } else if (status == 'Unemployed') {
      statusLabel = isSw ? 'Hajaajiriwa' : 'Unemployed';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          _SectionTitle(
            icon: Icons.business_center_rounded,
            label: isSw ? 'KAZI NA KIPATO' : 'EMPLOYMENT & INCOME',
          ),
          Divider(height: 24.h, color: Colors.white10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              children: [
                _DetailTableRow(
                  label: isSw ? 'Hali ya Ajira' : 'Employment Status',
                  value: statusLabel,
                  icon: Icons.assignment_ind_outlined,
                  showBorder: employer.isNotEmpty || title.isNotEmpty || length.isNotEmpty || workPhone.isNotEmpty,
                ),
                if (employer.isNotEmpty || title.isNotEmpty)
                  _DetailGridRow(
                    item1Label: isSw ? 'Mwajiri' : 'Employer',
                    item1Value: employer.isNotEmpty ? employer : '-',
                    item1Icon: Icons.business_outlined,
                    item2Label: isSw ? 'Cheo / Kazi' : 'Job Title',
                    item2Value: title.isNotEmpty ? title : '-',
                    item2Icon: Icons.badge_outlined,
                    showBorder: length.isNotEmpty || workPhone.isNotEmpty,
                  ),
                if (length.isNotEmpty || workPhone.isNotEmpty)
                  _DetailGridRow(
                    item1Label: isSw ? 'Muda wa Kazi' : 'Employment Duration',
                    item1Value: length.isNotEmpty ? length : '-',
                    item1Icon: Icons.timer_outlined,
                    item2Label: isSw ? 'Simu ya Kazini' : 'Work Phone',
                    item2Value: workPhone.isNotEmpty ? workPhone : '-',
                    item2Icon: Icons.phone_callback_outlined,
                    showBorder: false,
                  ),
              ],
            ),
          ),
        ],
      );
  }
}

// ─────────────────────────────────────────────
// Rental History card
// ─────────────────────────────────────────────
class _RentalHistoryCard extends StatelessWidget {
  const _RentalHistoryCard({required this.profile});
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    final isSw = loc.isSwahili;
    final hist = profile['history'] is Map
        ? Map<String, dynamic>.from(profile['history'] as Map)
        : <String, dynamic>{};

    if (hist.isEmpty) return const SizedBox();

    final prevAddress = hist['prev_address']?.toString() ?? '';
    final duration = hist['duration']?.toString() ?? '';
    final reason = hist['reason']?.toString() ?? '';
    final landlordName = hist['landlord_name']?.toString() ?? '';
    final landlordPhone = hist['landlord_phone']?.toString() ?? '';

    if (prevAddress.isEmpty && duration.isEmpty && reason.isEmpty && landlordName.isEmpty && landlordPhone.isEmpty) {
      return const SizedBox();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          _SectionTitle(
            icon: Icons.history_rounded,
            label: isSw ? 'HISTORIA YA UPANGAJI' : 'RENTAL HISTORY',
          ),
          Divider(height: 24.h, color: Colors.white10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              children: [
                if (prevAddress.isNotEmpty || duration.isNotEmpty)
                  _DetailGridRow(
                    item1Label: isSw ? 'Anwani ya Awali' : 'Previous Address',
                    item1Value: prevAddress.isNotEmpty ? prevAddress : '-',
                    item1Icon: Icons.home_work_outlined,
                    item2Label: isSw ? 'Muda wa Kuishi' : 'Stay Duration',
                    item2Value: duration.isNotEmpty ? duration : '-',
                    item2Icon: Icons.calendar_today_outlined,
                    showBorder: reason.isNotEmpty || landlordName.isNotEmpty || landlordPhone.isNotEmpty,
                  ),
                if (reason.isNotEmpty)
                  _DetailTableRow(
                    label: isSw ? 'Sababu ya Kuhama' : 'Reason for Leaving',
                    value: reason,
                    icon: Icons.exit_to_app_outlined,
                    showBorder: landlordName.isNotEmpty || landlordPhone.isNotEmpty,
                  ),
                if (landlordName.isNotEmpty || landlordPhone.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 12.w),
                    color: Colors.white.withOpacity(0.02),
                    child: Text(
                      isSw ? 'MWEZESHAJI / MMILIKI WA AWALI' : 'PREVIOUS LANDLORD',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  _DetailGridRow(
                    item1Label: isSw ? 'Jina la Mwenye Nyumba' : 'Landlord Name',
                    item1Value: landlordName.isNotEmpty ? landlordName : '-',
                    item1Icon: Icons.person_pin_outlined,
                    item2Label: isSw ? 'Simu ya Mwenye Nyumba' : 'Landlord Phone',
                    item2Value: landlordPhone.isNotEmpty ? landlordPhone : '-',
                    item2Icon: Icons.phone_outlined,
                    showBorder: false,
                  ),
                ],
              ],
            ),
          ),
        ],
      );
  }
}

// ─────────────────────────────────────────────
// Occupants & Pets card
// ─────────────────────────────────────────────
class _OccupantsPetsCard extends StatelessWidget {
  const _OccupantsPetsCard({required this.profile});
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    final isSw = loc.isSwahili;

    final occ = profile['occupants'] is Map
        ? Map<String, dynamic>.from(profile['occupants'] as Map)
        : <String, dynamic>{};
    final pets = profile['pets'] is Map
        ? Map<String, dynamic>.from(profile['pets'] as Map)
        : <String, dynamic>{};

    if (occ.isEmpty && pets.isEmpty) return const SizedBox();

    final adults = occ['adults']?.toString() ?? '0';
    final children = occ['children']?.toString() ?? '0';
    final othersWillLive = occ['others_will_live'];
    final petType = pets['type']?.toString() ?? 'None';
    final petBreed = pets['breed']?.toString() ?? '';
    final petAge = pets['age']?.toString() ?? '';
    final petWeight = pets['weight']?.toString() ?? '';

    if (adults == '0' && children == '0' && petType == 'None') {
      return const SizedBox();
    }

    String othersLabel = '-';
    if (othersWillLive != null) {
      if (othersWillLive == true || othersWillLive == 1 || othersWillLive.toString().toLowerCase() == 'yes') {
        othersLabel = isSw ? 'Ndiyo' : 'Yes';
      } else {
        othersLabel = isSw ? 'Hapana' : 'No';
      }
    }

    String petTypeLabel = petType;
    if (petType == 'None') {
      petTypeLabel = isSw ? 'Hakuna' : 'None';
    } else if (petType == 'Dog') {
      petTypeLabel = isSw ? 'Mbwa' : 'Dog';
    } else if (petType == 'Cat') {
      petTypeLabel = isSw ? 'Paka' : 'Cat';
    } else if (petType == 'Other') {
      petTypeLabel = isSw ? 'Nyingine' : 'Other';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          _SectionTitle(
            icon: Icons.people_outline_rounded,
            label: isSw ? 'WAKAZI NA WAFUGAJI' : 'OCCUPANTS & PETS',
          ),
          Divider(height: 24.h, color: Colors.white10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              children: [
                if (occ.isNotEmpty) ...[
                  _DetailGridRow(
                    item1Label: isSw ? 'Watu Wazima' : 'Adults Count',
                    item1Value: adults,
                    item1Icon: Icons.person_outline_rounded,
                    item2Label: isSw ? 'Watoto' : 'Children Count',
                    item2Value: children,
                    item2Icon: Icons.child_care_rounded,
                    showBorder: true,
                  ),
                  _DetailTableRow(
                    label: isSw ? 'Je, kuna wengine watakaishi?' : 'Will others live here?',
                    value: othersLabel,
                    icon: Icons.group_add_outlined,
                    showBorder: pets.isNotEmpty && petType != 'None',
                  ),
                ],
                if (pets.isNotEmpty && petType != 'None') ...[
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 12.w),
                    color: Colors.white.withOpacity(0.02),
                    child: Text(
                      isSw ? 'TAARIFA ZA MNYAMA' : 'PET INFORMATION',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  _DetailGridRow(
                    item1Label: isSw ? 'Mnyama wa Kufugwa' : 'Pet Type',
                    item1Value: petTypeLabel,
                    item1Icon: Icons.pets_rounded,
                    item2Label: isSw ? 'Aina ya Mnyama (Breed)' : 'Pet Breed',
                    item2Value: petBreed.isNotEmpty ? petBreed : '-',
                    item2Icon: Icons.category_outlined,
                    showBorder: petAge.isNotEmpty || petWeight.isNotEmpty,
                  ),
                  if (petAge.isNotEmpty || petWeight.isNotEmpty)
                    _DetailGridRow(
                      item1Label: isSw ? 'Umri wa Mnyama' : 'Pet Age',
                      item1Value: petAge.isNotEmpty ? (isSw ? '$petAge miaka' : '$petAge years') : '-',
                      item1Icon: Icons.cake_outlined,
                      item2Label: isSw ? 'Uzito wa Mnyama' : 'Pet Weight',
                      item2Value: petWeight.isNotEmpty ? '$petWeight kg' : '-',
                      item2Icon: Icons.scale_outlined,
                      showBorder: false,
                    ),
                ],
              ],
            ),
          ),
        ],
      );
  }
}

// ─────────────────────────────────────────────
// Info pill widget (colored background cell)
// ─────────────────────────────────────────────
class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.fullWidth = false,
  });
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;
  final bool     fullWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 9.sp,
                        letterSpacing: 0.4)),
                SizedBox(height: 2.h),
                Text(value,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Clickable info row (with chevron)
// ─────────────────────────────────────────────
class _ClickableRow extends StatelessWidget {
  const _ClickableRow({
    required this.label,
    required this.value,
    required this.onTap,
    required this.icon,
    this.showBorder = true,
  });
  final String   label;
  final String   value;
  final VoidCallback onTap;
  final IconData icon;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10.r),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
          decoration: BoxDecoration(
            border: showBorder
                ? Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white24, size: 15.sp),
              SizedBox(width: 10.w),
              Text(label,
                  style: TextStyle(color: Colors.white54, fontSize: 12.sp)),
              const Spacer(),
              Text(value,
                  style: TextStyle(
                      color: _kOrange,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600)),
              SizedBox(width: 4.w),
              Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white24, size: 10.sp),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Grid row (two columns side by side)
// ─────────────────────────────────────────────
class _DetailGridRow extends StatelessWidget {
  const _DetailGridRow({
    required this.item1Label,
    required this.item1Value,
    required this.item1Icon,
    required this.item2Label,
    required this.item2Value,
    required this.item2Icon,
    this.showBorder = true,
  });
  final String item1Label;
  final String item1Value;
  final IconData item1Icon;
  final String item2Label;
  final String item2Value;
  final IconData item2Icon;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: showBorder
            ? Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))
            : null,
      ),
      child: Row(
        children: [
          // Column 1
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: Row(
                children: [
                  Icon(item1Icon, color: _kOrange.withOpacity(0.7), size: 14.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item1Label, style: TextStyle(color: Colors.white38, fontSize: 9.sp), overflow: TextOverflow.ellipsis),
                        SizedBox(height: 2.h),
                        Text(item1Value, style: TextStyle(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Column 2
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
              child: Row(
                children: [
                  Icon(item2Icon, color: _kOrange.withOpacity(0.7), size: 14.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item2Label, style: TextStyle(color: Colors.white38, fontSize: 9.sp), overflow: TextOverflow.ellipsis),
                        SizedBox(height: 2.h),
                        Text(item2Value, style: TextStyle(color: Colors.white, fontSize: 11.sp, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Table row (label + value)
// ─────────────────────────────────────────────
class _DetailTableRow extends StatelessWidget {
  const _DetailTableRow({
    required this.label,
    required this.value,
    required this.icon,
    this.showBorder = true,
  });
  final String label;
  final String value;
  final IconData icon;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
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
}

// ─────────────────────────────────────────────
// Plain info row
// ─────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, required this.icon});
  final String   label;
  final String   value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 7.h),
      child: Row(
        children: [
          Icon(icon, color: Colors.white24, size: 14.sp),
          SizedBox(width: 10.w),
          Text(label,
              style: TextStyle(color: Colors.white54, fontSize: 12.sp)),
          const Spacer(),
          Flexible(
            child: Text(value,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Bottom action bar
// ─────────────────────────────────────────────
class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar(
      {required this.isLoading, required this.onTerminate});
  final bool isLoading;
  final VoidCallback onTerminate;

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
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
              child: InkWell(
                onTap: isLoading ? null : onTerminate,
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
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.person_remove_rounded,
                                  color: Colors.white),
                              SizedBox(width: 10.w),
                              Text(loc.translate('terminate_agreement'),
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Confirm dialog
// ─────────────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });
  final String title;
  final String message;
  final String confirmLabel;
  final Color  confirmColor;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: _kGradientMid.withOpacity(0.92),
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: Colors.white.withOpacity(0.14)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(14.w),
                  decoration: BoxDecoration(
                    color: confirmColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.warning_amber_rounded,
                      color: confirmColor, size: 28.sp),
                ),
                SizedBox(height: 16.h),
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 8.h),
                Text(message,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Colors.white70, fontSize: 13.sp)),
                SizedBox(height: 24.h),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r)),
                      ),
                      child: Text(LocalizationService.instance.translate('cancel'),
                          style: const TextStyle(color: Colors.white70)),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: confirmColor,
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r)),
                        shadowColor: confirmColor.withOpacity(0.5),
                        elevation: 6,
                      ),
                      child: Text(confirmLabel,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.sp)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
