import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/theme_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import 'user_permissions_management_screen.dart';
import '../../utils/server_message.dart';

// ignore_for_file: use_string_buffers, use_if_null_to_convert_nulls_to_bools, avoid_catches_without_on_clauses, control_flow_in_finally
class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final LocalizationService _loc = LocalizationService.instance;
  final ApiService _api = ApiService();

  bool _loading = true;
  bool _creating = false;
  List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];
  String _activeService = 'transport'; // default

  // Super admin only: view all users grouped by service, then by the admin
  // managing them within that service.
  bool _groupedView = false;
  bool _loadingGrouped = false;
  Map<String, dynamic>? _groupedData;

  @override
  void initState() {
    super.initState();
    _api.initialize();
    _detectActiveService();
  }

  Future<void> _detectActiveService() async {
    final prefs = await SharedPreferences.getInstance();
    final service = prefs.getString('selected_service') ?? 'transport';
    if (mounted) {
      setState(() => _activeService = service);
      _loadMyUsers();
    }
  }

  bool get _isRental => _activeService == 'rental';
  bool get _isSalon => _activeService == 'salon';
  // Salon runs on the same sales engine, so its staff are given the same kinds of roles and permissions.
  bool get _isInventory => _activeService == 'inventory' || _activeService == 'salon';

  /// Owner roles (admin / landlord) are separate businesses: they register
  /// themselves or a super admin creates them. A business owner creates STAFF,
  /// so the server refuses these roles for anyone but a super admin.
  bool get _isSuperAdminUser =>
      Provider.of<AuthProvider>(context, listen: false).user?.isSuperAdmin == true;

  static const List<String> _allServices = <String>['inventory', 'transport', 'rental', 'salon'];

  /// The services the signed-in user may give to someone else. A super admin can give any;
  /// a business owner only the ones a super admin gave them (the server refuses the rest
  /// with a 403, so offering them would only lead to an error).
  List<String> get _assignableServices {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user?.isSuperAdmin == true) return _allServices;
    final List<String> own = user?.serviceTypes ?? const <String>[];
    return _allServices.where(own.contains).toList();
  }

  /// The roles a salon gives its people (the server and the app both know what each may do).
  static const List<String> _salonRoles = <String>['receptionist', 'cashier', 'hair_stylist', 'nail_technician', 'lash_makeup_artist', 'accountant', 'stock_manager'];

  List<DropdownMenuItem<String>> get _roleDropdownItems => _allRoleDropdownItems
      .where((DropdownMenuItem<String> item) =>
          _isSuperAdminUser || (item.value != 'admin' && item.value != 'landlord'))
      .toList();

  List<DropdownMenuItem<String>> get _allRoleDropdownItems {
    if (_isRental) {
      return [
        DropdownMenuItem(value: 'admin', child: Text(LocalizationService.instance.translate('admin'))),
        DropdownMenuItem(value: 'landlord', child: Text(LocalizationService.instance.translate('landlord'))),
        DropdownMenuItem(value: 'caretaker', child: Text(LocalizationService.instance.translate('caretaker'))),
        DropdownMenuItem(value: 'tenant', child: Text(LocalizationService.instance.translate('tenant'))),
        DropdownMenuItem(value: 'viewer', child: Text(LocalizationService.instance.translate('viewer'))),
      ];
    }
    if (_isSalon) {
      return [
        DropdownMenuItem(value: 'admin', child: Text(LocalizationService.instance.translate('admin'))),
        DropdownMenuItem(value: 'manager', child: Text(LocalizationService.instance.translate('manager'))),
        for (final String r in _salonRoles) DropdownMenuItem(value: r, child: Text(LocalizationService.instance.translate(r))),
        DropdownMenuItem(value: 'viewer', child: Text(LocalizationService.instance.translate('viewer'))),
      ];
    }
    if (_isInventory) {
      return [
        DropdownMenuItem(value: 'admin', child: Text(LocalizationService.instance.translate('admin'))),
        DropdownMenuItem(value: 'manager', child: Text(LocalizationService.instance.translate('manager'))),
        DropdownMenuItem(value: 'sales_officer', child: Text(LocalizationService.instance.translate('sales_officer'))),
        DropdownMenuItem(value: 'operator', child: Text(LocalizationService.instance.translate('operator'))),
        DropdownMenuItem(value: 'viewer', child: Text(LocalizationService.instance.translate('viewer'))),
      ];
    }
    return [
      DropdownMenuItem(value: 'admin', child: Text(LocalizationService.instance.translate('admin'))),
      DropdownMenuItem(value: 'manager', child: Text(LocalizationService.instance.translate('manager'))),
      DropdownMenuItem(value: 'operator', child: Text(LocalizationService.instance.translate('operator'))),
      DropdownMenuItem(value: 'viewer', child: Text(LocalizationService.instance.translate('viewer'))),
      DropdownMenuItem(value: 'driver', child: Text(LocalizationService.instance.translate('driver'))),
    ];
  }

  String get _defaultRole =>
      _isRental ? 'tenant' : (_isSuperAdminUser ? 'admin' : 'manager');

  String _serviceLabel(String service) {
    switch (service) {
      case 'inventory':
        return _loc.translate('inventory_service');
      case 'transport':
        return _loc.translate('transport_service');
      case 'rental':
        return _loc.translate('rental_service');
      case 'salon':
        return _loc.translate('salon_service');
      default:
        return service;
    }
  }

  Future<void> _loadMyUsers() async {
    setState(() => _loading = true);
    try {
      final isSuperAdmin = Provider.of<AuthProvider>(context, listen: false).user?.isSuperAdmin == true;
      // super_admin sees ALL users across all services (no service filter)
      // so they can manage admins who may not yet have any service bound.
      final Map<String, dynamic> res = isSuperAdmin
          ? await _api.getUsers(limit: 200)
          : await _api.getMyUsers(limit: 100, serviceType: _activeService);
      final List<Map<String, dynamic>> items = _extractUsers(res);
      setState(() {
        _users = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _loadGrouped() async {
    setState(() => _loadingGrouped = true);
    try {
      final Map<String, dynamic> res = await _api.getUsersByService();
      final dynamic data = res['data'];
      if (!mounted) return;
      setState(() {
        _groupedData = data is Map ? Map<String, dynamic>.from(data) : null;
        _loadingGrouped = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingGrouped = false);
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  List<Map<String, dynamic>> _extractUsers(Map<String, dynamic> resp) {
    final dynamic data = resp['data'];
    List<dynamic> raw;
    if (data is Map && data['users'] is List) {
      raw = data['users'] as List;
    } else if (resp['users'] is List) {
      raw = resp['users'] as List;
    } else if (data is List) {
      raw = data;
    } else {
      raw = const <dynamic>[];
    }
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  String _defaultPasswordFromName(String fullName) {
    final String trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'PASSWORD8';
    final List<String> parts =
        trimmed.split(RegExp(r"\s+")).where((p) => p.isNotEmpty).toList();
    final String base = (parts.isNotEmpty ? parts.last : trimmed).toUpperCase();
    // Ensure password has exactly 8 characters
    String pwd = base;
    while (pwd.length < 8) {
      pwd += base;
    }
    return pwd.substring(0, 8);
  }

  Future<void> _openCreateDialog() async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController name = TextEditingController();
    final TextEditingController email = TextEditingController();
    final TextEditingController phone = TextEditingController();
    String role = _defaultRole;
    bool isActive = true;
    bool fullAccess = false;
    // Which services this new account is bound to. Defaults to the one
    // the admin is currently managing, but a user can be bound to more
    // than one (e.g. transport + inventory).
    final List<String> assignable = _assignableServices;
    final Set<String> selectedServices = <String>{
      if (assignable.contains(_activeService))
        _activeService
      else if (assignable.isNotEmpty)
        assignable.first,
    };

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _loc.translate('create_user'),
                style: const TextStyle(
                    color: ThemeConstants.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: StatefulBuilder(
                  builder: (context, setDialogState) {
                    return Form(
                      key: formKey,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextFormField(
                              controller: name,
                              style: const TextStyle(color: ThemeConstants.textPrimary),
                              decoration: InputDecoration(
                                labelText: _loc.translate('full_name'),
                                labelStyle:
                                    const TextStyle(color: ThemeConstants.textSecondary),
                                prefixIcon: const Icon(Icons.person,
                                    color: ThemeConstants.textSecondary),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.1),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: Colors.white.withOpacity(0.3)),
                                ),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? (_loc.isSwahili
                                      ? 'Ingiza jina kamili'
                                      : 'Enter full name')
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(color: ThemeConstants.textPrimary),
                              decoration: InputDecoration(
                                labelText: _loc.translate('email'),
                                labelStyle:
                                    const TextStyle(color: ThemeConstants.textSecondary),
                                prefixIcon: const Icon(Icons.email,
                                    color: ThemeConstants.textSecondary),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.1),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: Colors.white.withOpacity(0.3)),
                                ),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? (_loc.isSwahili ? 'Ingiza barua pepe' : 'Enter email')
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: phone,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(color: ThemeConstants.textPrimary),
                              decoration: InputDecoration(
                                labelText: _loc.translate('phone_number'),
                                labelStyle:
                                    const TextStyle(color: ThemeConstants.textSecondary),
                                prefixIcon: const Icon(Icons.phone,
                                    color: ThemeConstants.textSecondary),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.1),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: Colors.white.withOpacity(0.3)),
                                ),
                              ),
                              // Login checks the phone number, so an account
                              // without one could never sign in.
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? (_loc.isSwahili ? 'Ingiza namba ya simu' : 'Enter phone number')
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: role,
                              dropdownColor: ThemeConstants.primaryBlue,
                              style: const TextStyle(color: ThemeConstants.textPrimary),
                              decoration: InputDecoration(
                                labelText: _loc.translate('role'),
                                labelStyle:
                                    const TextStyle(color: ThemeConstants.textSecondary),
                                prefixIcon: const Icon(Icons.verified_user,
                                    color: ThemeConstants.textSecondary),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.1),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide:
                                      BorderSide(color: Colors.white.withOpacity(0.3)),
                                ),
                              ),
                              items: _roleDropdownItems,
                              onChanged: (v) => setDialogState(() => role = v ?? _defaultRole),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _loc.isSwahili ? 'Huduma' : 'Services',
                                style: const TextStyle(
                                    color: ThemeConstants.textSecondary, fontSize: 12),
                              ),
                            ),
                            Wrap(
                              spacing: 4,
                              children: assignable
                                  .map((String s) => FilterChip(
                                        label: Text(_serviceLabel(s)),
                                        selected: selectedServices.contains(s),
                                        onSelected: (bool sel) => setDialogState(() {
                                          sel
                                              ? selectedServices.add(s)
                                              : selectedServices.remove(s);
                                        }),
                                        labelStyle: TextStyle(
                                          color: selectedServices.contains(s)
                                              ? Colors.black
                                              : ThemeConstants.textPrimary,
                                        ),
                                        selectedColor: ThemeConstants.primaryOrange,
                                        backgroundColor: Colors.white.withOpacity(0.1),
                                      ))
                                  .toList(),
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile.adaptive(
                              value: isActive,
                              onChanged: (v) => setDialogState(() => isActive = v ?? true),
                              title: Text(
                                _loc.translate('active'),
                                style: const TextStyle(color: ThemeConstants.textPrimary),
                              ),
                              activeColor: ThemeConstants.primaryOrange,
                            ),
                            SwitchListTile.adaptive(
                              value: fullAccess,
                              onChanged: (v) => setDialogState(() => fullAccess = v ?? false),
                              title: Text(
                                _loc.isSwahili ? 'Ufikiaji Kamili' : 'Full Access',
                                style: const TextStyle(color: ThemeConstants.textPrimary),
                              ),
                              activeColor: ThemeConstants.primaryOrange,
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _loc.translate('default_password_note'),
                                style: const TextStyle(
                                    color: ThemeConstants.textSecondary, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(_loc.translate('cancel'),
                        style: const TextStyle(color: ThemeConstants.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _creating
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;

                            // Check if email already exists in current users list
                            final String emailToCheck = email.text.trim().toLowerCase();
                            final bool emailExists = _users.any((u) =>
                                (u['email']?.toString().toLowerCase() ?? '') ==
                                emailToCheck);

                            if (emailExists) {
                              ThemeConstants.showErrorSnackBar(
                                  context,
                                  _loc.isSwahili
                                      ? 'Barua pepe tayari ipo'
                                      : 'Email already exists');
                              return;
                            }

                            setState(() => _creating = true);
                            try {
                              final String password =
                                  _defaultPasswordFromName(name.text);
                              final Map<String, dynamic> payload = <String, dynamic>{
                                'name': name.text.trim(),
                                'email': email.text.trim(),
                                'phone_number': phone.text.trim().isEmpty
                                    ? null
                                    : phone.text.trim(),
                                'role': role,
                                'is_active': isActive,
                                'password': password,
                                'password_confirmation': password,
                                'service_types': selectedServices.toList(),
                                'full_access': fullAccess,
                              }..removeWhere((key, value) => value == null);
                              // Use admin users endpoint. The payload carries the
                              // initial password, so it is never logged.
                              final Map<String, dynamic> res =
                                  await _api.createUser(payload);
                              if ((res['success'] == true) || res.containsKey('data')) {
                                if (!mounted) return;
                                // ignore: use_build_context_synchronously
                                ThemeConstants.showSuccessSnackBar(context,
                                    _loc.translate('user_created_successfully'));
                                // ignore: use_build_context_synchronously
                                Navigator.pop(ctx, true);
                              } else {
                                throw Exception(
                                    res['message'] ?? LocalizationService.instance.translate('failed_to_create_user'));
                              }
                            } catch (e) {
                              if (mounted) {
                                String errorMsg = readableErrorMessage(e);
                                // Extract specific validation error from API response
                                if (errorMsg.contains('email has already been taken')) {
                                  errorMsg = _loc.isSwahili
                                      ? 'Barua pepe tayari inatumika. Tumia barua pepe nyingine.'
                                      : 'Email already exists. Please use a different email.';
                                } else if (errorMsg.contains('validation')) {
                                  errorMsg = _loc.isSwahili
                                      ? 'Taarifa za mtumiaji si sahihi. Angalia na ujaribu tena.'
                                      : 'User information is invalid. Please check and try again.';
                                }
                                // ignore: use_build_context_synchronously
                                ThemeConstants.showErrorSnackBar(context, errorMsg);
                              }
                            } finally {
                              if (!mounted) return;
                              setState(() => _creating = false);
                              await _loadMyUsers();
                            }
                          },
                    style: FilledButton.styleFrom(
                        backgroundColor: ThemeConstants.primaryOrange,
                        foregroundColor: Colors.white),
                    child: _creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(_loc.translate('create_user')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUserActions(Map<String, dynamic> user) {
    final bool active = user['is_active'] == true || user['is_active'] == 1;
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final bool isSuperAdmin = authUser?.isSuperAdmin == true;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.lock_reset, color: Colors.white70),
                title: Text(
                  _loc.translate('reset_password'),
                  style: const TextStyle(color: ThemeConstants.textPrimary),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _resetUserPassword(user);
                },
              ),
              const Divider(height: 1, color: Colors.white24),
              ListTile(
                leading: Icon(active ? Icons.block : Icons.check_circle,
                    color: Colors.white70),
                title: Text(
                  active
                      ? (_loc.isSwahili ? 'Lemaza mtumiaji' : 'Deactivate user')
                      : (_loc.isSwahili ? 'Wezesha mtumiaji' : 'Activate user'),
                  style: const TextStyle(color: ThemeConstants.textPrimary),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _setUserActive(user, !active);
                },
              ),
              const Divider(height: 1, color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.manage_accounts, color: ThemeConstants.primaryOrange),
                title: Text(
                  LocalizationService.instance.translate('change_role'),
                  style: TextStyle(color: ThemeConstants.primaryOrange),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _changeUserRole(user);
                },
              ),
              // Service bindings: super_admin can edit anyone's; admin can edit their own created users
              const Divider(height: 1, color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.apps_rounded, color: Colors.lightBlueAccent),
                title: Text(
                  _loc.isSwahili ? 'Badilisha Huduma' : 'Edit Service Access',
                  style: const TextStyle(color: Colors.lightBlueAccent),
                ),
                subtitle: isSuperAdmin
                    ? Text(
                        _loc.isSwahili
                            ? 'Super Admin: weka huduma zozote'
                            : 'Super Admin: assign any services',
                        style: const TextStyle(color: ThemeConstants.textSecondary, fontSize: 11),
                      )
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  await _editServiceBindings(user);
                },
              ),
              const Divider(height: 1, color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.security, color: Colors.green),
                title: Text(
                  _loc.isSwahili ? 'Weka/Ondoa Ruhusa' : 'Assign/Remove Permissions',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserPermissionsManagementScreen(
                        user: user,
                        serviceType: _activeService,
                      ),
                    ),
                  ).then((_) => _loadMyUsers());
                },
              ),
              const Divider(height: 1, color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title: Text(
                  _loc.isSwahili ? 'Futa mtumiaji' : 'Delete user',
                  style: const TextStyle(color: Colors.redAccent),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _deleteUser(user);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editServiceBindings(Map<String, dynamic> user) async {
    // Parse the current bound services from the user map
    final List<dynamic> raw = (user['service_types'] as List?) ?? [];
    final Set<String> selected = raw.map((e) => e.toString()).toSet();
    // If none bound yet, default to showing all unselected
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final bool isSuperAdmin = authUser?.isSuperAdmin == true;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: ThemeConstants.primaryBlue,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loc.isSwahili ? 'Huduma za ${user['name']}' : '${user['name']}\'s Services',
                style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (isSuperAdmin)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade800.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.shade600, width: 1),
                  ),
                  child: Text(
                    _loc.isSwahili ? '🔑 Mamlaka ya Super Admin' : '🔑 Super Admin Authority',
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                  ),
                ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _loc.isSwahili
                    ? 'Chagua huduma ambazo mtumiaji huyu atapata ufikiaji:'
                    : 'Select which services this user can access:',
                style: const TextStyle(color: ThemeConstants.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              ..._assignableServices.map((s) {
                final bool on = selected.contains(s);
                return CheckboxListTile(
                  value: on,
                  onChanged: (v) => setDialogState(() {
                    v == true ? selected.add(s) : selected.remove(s);
                  }),
                  title: Row(
                    children: [
                      Icon(
                        s == 'inventory'
                            ? Icons.inventory_2_rounded
                            : s == 'transport'
                                ? Icons.local_shipping_rounded
                                : s == 'salon'
                                    ? Icons.content_cut_rounded
                                    : Icons.apartment_rounded,
                        color: on ? ThemeConstants.primaryOrange : Colors.white54,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _serviceLabel(s),
                        style: TextStyle(
                          color: on ? ThemeConstants.textPrimary : Colors.white54,
                          fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  activeColor: ThemeConstants.primaryOrange,
                  checkColor: Colors.white,
                  controlAffinity: ListTileControlAffinity.trailing,
                  contentPadding: EdgeInsets.zero,
                );
              }),
              if (selected.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _loc.isSwahili
                        ? '⚠️ Mtumiaji hataona huduma yoyote'
                        : '⚠️ User will see no services on login',
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_loc.translate('cancel'),
                  style: const TextStyle(color: ThemeConstants.textSecondary)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: ThemeConstants.primaryOrange),
              child: Text(_loc.isSwahili ? 'Hifadhi' : 'Save',
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    try {
      final String id = (user['id'] ?? user['user_id'] ?? '').toString();
      await _api.updateUser(id, <String, dynamic>{
        'service_types': selected.toList(),
      });
      await _loadMyUsers();
      if (mounted) {
        ThemeConstants.showSuccessSnackBar(
          context,
          _loc.isSwahili ? 'Huduma zimesasishwa' : 'Service access updated',
        );
      }
    } catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _changeUserRole(Map<String, dynamic> user) async {
    String role = (user['role'] ?? _defaultRole).toString();
    bool fullAccess = user['full_access'] == true || user['full_access'] == 1;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: ThemeConstants.primaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(LocalizationService.instance.translate('change_role'), style: TextStyle(color: ThemeConstants.textPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _roleDropdownItems.any((e) => e.value == role) ? role : _defaultRole,
                    dropdownColor: ThemeConstants.primaryBlue,
                    style: const TextStyle(color: ThemeConstants.textPrimary),
                    decoration: InputDecoration(
                      labelText: _loc.translate('role'),
                      labelStyle: const TextStyle(color: ThemeConstants.textSecondary),
                      prefixIcon: const Icon(Icons.verified_user, color: ThemeConstants.textSecondary),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                      ),
                    ),
                    items: _roleDropdownItems,
                    onChanged: (v) => setState(() => role = v ?? _defaultRole),
                  ),
                  const SizedBox(height: 16),
                  StatefulBuilder(
                    builder: (context, setDialogState) {
                      return SwitchListTile.adaptive(
                        value: fullAccess,
                        onChanged: (v) => setDialogState(() => fullAccess = v),
                        title: Text(
                          _loc.isSwahili ? 'Ufikiaji Kamili wa Moduli' : 'Full Module Access',
                          style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
                        ),
                        subtitle: Text(
                          _loc.isSwahili ? 'Ruhusu kuona watumiaji wote wa huduma hii' : 'Allow seeing all users of this service',
                          style: const TextStyle(color: ThemeConstants.textSecondary, fontSize: 12),
                        ),
                        activeColor: ThemeConstants.primaryOrange,
                        contentPadding: EdgeInsets.zero,
                      );
                    }
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(_loc.translate('cancel'), style: const TextStyle(color: ThemeConstants.textSecondary)),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(backgroundColor: ThemeConstants.primaryOrange),
                  child: Text(_loc.translate('yes'), style: const TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      },
    );

    if (ok != true) return;

    try {
      final String id = (user['id'] ?? user['user_id'] ?? '').toString();
      await _api.updateUser(id, <String, dynamic>{
        'role': role,
        'service_type': _activeService,
        'full_access': fullAccess,
      });
      await _loadMyUsers();
      if (mounted) {
        ThemeConstants.showSuccessSnackBar(
            context, _loc.isSwahili ? 'Jukumu limesasishwa' : 'Role updated successfully');
      }
    } catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _resetUserPassword(Map<String, dynamic> user) async {
    final String name = (user['name'] ?? '').toString();
    final String defaultPassword = _defaultPasswordFromName(name);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_loc.translate('reset_password'),
            style: const TextStyle(color: ThemeConstants.textPrimary),
            overflow: TextOverflow.ellipsis),
        content: Text(
          _loc.isSwahili
              ? 'Utarejesha nywila ya ${user['name']} kuwa "$defaultPassword"?'
              : "Reset ${user['name']}'s password to \"$defaultPassword\"?",
          style: const TextStyle(color: ThemeConstants.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_loc.translate('no'),
                style: const TextStyle(color: ThemeConstants.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_loc.translate('yes'),
                style: const TextStyle(color: ThemeConstants.primaryOrange)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final String id = (user['id'] ?? user['user_id'] ?? '').toString();
      await _api.resetUserPassword(userId: id, newPassword: defaultPassword);
      if (mounted) {
        ThemeConstants.showSuccessSnackBar(
            context, _loc.translate('password_reset_successfully'));
      }
    } catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _setUserActive(Map<String, dynamic> user, bool active) async {
    try {
      final String id = (user['id'] ?? user['user_id'] ?? '').toString();
      await _api.updateUser(id, <String, dynamic>{'is_active': active});
      await _loadMyUsers();
      if (mounted) {
        ThemeConstants.showSuccessSnackBar(
            context, _loc.isSwahili ? 'Imesasishwa' : 'Updated');
      }
    } catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ThemeConstants.primaryBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_loc.isSwahili ? 'Thibitisha' : 'Confirm',
            style: const TextStyle(color: ThemeConstants.textPrimary),
            overflow: TextOverflow.ellipsis),
        content: Text(
          _loc.isSwahili
              ? 'Una uhakika unataka kufuta mtumiaji huyu?'
              : 'Are you sure you want to delete this user?',
          style: const TextStyle(color: ThemeConstants.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_loc.translate('no'),
                style: const TextStyle(color: ThemeConstants.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_loc.translate('yes'),
                style: const TextStyle(color: ThemeConstants.primaryOrange)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final String id = (user['id'] ?? user['user_id'] ?? '').toString();
      await _api.deleteUser(id);
      await _loadMyUsers();
      if (mounted) {
        ThemeConstants.showSuccessSnackBar(
            context, _loc.isSwahili ? 'Imefutwa' : 'Deleted');
      }
    } catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(_loc.translate('users_management')),
      floatingActionButton:
          (user?.isAdmin == true || user?.isSuperAdmin == true)
              ? FloatingActionButton(
                  backgroundColor: ThemeConstants.primaryOrange,
                  foregroundColor: Colors.white,
                  onPressed: _openCreateDialog,
                  child: const Icon(Icons.person_add_alt_1),
                )
              : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThemeConstants.buildGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.people,
                          color: ThemeConstants.primaryOrange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _loc.translate('users_subtitle'),
                          style: const TextStyle(
                              color: ThemeConstants.textSecondary),
                        ),
                      ),
                      if (user?.isAdmin == true || user?.isSuperAdmin == true)
                        FilledButton.icon(
                          onPressed: _openCreateDialog,
                          style: FilledButton.styleFrom(
                            backgroundColor: ThemeConstants.primaryOrange,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.add),
                          label: Text(_loc.translate('create_user')),
                        ),
                    ],
                  ),
                ),
              ),
              if (user?.isSuperAdmin == true) ...<Widget>[
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    ChoiceChip(
                      label: Text(_loc.isSwahili ? 'Orodha' : 'List'),
                      selected: !_groupedView,
                      onSelected: (bool v) {
                        if (v) setState(() => _groupedView = false);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(_loc.isSwahili ? 'Kwa Huduma' : 'By Service'),
                      selected: _groupedView,
                      onSelected: (bool v) {
                        setState(() => _groupedView = v);
                        if (v && _groupedData == null) _loadGrouped();
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (user?.isSuperAdmin == true && _groupedView)
                Expanded(child: _groupedUsersView())
              else if (_loading)
                ThemeConstants.buildLoadingWidget()
              else
                Expanded(
                  child: _users.isEmpty
                      ? Center(
                          child: Text(
                            _loc.isSwahili
                                ? 'Hakuna watumiaji wako bado'
                                : 'No users created by you yet',
                            style: const TextStyle(
                                color: ThemeConstants.textSecondary),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _users.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) => _userCard(_users[index]),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _userCard(Map<String, dynamic> m) {
    final String name = (m['name'] ?? '').toString();
    final String email = (m['email'] ?? '').toString();
    final String role = (m['role'] ?? '').toString();
    final bool active = m['is_active'] == true || m['is_active'] == 1;
    final String? createdByName = m['created_by_name']?.toString();
    return ThemeConstants.buildGlassCard(
      onTap: () => _showUserActions(m),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: ThemeConstants.primaryOrange,
          child: Text(
            name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(name,
            style: const TextStyle(
                color: ThemeConstants.textPrimary,
                fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$email • ${role.toUpperCase()}${active ? '' : ' • INACTIVE'}',
              style: const TextStyle(color: ThemeConstants.textSecondary),
            ),
            if ((m['service_types'] as List?)?.isNotEmpty == true)
              Text(
                ((m['service_types'] as List)
                    .map((s) => _serviceLabel(s.toString()))
                    .join(', ')),
                style: const TextStyle(
                    color: Colors.lightBlueAccent, fontSize: 11),
              )
            else
              Text(
                _loc.isSwahili ? 'Huduma: hakuna' : 'Services: none',
                style: const TextStyle(color: Colors.orange, fontSize: 11),
              ),
            if (createdByName != null && createdByName.isNotEmpty)
              Text(
                (_loc.isSwahili ? 'Meneja: ' : 'Managed by: ') + createdByName,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        ),
        trailing: const Icon(Icons.more_vert, color: Colors.white70),
      ),
    );
  }

  Widget _groupedUsersView() {
    if (_loadingGrouped) {
      return ThemeConstants.buildLoadingWidget();
    }
    final Map<String, dynamic> data = _groupedData ?? const <String, dynamic>{};
    final Map<String, dynamic> byService =
        (data['by_service'] as Map?)?.cast<String, dynamic>() ?? const {};
    final List<dynamic> generalAdmins =
        (data['general_admins'] as List?) ?? const [];

    final List<Widget> sections = <Widget>[];
    for (final String service in <String>['transport', 'rental', 'inventory', 'salon']) {
      final List<dynamic> groups = (byService[service] as List?) ?? const [];
      if (groups.isEmpty) continue;
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(
            _serviceLabel(service),
            style: const TextStyle(
              color: ThemeConstants.primaryOrange,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      );
      for (final dynamic g in groups) {
        final Map<String, dynamic> group = Map<String, dynamic>.from(g as Map);
        final Map<String, dynamic>? admin = group['admin'] is Map
            ? Map<String, dynamic>.from(group['admin'] as Map)
            : null;
        final List<dynamic> users = (group['users'] as List?) ?? const [];
        sections.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 6, bottom: 4),
            child: Text(
              admin != null
                  ? '${_loc.isSwahili ? "Meneja" : "Admin"}: ${admin['name']} (${admin['email']})'
                  : (_loc.isSwahili ? 'Hakuna meneja aliyewekwa' : 'No admin assigned'),
              style: const TextStyle(
                  color: Colors.lightBlueAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ),
        );
        for (final dynamic u in users) {
          sections.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _userCard(Map<String, dynamic>.from(u as Map)),
            ),
          );
        }
      }
    }

    if (generalAdmins.isNotEmpty) {
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(
            _loc.isSwahili ? 'Wasimamizi wakuu (bila huduma maalum)' : 'General admins (no specific service)',
            style: const TextStyle(
              color: ThemeConstants.primaryOrange,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      );
      for (final dynamic u in generalAdmins) {
        sections.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _userCard(Map<String, dynamic>.from(u as Map)),
          ),
        );
      }
    }

    if (sections.isEmpty) {
      return Center(
        child: Text(
          _loc.isSwahili ? 'Hakuna watumiaji' : 'No users',
          style: const TextStyle(color: ThemeConstants.textSecondary),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGrouped,
      child: ListView(children: sections),
    );
  }
}
