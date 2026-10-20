import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/theme_constants.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../widgets/pending_registrations_count.dart';
import 'admin/registrations_screen.dart';

class ServiceSelectionScreen extends StatelessWidget {
  const ServiceSelectionScreen({
    super.key,
    this.allowedServices,
    this.deniedService,
    this.registrationsSource,
  });

  /// Where the "registration requests" card gets its numbers (the server in the app, a fake in tests).
  final RegistrationsDataSource? registrationsSource;

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
      _allows('inventory') || _allows('rental') || _allows('transport') || _allows('salon');

  /// Only a super admin reviews registrations. (No signed-in user, or no provider at all, means no.)
  bool _isSuperAdmin(BuildContext context) {
    try {
      return Provider.of<AuthProvider>(context, listen: false).user?.isSuperAdmin ?? false;
    } on ProviderNotFoundException {
      return false;
    }
  }

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
      case 'salon':
        if (context.mounted) {
          await Navigator.pushReplacementNamed(context, '/salon');
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
              if (_isSuperAdmin(context))
                _RegistrationRequestsCard(source: registrationsSource),
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
                          if (_allows('salon'))
                            _ServiceTile(
                              icon: Icons.content_cut_rounded,
                              label: loc.translate('salon_service'),
                              onTap: () => _selectService(context, 'salon'),
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

/// For the super admin: how many businesses are waiting to be let in, one tap from the list. Visible the moment
/// they sign in, so a new request is never buried under Settings.
class _RegistrationRequestsCard extends StatefulWidget {
  const _RegistrationRequestsCard({this.source});

  final RegistrationsDataSource? source;

  @override
  State<_RegistrationRequestsCard> createState() => _RegistrationRequestsCardState();
}

class _RegistrationRequestsCardState extends State<_RegistrationRequestsCard> {
  final GlobalKey<PendingRegistrationsCountState> _count = GlobalKey<PendingRegistrationsCountState>();

  Future<void> _open() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (BuildContext _) => RegistrationsScreen(dataSource: widget.source)),
    );
    // approving or rejecting changed the number
    await _count.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = LocalizationService.instance;
    return PendingRegistrationsCount(
      key: _count,
      source: widget.source,
      builder: (BuildContext context, int? pending) {
        final bool waiting = (pending ?? 0) > 0;
        return Container(
          margin: EdgeInsets.only(bottom: 14.h),
          child: Material(
            color: (waiting ? Colors.amber : Colors.white).withValues(alpha: waiting ? 0.16 : 0.06),
            borderRadius: BorderRadius.circular(14.r),
            child: InkWell(
              key: const ValueKey<String>('registration_requests_card'),
              borderRadius: BorderRadius.circular(14.r),
              onTap: _open,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: (waiting ? Colors.amber : Colors.white24).withValues(alpha: waiting ? 0.7 : 1)),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.how_to_reg_rounded, color: waiting ? Colors.amber : Colors.white70, size: 28.sp),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            loc.translate('registration_requests_title'),
                            style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            key: const ValueKey<String>('registration_requests_subtitle'),
                            waiting
                                ? loc.translateWith('registration_requests_waiting', <Object?>[pending])
                                : loc.translate('registration_requests_none'),
                            style: TextStyle(color: waiting ? Colors.amber : Colors.white54, fontSize: 12.sp),
                          ),
                        ],
                      ),
                    ),
                    CountBadge(count: pending),
                    SizedBox(width: 6.w),
                    const Icon(Icons.chevron_right, color: Colors.white54),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
