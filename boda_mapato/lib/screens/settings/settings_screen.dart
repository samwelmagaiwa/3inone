import "package:flutter/material.dart";
import "package:file_picker/file_picker.dart";
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import "../../config/api_config.dart";
import "../../constants/theme_constants.dart";
import "../../providers/auth_provider.dart";
import "../../services/localization_service.dart";
import "language_screen.dart";
import "notifications_screen.dart";
import "security_screen.dart";
import "backup_screen.dart";
import "help_screen.dart";
import "../../widgets/subscription_banner.dart";
import "business_profile_screen.dart";
import "user_management_screen.dart";
import 'subscription_screen.dart';
import "super_admin_tiles.dart";

// ignore_for_file: directives_ordering
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final LocalizationService _localizationService = LocalizationService.instance;

  @override
  void initState() {
    super.initState();
    // Listen for language changes to rebuild the screen
    _localizationService.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final AuthProvider authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final isSuperAdmin = user?.isSuperAdmin ?? false;
    final isAdmin = user?.isAdmin ?? false;
    final loc = _localizationService;
    // Staff and owners belong to a business and see its details; drivers, tenants and fundis are the
    // business's customers and have no use for them here.
    final belongsToBusiness = user?.business != null &&
        !const <String>['driver', 'tenant', 'vendor'].contains(user!.role);

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(loc.translate('settings')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Profile Card ───────────────────────────────────────────
              ThemeConstants.buildGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: isSuperAdmin
                                ? const Color(0xFFB8860B) // dark gold
                                : ThemeConstants.primaryOrange,
                            backgroundImage: _buildAvatarImage(authProvider),
                            child: _buildAvatarImage(authProvider) == null
                                ? (user?.name != null && user!.name.isNotEmpty)
                                    ? Text(
                                        user.name.substring(0, 1).toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : const Icon(Icons.person,
                                        color: Colors.white, size: 40)
                                : null,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: InkWell(
                              onTap: () => _pickAndUploadImage(authProvider),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        user?.name ?? LocalizationService.instance.translate('user'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: ThemeConstants.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.email ?? '',
                        style: const TextStyle(
                            fontSize: 13, color: ThemeConstants.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      // Role badge — visually distinguishes the two admin levels
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: isSuperAdmin
                              ? const Color(0xFFB8860B).withOpacity(0.25)
                              : Colors.blueGrey.shade700.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSuperAdmin
                                ? const Color(0xFFB8860B).withOpacity(0.6)
                                : Colors.blueGrey.shade400.withOpacity(0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isSuperAdmin
                                  ? Icons.verified_user_rounded
                                  : Icons.manage_accounts_rounded,
                              size: 14,
                              color: isSuperAdmin
                                  ? const Color(0xFFFFD700)
                                  : Colors.blueGrey.shade200,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isSuperAdmin ? LocalizationService.instance.translate('super_admin').toUpperCase() : isAdmin ? LocalizationService.instance.translate('admin').toUpperCase() : (user?.role?.toUpperCase() ?? ''),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isSuperAdmin
                                    ? const Color(0xFFFFD700)
                                    : Colors.blueGrey.shade200,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Admin: show assigned services under the badge
                      if (isAdmin && !isSuperAdmin) ...[
                        const SizedBox(height: 8),
                        Builder(builder: (_) {
                          final svcs = user?.serviceTypes ?? [];
                          if (svcs.isEmpty) return const SizedBox.shrink();
                          return Wrap(
                            spacing: 6,
                            children: svcs
                                .map((s) => Chip(
                                      label: Text(s,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.white70)),
                                      backgroundColor:
                                          Colors.white.withOpacity(0.08),
                                      padding: EdgeInsets.zero,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ))
                                .toList(),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),

              // ── The business this person works for ──────────────────────
              if (belongsToBusiness) ...[
                const SizedBox(height: 20),
                SubscriptionBanner(
                  billing: user.business!.billing,
                  sw: loc.isSwahili,
                  onTap: () => _navigateToScreen(const SubscriptionScreen()),
                ),
                if (user.business!.billing.needsAttention()) const SizedBox(height: 12),
                _sectionLabel(loc.isSwahili ? 'Biashara' : 'Business'),
                const SizedBox(height: 8),
                ThemeConstants.buildGlassCard(
                  child: Column(
                    children: [
                      _buildSettingsTile(
                        Icons.storefront_outlined,
                        user.business!.name,
                        user.isBusinessOwner
                            ? (loc.isSwahili
                                ? 'Jina, TIN, nembo na anwani vinavyoonekana kwenye risiti'
                                : 'Name, TIN, logo and address shown on receipts')
                            : (loc.isSwahili ? 'Angalia taarifa za biashara' : 'View the business details'),
                        () => _navigateToScreen(BusinessProfileScreen(
                          canEdit: user.isBusinessOwner,
                          showInventoryType: user.serviceTypes.contains('inventory'),
                          onChanged: authProvider.refreshUser,
                        )),
                      ),
                      const Divider(color: Colors.white24, height: 1),
                      _buildSettingsTile(
                        Icons.event_available_outlined,
                        loc.isSwahili ? 'Usajili Wangu' : 'My Subscription',
                        loc.isSwahili
                            ? 'Mpango, tarehe ulizoanza na kuisha, na malipo yako'
                            : 'Your plan, when it started and ends, and your payments',
                        () => _navigateToScreen(const SubscriptionScreen()),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ── Personal Settings (all roles) ──────────────────────────
              _sectionLabel(loc.isSwahili ? 'Binafsi' : 'Personal'),
              const SizedBox(height: 8),
              ThemeConstants.buildGlassCard(
                child: Column(
                  children: [
                    _buildSettingsTile(
                      Icons.notifications_outlined,
                      loc.translate('notifications'),
                      loc.translate('notifications_subtitle'),
                      () => _navigateToScreen(const NotificationsScreen()),
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    _buildSettingsTile(
                      Icons.language_outlined,
                      loc.translate('language'),
                      loc.translate('language_subtitle'),
                      () => _navigateToScreen(const LanguageScreen()),
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    _buildSettingsTile(
                      Icons.shield_outlined,
                      loc.translate('security'),
                      loc.translate('security_subtitle'),
                      () => _navigateToScreen(const SecurityScreen()),
                    ),
                  ],
                ),
              ),

              // ── Super Admin Controls ────────────────────────────────────
              if (isSuperAdmin) ...[
                const SizedBox(height: 20),
                _sectionLabel(
                  loc.isSwahili ? 'Udhibiti wa Super Admin' : 'Super Admin Controls',
                  color: const Color(0xFFFFD700),
                  icon: Icons.verified_user_rounded,
                ),
                const SizedBox(height: 8),
                ThemeConstants.buildGlassCard(child: const SuperAdminTiles()),
              ],

              // ── Admin Tools ────────────────────────────────────────────
              if (isAdmin && !isSuperAdmin) ...[
                const SizedBox(height: 20),
                _sectionLabel(
                  loc.isSwahili ? 'Zana za Msimamizi' : 'Admin Tools',
                  color: Colors.blueGrey.shade200,
                  icon: Icons.manage_accounts_rounded,
                ),
                const SizedBox(height: 8),
                ThemeConstants.buildGlassCard(
                  child: Column(
                    children: [
                      _buildSettingsTile(
                        Icons.people_outlined,
                        loc.translate('users'),
                        loc.isSwahili
                            ? 'Dhibiti watumiaji wa huduma yako'
                            : 'Manage users in your assigned service(s)',
                        () => _navigateToScreen(const UserManagementScreen()),
                      ),
                      const Divider(color: Colors.white24, height: 1),
                      _buildSettingsTile(
                        Icons.cloud_upload_outlined,
                        loc.translate('backup'),
                        loc.translate('backup_subtitle'),
                        () => _navigateToScreen(const BackupScreen()),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ── App Information (all roles) ────────────────────────────
              _sectionLabel(loc.isSwahili ? 'Kuhusu' : 'About'),
              const SizedBox(height: 8),
              ThemeConstants.buildGlassCard(
                child: Column(
                  children: [
                    _buildSettingsTile(
                      Icons.info_outline_rounded,
                      loc.translate('about_app'),
                      loc.translate('about_app_subtitle'),
                      _showAboutDialog,
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    _buildSettingsTile(
                      Icons.help_outline_rounded,
                      loc.translate('help'),
                      loc.translate('help_subtitle'),
                      () => _navigateToScreen(const HelpScreen()),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Logout ────────────────────────────────────────────────
              ThemeConstants.buildGlassCard(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: const Icon(Icons.logout_rounded,
                      color: Colors.redAccent, size: 24),
                  title: Text(
                    loc.translate('logout'),
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  onTap: () => _showLogoutDialog(authProvider),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, {Color? color, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color ?? ThemeConstants.textSecondary),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: color ?? ThemeConstants.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    Widget? badge,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(
        icon,
        color: ThemeConstants.textSecondary,
        size: 24,
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: ThemeConstants.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: ThemeConstants.textSecondary,
          fontSize: 13,
        ),
      ),
      trailing: badge == null
          ? const Icon(
              Icons.chevron_right,
              color: ThemeConstants.textSecondary,
              size: 20,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                badge,
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right,
                  color: ThemeConstants.textSecondary,
                  size: 20,
                ),
              ],
            ),
      onTap: onTap,
    );
  }

  void _navigateToScreen(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: ThemeConstants.primaryOrange,
              size: 18.sp,
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                _localizationService.translate('app_name'),
                style: const TextStyle(color: ThemeConstants.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${_localizationService.translate('version')}: 1.0.0",
              style: const TextStyle(color: ThemeConstants.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              _localizationService.translate('app_description'),
              style: const TextStyle(color: ThemeConstants.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              _localizationService.translate('copyright'),
              style: const TextStyle(color: ThemeConstants.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _localizationService.translate('ok'),
              style: const TextStyle(color: ThemeConstants.primaryOrange),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLogoutDialog(AuthProvider authProvider) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(
              Icons.logout,
              color: Colors.redAccent,
              size: 18.sp,
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                _localizationService.translate('confirm'),
                style: const TextStyle(color: ThemeConstants.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          _localizationService.translate('logout_confirm'),
          style: const TextStyle(color: ThemeConstants.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              _localizationService.translate('no'),
              style: const TextStyle(color: ThemeConstants.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _localizationService.translate('yes'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if ((confirm ?? false) && context.mounted) {
      await authProvider.logout();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  }

  ImageProvider? _buildAvatarImage(AuthProvider authProvider) {
    final String? url = authProvider.user?.avatarUrl;
    if (url == null || url.isEmpty) return null;
    final String fullUrl = url.startsWith('http')
        ? url
        : "${ApiConfig.webBaseUrl}${url.startsWith('/') ? '' : '/'}$url";
    return NetworkImage(fullUrl);
  }

  Future<void> _pickAndUploadImage(AuthProvider authProvider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;
      if (!context.mounted) return;
      // ignore: use_build_context_synchronously
      ThemeConstants.showInfoSnackBar(context, '${LocalizationService.instance.translate('uploading_image')}...');
      final ok = await authProvider.uploadProfileImage(
        bytes: file.bytes!,
        filename: file.name,
      );
      if (!context.mounted) return;
      // ignore: use_build_context_synchronously
      if (ok) {
        ThemeConstants.showSuccessSnackBar(context, LocalizationService.instance.translate('image_uploaded'));
      } else {
        ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translate('failed_to_upload_image'));
      }
      if (ok && mounted) setState(() {});
    } on Exception catch (e) {
      if (!context.mounted) return;
      // ignore: use_build_context_synchronously
      ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translateWith('upload_failed', <Object?>[e]));
    }
  }
}
