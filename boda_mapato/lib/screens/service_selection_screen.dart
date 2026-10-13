import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/theme_constants.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';

class ServiceSelectionScreen extends StatelessWidget {
  const ServiceSelectionScreen({
    super.key,
    this.allowedServices,
    this.deniedService,
  });

  /// Services this user may access. Null is treated as empty — no tiles shown.
  /// Always pass a non-null list derived from the user's role or bindings.
  final List<String>? allowedServices;

  /// When set, a warning banner is shown explaining that the user tried to
  /// access a service they are not bound to.
  final String? deniedService;

  static const String _serviceKey = 'selected_service';

  bool _allows(String service) =>
      allowedServices != null && allowedServices!.contains(service);

  bool get _hasAnyVisible =>
      _allows('inventory') || _allows('rental') || _allows('transport');

  Future<void> _selectService(BuildContext context, String service) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serviceKey, service);

    // Navigate to service home
    switch (service) {
      case 'inventory':
        if (context.mounted) {
          await Navigator.pushReplacementNamed(context, '/inventory');
        }
        return;
      case 'rental':
        if (context.mounted) {
          await Navigator.pushReplacementNamed(context, '/rental/dashboard');
        }
        return;
      case 'transport':
        if (context.mounted) {
          await Navigator.pushReplacementNamed(context, '/modern-dashboard');
        }
        return;
      default:
        if (context.mounted) {
          await Navigator.pushReplacementNamed(context, '/coming-soon',
              arguments: service);
        }
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(loc.translate('select_service')),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (deniedService != null)
                Container(
                  margin: EdgeInsets.only(bottom: 12.h),
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade800.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          loc.translate('service_access_denied'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              AutoSizeText(
                loc.translate('select_service_subtitle'),
                maxLines: 2,
                style: ThemeConstants.subHeadingStyle,
              ),
              SizedBox(height: 16.h),
              Expanded(
                child: _hasAnyVisible
                    ? _ServiceRows(
                        children: [
                          if (_allows('inventory'))
                            _ServiceTile(
                              icon: Icons.inventory_2_rounded,
                              label: loc.translate('inventory_service'),
                              onTap: () => _selectService(context, 'inventory'),
                            ),
                          if (_allows('rental'))
                            _ServiceTile(
                              icon: Icons.apartment_rounded,
                              label: loc.translate('rental_service'),
                              onTap: () => _selectService(context, 'rental'),
                            ),
                          if (_allows('transport'))
                            _ServiceTile(
                              icon: Icons.local_shipping_rounded,
                              label: loc.translate('transport_service'),
                              onTap: () =>
                                  _selectService(context, 'transport'),
                            ),
                        ],
                      )
                    : _NoServiceAccess(loc: loc),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the user has no service bindings at all.
/// Provides a logout button so they are not stuck on a dead screen.
class _NoServiceAccess extends StatefulWidget {
  const _NoServiceAccess({required this.loc});
  final LocalizationService loc;

  @override
  State<_NoServiceAccess> createState() => _NoServiceAccessState();
}

class _NoServiceAccessState extends State<_NoServiceAccess> {
  bool _loggingOut = false;

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      final auth = context.read<AuthProvider>();
      await auth.logout();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
      }
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSwahili = widget.loc.isSwahili;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 64.sp,
            color: ThemeConstants.textSecondary.withOpacity(0.35),
          ),
          SizedBox(height: 20.h),
          Text(
            isSwahili
                ? 'Huna ruhusa ya huduma yoyote.'
                : 'You have no access to any service.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ThemeConstants.textSecondary.withOpacity(0.8),
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            isSwahili
                ? 'Wasiliana na msimamizi wako\nkupata ufikiaji wa huduma.'
                : 'Contact your administrator\nto get access to a service.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ThemeConstants.textSecondary.withOpacity(0.55),
              fontSize: 13.sp,
            ),
          ),
          SizedBox(height: 32.h),
          SizedBox(
            width: 200.w,
            child: ElevatedButton.icon(
              onPressed: _loggingOut ? null : _logout,
              icon: _loggingOut
                  ? SizedBox(
                      width: 16.w,
                      height: 16.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.logout_rounded, size: 18),
              label: Text(
                isSwahili ? 'Rudi Kuingia' : 'Back to Login',
                style: TextStyle(fontSize: 14.sp),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey.shade700,
                foregroundColor: Colors.white,
                padding:
                    EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The services in rows of up to three, every row centred: three services sit side by side, two or one in the
/// middle, and a fourth would start a new row, also centred. (A two-column grid left the third service alone at the
/// left of a second row.)
class _ServiceRows extends StatelessWidget {
  const _ServiceRows({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double gap = 12.w;
        final double tileWidth = (box.maxWidth - 2 * gap) / 3;
        return SingleChildScrollView(
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: gap,
              runSpacing: 20.h,
              children: <Widget>[
                for (final Widget tile in children) SizedBox(width: tileWidth, child: tile),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16.r),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80.w,
              height: 80.w,
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 40.sp),
            ),
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.w),
              child: AutoSizeText(
                label,
                maxLines: 2,
                minFontSize: 10,
                maxFontSize: 14,
                overflow: TextOverflow.ellipsis,
                style: ThemeConstants.bodyStyle
                    .copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
