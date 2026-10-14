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
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  final LocalizationService _loc = LocalizationService.instance;
  final ApiService _api = ApiService();

  bool _loading = true;
  bool _creating = false;
  List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];
  String _activeService = 'transport'; // default

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

  List<DropdownMenuItem<String>> get _roleDropdownItems {
    if (_isRental) {
      return [
        DropdownMenuItem(value: 'admin', child: Text(LocalizationService.instance.translate('admin'))),
        DropdownMenuItem(value: 'landlord', child: Text(LocalizationService.instance.translate('landlord'))),
        DropdownMenuItem(value: 'caretaker', child: Text(LocalizationService.instance.translate('caretaker'))),
        DropdownMenuItem(value: 'tenant', child: Text(LocalizationService.instance.translate('tenant'))),
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

  String get _defaultRole => _isRental ? 'tenant' : 'admin';

  Future<void> _loadMyUsers() async {
    setState(() => _loading = true);
    try {
      final Map<String, dynamic> res = await _api.getUsers(limit: 100, serviceType: _activeService);
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
                child: Form(
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
                          onChanged: (v) => role = v ?? _defaultRole,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile.adaptive(
                          value: isActive,
                          onChanged: (v) => isActive = v,
                          title: Text(
                            _loc.translate('active'),
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
                                'service_type': _activeService,
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
            ],
          ),
        ),
      ),
    );
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
      appBar: ThemeConstants.buildAppBar(LocalizationService.instance.translate('permissions_management')),
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
                      if (user?.isSuperAdmin == true) ...[
                        const SizedBox(width: 8),
                      ]
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_loading)
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
                          itemBuilder: (context, index) {
                            final m = _users[index];
                            final String name = (m['name'] ?? '').toString();
                            final String email = (m['email'] ?? '').toString();
                            final String role = (m['role'] ?? '').toString();
                            final bool active =
                                m['is_active'] == true || m['is_active'] == 1;
                            return ThemeConstants.buildGlassCard(
                              onTap: () => _showUserActions(m),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                leading: CircleAvatar(
                                  backgroundColor: ThemeConstants.primaryOrange,
                                  child: Text(
                                    name.isNotEmpty
                                        ? name.substring(0, 1).toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(name,
                                    style: const TextStyle(
                                        color: ThemeConstants.textPrimary,
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    '$email • ${role.toUpperCase()}${active ? '' : ' • INACTIVE'}',
                                    style: const TextStyle(
                                        color: ThemeConstants.textSecondary)),
                                trailing: const Icon(Icons.more_vert,
                                    color: Colors.white70),
                              ),
                            );
                          },
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
