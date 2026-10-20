import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/theme_constants.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../utils/role_services.dart';

class ServiceSwitcherDialog extends StatelessWidget {
  const ServiceSwitcherDialog({super.key});

  static const String _serviceKey = 'selected_service';

  Future<void> _switchService(BuildContext context, String service) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serviceKey, service);

    if (!context.mounted) return;
    
    // Pop the dialog
    Navigator.pop(context);

    // Navigate to service home
    switch (service) {
      case 'inventory':
        Navigator.pushReplacementNamed(context, '/inventory');
      case 'rental':
        Navigator.pushReplacementNamed(context, '/rental/dashboard');
      case 'salon':
        Navigator.pushReplacementNamed(context, '/salon');
      case 'transport':
        Navigator.pushReplacementNamed(context, '/modern-dashboard');
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = LocalizationService.instance;
    final auth = context.read<AuthProvider>();
    final user = auth.user;

    // Compute which services this user may actually switch to —
    // same logic as the initial routing: explicit bindings take
    // priority, then role-based defaults.
    final List<String> allowed = pickableServices(
      bound: user?.serviceTypes ?? <String>[],
      role: user?.role ?? '',
      isSuperAdmin: user?.isSuperAdmin ?? false,
    );

    return Dialog(
      backgroundColor: ThemeConstants.primaryBlue,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      child: Padding(
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  loc.translate('select_service'),
                  style: ThemeConstants.headingStyle,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 4.w,
                runSpacing: 12.h,
                children: [
                  if (allowed.contains('inventory'))
                    _ServiceOption(
                      icon: Icons.inventory_2_rounded,
                      label: loc.translate('inventory_service'),
                      onTap: () => _switchService(context, 'inventory'),
                    ),
                  if (allowed.contains('rental'))
                    _ServiceOption(
                      icon: Icons.apartment_rounded,
                      label: loc.translate('rental_service'),
                      onTap: () => _switchService(context, 'rental'),
                    ),
                  if (allowed.contains('transport'))
                    _ServiceOption(
                      icon: Icons.local_shipping_rounded,
                      label: loc.translate('transport_service'),
                      onTap: () => _switchService(context, 'transport'),
                    ),
                  if (allowed.contains('salon'))
                    _ServiceOption(
                      icon: Icons.content_cut_rounded,
                      label: loc.translate('salon_service'),
                      onTap: () => _switchService(context, 'salon'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceOption extends StatelessWidget {

  const _ServiceOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
        child: Column(
          children: [
            Container(
              width: 56.w,
              height: 56.w,
              decoration: BoxDecoration(
                color: ThemeConstants.primaryOrange.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: ThemeConstants.primaryOrange.withOpacity(0.3)),
              ),
              child: Icon(icon, color: ThemeConstants.primaryOrange, size: 28.sp),
            ),
            SizedBox(height: 8.h),
            Text(
              label,
              style: ThemeConstants.bodyStyle.copyWith(
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
