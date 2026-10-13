import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../services/localization_service.dart';
import '../../../../screens/settings/backup_screen.dart';
import '../../../../screens/settings/language_screen.dart';
import '../../../../screens/settings/notifications_screen.dart';
import '../../../../screens/settings/permissions_management_screen.dart';
import '../../../../screens/settings/security_screen.dart';
import '../../../../screens/settings/user_management_screen.dart';
import '../../models/inv_depot_models.dart';
import '../../providers/depot_provider.dart';
import '../widgets/inventory_widgets.dart';
import 'business_kind_card.dart';
import 'crate_deposit_card.dart';
import 'receipt_header_screen.dart';

/// Area 13 — depot settings and the permanent audit trail.
class DepotSettingsScreen extends StatefulWidget {
  const DepotSettingsScreen({super.key});

  @override
  State<DepotSettingsScreen> createState() => _DepotSettingsScreenState();
}

class _DepotSettingsScreenState extends State<DepotSettingsScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Draw whatever is already cached; only show a spinner on a cold start.
    _loading = context.read<DepotProvider>().settings.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final DepotProvider depot = context.read<DepotProvider>();
    await Future.wait<void>(<Future<void>>[
      depot.fetchSettings(),
      depot.fetchAuditLog(),
    ]);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();

    if (_loading) {
      return const Scaffold(
        backgroundColor: ThemeConstants.primaryBlue,
        body: Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
    }

    return InvTabScaffold(
      title: '',
      tabs: <String>[
        loc.translate('settings'),
        loc.isSwahili ? 'Ulinzi' : 'Security',
        loc.translate('audit_trail'),
      ],
      views: <Widget>[
        _SettingsTab(onSaved: _load),
        const _AppSettingsTab(),
        _AuditTab(onRefresh: _load),
      ],
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.onSaved});

  final Future<void> Function() onSaved;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  bool _saving = false;

  /// Grouped so the form reads like the settings it configures, and each
  /// field knows whether it is text or a number.
  static final Map<String, List<_Field>> _groups = <String, List<_Field>>{
    'depot_details': <_Field>[
      const _Field('depot_name', 'depot_name',
          hint: 'e.g. Beverage Depot Dodoma'),
      const _Field('depot_phone', 'phone', hint: 'e.g. +255 700 000 000', phone: true),
      const _Field('depot_address', 'address',
          hint: 'e.g. Main Street, Block B'),
    ],
    'invoicing': <_Field>[
      const _Field('invoice_prefix', 'invoice_prefix', hint: 'e.g. INV'),
      const _Field('invoice_next_number', 'next_invoice_number',
          hint: 'e.g. 1', numeric: true),
      const _Field('tax_percent', 'tax_percent',
          hint: 'e.g. 18.0', numeric: true),
    ],
    'limits_and_thresholds': <_Field>[
      const _Field('max_discount_percent', 'max_discount_percent',
          hint: 'e.g. 10.0', numeric: true),
      const _Field('large_discount_percent', 'large_discount_percent',
          hint: 'e.g. 15.0', numeric: true),
      const _Field('low_stock_threshold', 'low_stock_threshold',
          hint: 'e.g. 5', numeric: true),
      const _Field('expiry_alert_days', 'expiry_alert_days',
          hint: 'e.g. 30', numeric: true),
      const _Field('overdue_alert_days', 'overdue_alert_days',
          hint: 'e.g. 7', numeric: true),
    ],
  };

  @override
  void initState() {
    super.initState();
    final Map<String, String> settings = context.read<DepotProvider>().settings;
    for (final List<_Field> group in _groups.values) {
      for (final _Field f in group) {
        _controllers[f.key] =
            TextEditingController(text: settings[f.key] ?? '');
      }
    }
    // The crate deposit card needs the current crate types.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DepotProvider>().fetchCrateTypes();
    });
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    final bool ok = await context.read<DepotProvider>().saveSettings(
          _controllers.map((String k, TextEditingController v) =>
              MapEntry<String, String>(k, v.text.trim())),
        );

    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    ThemeConstants.showInfoSnackBar(
      context,
      LocalizationService.instance.translate(ok ? 'saved' : 'operation_failed'),
    );
    if (ok) {
      await widget.onSaved();
    }
  }

  String? _validateField(_Field f, String? value) {
    final v = value?.trim() ?? '';
    if (f.key == 'depot_name' && v.isEmpty) {
      return 'Depot name is required';
    }
    if (f.numeric && v.isNotEmpty) {
      final n = double.tryParse(v);
      if (n == null || n < 0) {
        return 'Enter a valid non-negative number';
      }
      if (f.key.contains('percent') && n > 100) {
        return 'Percentage cannot exceed 100%';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final bool canManageSettings = context.select<AuthProvider, bool>(
        (AuthProvider a) => a.permissions.has('inv_manage_settings'));

    return Form(
      key: _formKey,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
        children: <Widget>[
          // What kind of business this is: the first thing an owner looks for here, because it decides how the
          // product page and the till behave.
          Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: Consumer2<DepotProvider, AuthProvider>(
              builder: (BuildContext _, DepotProvider depot, AuthProvider auth, Widget? __) => BusinessKindCard(
                // A server that has never heard of kinds does not send one with the settings.
                serverKnowsKinds: depot.settings.containsKey('inventory_type'),
                current: depot.capabilities.inventoryType,
                canChange: auth.user?.isBusinessOwner ?? false,
                onChange: depot.changeBusinessKind,
                sw: loc.isSwahili,
              ),
            ),
          ),
          ..._groups.entries.map(
            (MapEntry<String, List<_Field>> group) => Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: Container(
                decoration: ThemeConstants.glassCardDecoration,
                padding: EdgeInsets.all(12.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AutoSizeText(
                      loc.translate(group.key),
                      maxLines: 1,
                      minFontSize: 11,
                      overflow: TextOverflow.ellipsis,
                      style: ThemeConstants.bodyStyle
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 10.h),
                    ...group.value.map(
                      (_Field f) => Padding(
                        padding: EdgeInsets.only(bottom: 10.h),
                        child: InvTextField(
                          controller: _controllers[f.key]!,
                          label: loc.translate(f.labelKey),
                          hint: f.hint,
                          validator: (v) => _validateField(f, v),
                          keyboardType: f.numeric
                              ? const TextInputType.numberWithOptions(decimal: true)
                              : f.phone
                                  ? TextInputType.phone
                                  : TextInputType.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // -- Security deposit charged per crate (one row per crate type) --
          // Only for a business that uses returnable packaging.
          if (canManageSettings && context.watch<DepotProvider>().capabilities.useCrates)
            Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: Consumer<DepotProvider>(
                builder: (BuildContext _, DepotProvider depot, Widget? __) =>
                    CrateDepositCard(
                  swahili: loc.isSwahili,
                  types: depot.crateTypes,
                  onCreate: (String name, double deposit) =>
                      depot.createCrateType(name: name, deposit: deposit),
                  onUpdate: (InvCrateType t, String name, double deposit,
                          bool active) =>
                      depot.updateCrateType(t.id,
                          name: name, deposit: deposit, active: active),
                  onDelete: (InvCrateType t) => depot.deleteCrateType(t.id),
                ),
              ),
            ),
          // -- Quick-link to user management (admin / super_admin only) --
          // Lets an admin create staff for their own bound service, and a
          // super_admin manage every account across every service.
          Builder(
            builder: (context) {
              final user = context.watch<AuthProvider>().user;
              if (user?.isAdmin != true && user?.isSuperAdmin != true) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const UserManagementScreen(),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(14.r),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(14.r),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: ThemeConstants.primaryBlue.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Icon(Icons.people_alt_rounded, color: Colors.white, size: 20.sp),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                loc.translate('users_management'),
                                style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                loc.translate('users_subtitle'),
                                style: ThemeConstants.captionStyle,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14.sp),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // -- Quick-link to receipt header settings (admin / manager only) --
          Builder(
            builder: (context) {
              final role = context.watch<AuthProvider>().user?.role ?? '';
              if (role != 'admin' && role != 'manager') return const SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: InkWell(
                  onTap: () => Navigator.of(context).push(ReceiptHeaderScreen.route()),
                  borderRadius: BorderRadius.circular(14.r),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(14.r),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: ThemeConstants.primaryBlue.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Icon(Icons.receipt_long_rounded, color: Colors.white, size: 20.sp),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mpangilio wa Risiti',
                                style: ThemeConstants.bodyStyle.copyWith(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                'Jina, anwani, TIN, ujumbe wa chini na zaidi',
                                style: ThemeConstants.captionStyle,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14.sp),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          InvPrimaryButton(busy: _saving, onPressed: _save),
        ],
      ),
    );
  }
}

/// "Ulinzi" tab — renders the full app settings page (same design as
/// SettingsScreen) embedded inside the depot settings tab scaffold.
class _AppSettingsTab extends StatelessWidget {
  const _AppSettingsTab();

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final isSuperAdmin = user?.isSuperAdmin ?? false;
    final isAdmin = user?.isAdmin ?? false;

    void go(Widget screen) => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => screen),
        );

    Widget tile(IconData icon, String title, String subtitle, VoidCallback onTap) =>
        Material(
          color: Colors.transparent,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Icon(icon, color: ThemeConstants.textSecondary, size: 24),
            title: Text(title,
                style: const TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
            subtitle: Text(subtitle,
                style: const TextStyle(
                    color: ThemeConstants.textSecondary, fontSize: 13)),
            trailing: const Icon(Icons.chevron_right,
                color: ThemeConstants.textSecondary, size: 20),
            onTap: onTap,
          ),
        );

    const d = Divider(color: Colors.white24, height: 1);

    // All settings tiles in ONE card — exactly like the main settings page.
    final allTiles = <Widget>[
      tile(Icons.notifications, loc.translate('notifications'),
          loc.translate('notifications_subtitle'),
          () => go(const NotificationsScreen())),
      d,
      tile(Icons.language, loc.translate('language'),
          loc.translate('language_subtitle'),
          () => go(const LanguageScreen())),
      d,
      tile(Icons.security, loc.translate('security'),
          loc.translate('security_subtitle'),
          () => go(const SecurityScreen())),
      if (isAdmin || isSuperAdmin) ...[
        d,
        tile(Icons.people, loc.translate('users'),
            isSuperAdmin
                ? (loc.isSwahili
                    ? 'Dhibiti watumiaji wote kwenye huduma zote'
                    : 'Manage all users across every service')
                : loc.translate('users_subtitle'),
            () => go(const UserManagementScreen())),
        if (isSuperAdmin) ...[
          d,
          tile(Icons.admin_panel_settings, 'Permissions',
              'Manage service module permissions',
              () => go(const PermissionsScreen())),
        ],
        d,
        tile(Icons.backup, loc.translate('backup'),
            loc.translate('backup_subtitle'),
            () => go(const BackupScreen())),
      ],
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // -- Profile Card — matches main settings exactly ---------------
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
                            ? const Color(0xFFB8860B)
                            : ThemeConstants.primaryOrange,
                        backgroundImage: _avatarImage(auth),
                        child: _avatarImage(auth) == null
                            ? (user?.name.isNotEmpty == true
                                ? Text(
                                    user!.name.substring(0, 1).toUpperCase(),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold),
                                  )
                                : const Icon(Icons.person,
                                    color: Colors.white, size: 40))
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
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
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(user?.name ?? '',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: ThemeConstants.textPrimary)),
                  Text(user?.email ?? '',
                      style: const TextStyle(
                          fontSize: 14,
                          color: ThemeConstants.textSecondary)),
                  const SizedBox(height: 10),
                  // Role badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSuperAdmin
                          ? const Color(0xFFB8860B).withOpacity(0.22)
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
                          isSuperAdmin
                              ? 'SUPER ADMIN'
                              : isAdmin
                                  ? 'ADMIN'
                                  : (user?.role?.toUpperCase() ?? ''),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: isSuperAdmin
                                ? const Color(0xFFFFD700)
                                : Colors.blueGrey.shade200,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Admin: assigned service chips
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

          const SizedBox(height: 20),

          // -- All settings tiles in one card ----------------------------
          ThemeConstants.buildGlassCard(
            child: Column(children: allTiles),
          ),

          const SizedBox(height: 20),

          // -- About card ------------------------------------------------
          ThemeConstants.buildGlassCard(
            child: Column(
              children: [
                tile(Icons.info, loc.translate('about_app'),
                    loc.translate('about_app_subtitle'), () {}),
                d,
                tile(Icons.help, loc.translate('help'),
                    loc.translate('help_subtitle'), () {}),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  ImageProvider? _avatarImage(AuthProvider auth) {
    final url = auth.user?.avatarUrl;
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return NetworkImage(url);
    return null;
  }
}

class _Field {
  const _Field(this.key, this.labelKey, {this.hint, this.numeric = false, this.phone = false});

  final String key;
  final String labelKey;
  final String? hint;
  final bool numeric;
  final bool phone;
}

class _AuditTab extends StatelessWidget {
  const _AuditTab({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final LocalizationService loc = context.watch<LocalizationService>();
    final List<InvAuditEntry> rows = context.watch<DepotProvider>().auditLog;

    return RefreshIndicator(
      onRefresh: onRefresh,
      backgroundColor: Colors.white,
      color: ThemeConstants.primaryBlue,
      child: rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: <Widget>[
                SizedBox(height: 60.h),
                InvEmptyState(
                  icon: Icons.history_outlined,
                  message: loc.translate('no_audit_entries'),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 24.h),
              itemCount: rows.length,
              separatorBuilder: (_, __) => SizedBox(height: 6.h),
              itemBuilder: (_, int i) {
                final InvAuditEntry e = rows[i];
                final DateTime at = e.createdAt;

                return Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            AutoSizeText(
                              '${e.entityType.replaceAll('_', ' ')} · ${e.action}',
                              maxLines: 1,
                              minFontSize: 10,
                              overflow: TextOverflow.ellipsis,
                              style: ThemeConstants.bodyStyle
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                            SizedBox(height: 2.h),
                            AutoSizeText(
                              <String>[
                                '${at.day}/${at.month}/${at.year} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                                if (e.userName.isNotEmpty) e.userName,
                                if (e.summary.isNotEmpty) e.summary,
                              ].join('  •  '),
                              maxLines: 2,
                              minFontSize: 9,
                              overflow: TextOverflow.ellipsis,
                              style: ThemeConstants.captionStyle,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
