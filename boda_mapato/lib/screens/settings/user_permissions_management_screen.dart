import 'dart:convert';
import 'package:flutter/material.dart';
import '../../constants/theme_constants.dart';
import '../../models/user_permissions.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import '../../modules/inventory/screens/widgets/joined_sections.dart' show SectionGlowDivider;
import 'user_access_screen.dart';

class UserPermissionsManagementScreen extends StatefulWidget {
  // rental, transport, inventory

  const UserPermissionsManagementScreen({
    required this.user,
    required this.serviceType,
    this.api,
    super.key,
  });
  final Map<String, dynamic> user;
  final String serviceType;

  /// The server calls (a fake in tests).
  final ApiService? api;

  @override
  State<UserPermissionsManagementScreen> createState() =>
      _UserPermissionsManagementScreenState();
}

class _UserPermissionsManagementScreenState
    extends State<UserPermissionsManagementScreen> {
  late final ApiService _api = widget.api ?? ApiService();
  final LocalizationService _loc = LocalizationService.instance;

  late List<String> _currentPermissions;
  bool _saving = false;

  /// Permissions that the user's role already includes by default.
  late List<String> _roleDefaults;

  final Map<String, List<Map<String, String>>> _allPermissionGroups = {
    'inventory': [
      // Products & Stock
      {'id': 'inv_view_products',    'name': LocalizationService.instance.translate('view_products'),    'icon': 'inventory_2'},
      {'id': 'inv_create_products',  'name': LocalizationService.instance.translate('add_new_products'), 'icon': 'add_box'},
      {'id': 'inv_manage_products',  'name': LocalizationService.instance.translate('manage_products'),  'icon': 'edit'},
      {'id': 'inv_manage_stock',     'name': LocalizationService.instance.translate('manage_stock'),     'icon': 'track_changes'},
      {'id': 'inv_report_damage',    'name': LocalizationService.instance.translate('report_damaged_stock'), 'icon': 'report_problem'},
      // Sales
      {'id': 'inv_create_sales',     'name': LocalizationService.instance.translate('create_sales'),     'icon': 'point_of_sale'},
      {'id': 'inv_manage_sales',     'name': LocalizationService.instance.translate('manage_sales'),     'icon': 'manage_accounts'},
      // Financials
      {'id': 'inv_view_credit',      'name': LocalizationService.instance.translate('credit_debt'),    'icon': 'credit_card'},
      {'id': 'inv_view_cash',        'name': LocalizationService.instance.translate('daily_cash'),       'icon': 'payments'},
      {'id': 'inv_view_crates',      'name': LocalizationService.instance.translate('crates_empties'), 'icon': 'inbox'},
      {'id': 'inv_view_expenses',    'name': LocalizationService.instance.translate('view_expenses'),    'icon': 'receipt_long'},
      {'id': 'inv_manage_expenses',  'name': LocalizationService.instance.translate('record_expenses'),  'icon': 'edit_note'},
      // Supply chain
      {'id': 'inv_view_purchasing',  'name': LocalizationService.instance.translate('purchasing'),       'icon': 'local_shipping'},
      // Insights
      {'id': 'inv_view_reports',     'name': LocalizationService.instance.translate('reports'),          'icon': 'bar_chart'},
      // Misc
      {'id': 'inv_view_reminders',   'name': LocalizationService.instance.translate('reminders'),        'icon': 'notifications'},
      {'id': 'inv_manage_settings',  'name': LocalizationService.instance.translate('settings'),         'icon': 'settings'},
    ],
    // The salon runs on the same permission keys as the inventory, with the salon's own words.
    'salon': [
      {'id': 'inv_view_products', 'name': LocalizationService.instance.translate('salon_right_services'),            'icon': 'inventory_2'},
      {'id': 'inv_create_products', 'name': LocalizationService.instance.translate('salon_right_add'),                 'icon': 'add_box'},
      {'id': 'inv_manage_products', 'name': LocalizationService.instance.translate('salon_right_change'), 'icon': 'edit'},
      {'id': 'inv_manage_stock', 'name': LocalizationService.instance.translate('salon_right_stock'), 'icon': 'track_changes'},
      {'id': 'inv_report_damage', 'name': LocalizationService.instance.translate('salon_right_damage'), 'icon': 'report_problem'},
      {'id': 'inv_create_sales', 'name': LocalizationService.instance.translate('salon_right_sales'), 'icon': 'point_of_sale'},
      {'id': 'inv_manage_sales', 'name': LocalizationService.instance.translate('salon_right_returns'), 'icon': 'manage_accounts'},
      {'id': 'inv_view_credit', 'name': LocalizationService.instance.translate('salon_right_credit'),          'icon': 'credit_card'},
      {'id': 'inv_view_cash', 'name': LocalizationService.instance.translate('salon_right_cash'),         'icon': 'payments'},
      {'id': 'inv_view_expenses', 'name': LocalizationService.instance.translate('salon_right_expenses_view'),                  'icon': 'receipt_long'},
      {'id': 'inv_manage_expenses', 'name': LocalizationService.instance.translate('salon_right_expenses_record'),            'icon': 'edit_note'},
      {'id': 'inv_view_purchasing', 'name': LocalizationService.instance.translate('salon_right_purchasing'),                          'icon': 'local_shipping'},
      {'id': 'inv_view_reports', 'name': LocalizationService.instance.translate('salon_right_reports'), 'icon': 'bar_chart'},
      {'id': 'inv_view_reminders', 'name': LocalizationService.instance.translate('salon_right_reminders'),                         'icon': 'notifications'},
      {'id': 'inv_manage_settings', 'name': LocalizationService.instance.translate('salon_right_settings'), 'icon': 'settings'},
    ],
    'rental': [
      {'id': 'manage_properties_rental', 'name': LocalizationService.instance.translate('properties'),  'icon': 'home_work'},
      {'id': 'manage_houses_rental',     'name': LocalizationService.instance.translate('houses'),       'icon': 'house'},
      {'id': 'onboard_tenants_rental',   'name': LocalizationService.instance.translate('onboarding'),  'icon': 'person_add'},
      {'id': 'manage_agreements_rental', 'name': LocalizationService.instance.translate('agreements'),  'icon': 'handshake'},
      {'id': 'manage_billing_rental',    'name': LocalizationService.instance.translate('lipisha'),      'icon': 'receipt'},
      {'id': 'view_reports_rental',      'name': LocalizationService.instance.translate('reports'),      'icon': 'bar_chart'},
      {'id': 'manage_maintenance_rental','name': LocalizationService.instance.translate('maintenance'),  'icon': 'build'},
    ],
    'transport': [
      {'id': 'manage_vehicles_transport',   'name': LocalizationService.instance.translate('vehicles'),   'icon': 'directions_car'},
      {'id': 'manage_drivers_transport',    'name': LocalizationService.instance.translate('drivers'),    'icon': 'person'},
      {'id': 'manage_agreements_transport', 'name': LocalizationService.instance.translate('agreements'), 'icon': 'handshake'},
      {'id': 'manage_payments_transport',   'name': LocalizationService.instance.translate('payments_section'),   'icon': 'payments'},
      {'id': 'manage_debts_transport',      'name': LocalizationService.instance.translate('debts'),      'icon': 'money_off'},
      {'id': 'view_reports_transport',      'name': LocalizationService.instance.translate('reports'),    'icon': 'bar_chart'},
      {'id': 'manage_reminders_transport',  'name': LocalizationService.instance.translate('reminders'),  'icon': 'notifications'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _loadInitialPermissions();
  }

  void _loadInitialPermissions() {
    // Explicit per-user grants stored in DB
    final rawPerms = widget.user['permissions'];
    if (rawPerms is List) {
      _currentPermissions = List<String>.from(rawPerms.map((e) => e.toString()));
    } else if (rawPerms is String && rawPerms.trim().startsWith('[')) {
      try {
        final decoded = jsonDecode(rawPerms);
        _currentPermissions = decoded is List
            ? List<String>.from(decoded.map((e) => e.toString()))
            : [];
      } catch (_) {
        _currentPermissions = [];
      }
    } else {
      _currentPermissions = [];
    }

    // Role default baseline — used for display only (locked green chips)
    final String role = (widget.user['role'] as String?) ?? '';
    _roleDefaults = UserPermissions.fromRole(role).all;
  }

  void _togglePermission(String permId) {
    setState(() {
      if (_currentPermissions.contains(permId)) {
        _currentPermissions.remove(permId);
      } else {
        _currentPermissions.add(permId);
      }
    });
  }

  Future<void> _savePermissions() async {
    setState(() => _saving = true);
    try {
      final res = await _api.updateUserPermissions(
        widget.user['id'].toString(),
        _currentPermissions,
      );

      if (res['success'] == true) {
        if (mounted) {
          ThemeConstants.showSuccessSnackBar(
            context,
            _loc.isSwahili ? 'Mabadiliko yamehifadhiwa' : 'Permissions updated',
          );
          Navigator.pop(context);
        }
      } else {
        throw Exception(res['message'] ?? LocalizationService.instance.translate('failed_to_update'));
      }
    } catch (e) {
      if (mounted) {
        ThemeConstants.showErrorSnackBar(context, LocalizationService.instance.translateWith('error_2', <Object?>[e]));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _serviceName {
    if (widget.serviceType == 'rental') return LocalizationService.instance.translate('rental_service_title');
    if (widget.serviceType == 'transport') return LocalizationService.instance.translate('transport_service_2');
    if (widget.serviceType == 'inventory') return LocalizationService.instance.translate('inventory_service');
    if (widget.serviceType == 'salon') return LocalizationService.instance.translate('salon_service');
    return LocalizationService.instance.translateWith('service', <Object?>[widget.serviceType.toUpperCase()]);
  }

  /// Three-state logic for each permission tile:
  ///  - fromRole  → granted by role, locked (admin can't take it away here)
  ///  - explicit  → extra grant admin gave this specific user
  ///  - denied    → not in role defaults, not explicitly granted
  _PermState _permState(String id) {
    if (_roleDefaults.contains(id)) return _PermState.fromRole;
    if (_currentPermissions.contains(id)) return _PermState.explicit;
    return _PermState.denied;
  }

  /// A shop, depot or salon person has their access as switches the owner turns on and off (see [UserAccessScreen]); rental and
  /// transport keep the list of extra grants.
  bool get _usesSwitches => widget.serviceType == 'inventory' || widget.serviceType == 'salon';

  @override
  Widget build(BuildContext context) {
    if (_usesSwitches) return UserAccessScreen(user: widget.user, api: widget.api);
    final perms = _allPermissionGroups[widget.serviceType] ?? [];
    final String role = (widget.user['role'] as String?) ?? '';

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: AppBar(
        title: Text(
          _loc.isSwahili ? 'Usimamizi wa Ruhusa' : 'Permissions Management',
          style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: ThemeConstants.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_saving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: ThemeConstants.primaryOrange)),
              ),
            )
          else
            TextButton(
              onPressed: _savePermissions,
              child: Text(
                _loc.isSwahili ? 'HIFADHI' : 'SAVE',
                style: const TextStyle(
                    color: ThemeConstants.primaryOrange, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── User header ────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.white.withOpacity(0.08),
                Colors.white.withOpacity(0.02),
              ], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: ThemeConstants.primaryOrange.withOpacity(0.2),
                  child: Text(
                    (widget.user['name'] as String? ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(
                        color: ThemeConstants.primaryOrange,
                        fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.user['name'] ?? LocalizationService.instance.translate('unknown_user'),
                          style: const TextStyle(
                              color: ThemeConstants.textPrimary,
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(children: [
                        _rolePill(role),
                        const SizedBox(width: 6),
                        _pill(widget.serviceType.toUpperCase(),
                            ThemeConstants.primaryOrange),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const SectionGlowDivider(lift: false),

          // ── What is on, what is extra, what is off ─────────────────
          _summary(perms),
          const SectionGlowDivider(lift: false),

          // ── One switch per right ───────────────────────────────────
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: perms.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) => _permRow(perms[index]),
            ),
          ),
        ],
      ),
    );
  }

  static const Color _roleColor = Color(0xFF22C55E);
  static const Color _extraColor = Colors.cyanAccent;
  static const Color _offColor = Color(0xFF94A3B8);

  /// How many rights come from the role, how many were added for this person, how many are off, with the quick actions.
  Widget _summary(final List<Map<String, String>> perms) {
    final int role = perms.where((Map<String, String> p) => _permState(p['id']!) == _PermState.fromRole).length;
    final int extra = perms.where((Map<String, String> p) => _permState(p['id']!) == _PermState.explicit).length;
    final int off = perms.length - role - extra;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          _countPill('perm_count_role', role, _loc.isSwahili ? 'Kutoka wadhifa' : 'From role', _roleColor),
          const SizedBox(width: 8),
          _countPill('perm_count_extra', extra, _loc.isSwahili ? 'Ziada' : 'Extra', _extraColor),
          const SizedBox(width: 8),
          _countPill('perm_count_off', off, _loc.isSwahili ? 'Zimezimwa' : 'Off', _offColor),
        ]),
        const SizedBox(height: 6),
        Row(children: <Widget>[
          TextButton.icon(
            key: const Key('perm_grant_all'),
            onPressed: off == 0 ? null : () => _setAllExtras(perms, true),
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: Text(_loc.isSwahili ? 'Washa zote' : 'Turn all on'),
          ),
          TextButton.icon(
            key: const Key('perm_clear_extras'),
            onPressed: extra == 0 ? null : () => _setAllExtras(perms, false),
            icon: const Icon(Icons.layers_clear_rounded, size: 18),
            label: Text(_loc.isSwahili ? 'Ondoa ziada' : 'Remove extras'),
          ),
        ]),
      ]),
    );
  }

  Widget _countPill(final String key, final int n, final String label, final Color color) => Container(
        key: Key(key),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.45))),
        child: Text('$n  $label', style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );

  /// Turns on (as extra grants) or removes every right that is not given by the role.
  void _setAllExtras(final List<Map<String, String>> perms, final bool on) {
    setState(() {
      for (final Map<String, String> p in perms) {
        final String id = p['id']!;
        if (_roleDefaults.contains(id)) continue;
        if (on) {
          if (!_currentPermissions.contains(id)) _currentPermissions.add(id);
        } else {
          _currentPermissions.remove(id);
        }
      }
    });
  }

  /// One right as a switch. Three looks: green and locked (the role gives it), cyan (added for this person), grey and off.
  Widget _permRow(final Map<String, String> perm) {
    final String id = perm['id']!;
    final _PermState state = _permState(id);
    final bool fromRole = state == _PermState.fromRole;
    final bool on = state != _PermState.denied;
    final Color color = fromRole ? _roleColor : (on ? _extraColor : _offColor);
    final String label = fromRole
        ? (_loc.isSwahili ? 'Kutoka wadhifa (imefungwa)' : 'Given by the role (locked)')
        : on
            ? (_loc.isSwahili ? 'Ziada kwa mtu huyu' : 'Extra for this person')
            : (_loc.isSwahili ? 'Haijaruhusiwa' : 'Not allowed');

    return AnimatedContainer(
      key: Key('perm_$id'),
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: color.withValues(alpha: on ? 0.10 : 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            // the colour of the state, down the left edge
            Container(width: 4, color: color),
            Expanded(
              child: InkWell(
                onTap: fromRole ? null : () => _togglePermission(id),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(children: <Widget>[
                    Icon(_iconFor(perm['icon']), color: color, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        Text(perm['name']!, style: TextStyle(color: on ? ThemeConstants.textPrimary : Colors.white60, fontSize: 13.5, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(label, style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 10.5, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    if (fromRole) Padding(padding: const EdgeInsets.only(right: 2), child: Icon(Icons.lock, size: 15, color: color)),
                    Switch(
                      key: Key('perm_switch_$id'),
                      value: on,
                      onChanged: fromRole ? null : (bool _) => _togglePermission(id),
                      activeThumbColor: color,
                      activeTrackColor: color.withValues(alpha: 0.35),
                      inactiveThumbColor: _offColor,
                      inactiveTrackColor: Colors.white10,
                    ),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// The rights carry the name of a Material icon; this finds it.
  IconData _iconFor(final String? name) => switch (name) {
        'inventory_2' => Icons.inventory_2_rounded,
        'add_box' => Icons.add_box_rounded,
        'edit' => Icons.edit_rounded,
        'track_changes' => Icons.track_changes_rounded,
        'report_problem' => Icons.report_problem_rounded,
        'point_of_sale' => Icons.point_of_sale_rounded,
        'manage_accounts' => Icons.manage_accounts_rounded,
        'credit_card' => Icons.credit_card_rounded,
        'payments' => Icons.payments_rounded,
        'inbox' => Icons.inbox_rounded,
        'receipt_long' => Icons.receipt_long_rounded,
        'edit_note' => Icons.edit_note_rounded,
        'local_shipping' => Icons.local_shipping_rounded,
        'bar_chart' => Icons.bar_chart_rounded,
        'notifications' => Icons.notifications_rounded,
        'settings' => Icons.settings_rounded,
        'home_work' => Icons.home_work_rounded,
        'house' => Icons.house_rounded,
        'person_add' => Icons.person_add_rounded,
        'handshake' => Icons.handshake_rounded,
        'receipt' => Icons.receipt_rounded,
        'build' => Icons.build_rounded,
        'directions_car' => Icons.directions_car_rounded,
        'person' => Icons.person_rounded,
        'money_off' => Icons.money_off_rounded,
        _ => Icons.tune_rounded,
      };

  Widget _rolePill(String role) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: ThemeConstants.primaryCyan.withOpacity(0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: ThemeConstants.primaryCyan.withOpacity(0.4)),
    ),
    child: Text(role.toUpperCase(),
        style: const TextStyle(color: ThemeConstants.primaryCyan, fontSize: 10,
            fontWeight: FontWeight.bold)),
  );

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Text(label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
  );
}

enum _PermState { fromRole, explicit, denied }
