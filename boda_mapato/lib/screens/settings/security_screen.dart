import 'package:flutter/material.dart';
import '../../constants/theme_constants.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';

import 'dart:async';

// ignore_for_file: avoid_catches_without_on_clauses, unawaited_futures, unnecessary_brace_in_string_interps, control_flow_in_finally, directives_ordering
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final LocalizationService _localizationService = LocalizationService.instance;
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isChangingPassword = false;
  bool _twoFactorEnabled = false;
  bool _loadingSettings = true;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    await _apiService.initialize();
    await _loadSecuritySettings();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(
        _localizationService.translate('security'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header
              ThemeConstants.buildGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: ThemeConstants.primaryOrange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.security,
                          color: ThemeConstants.primaryOrange,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _localizationService.translate('security'),
                              style: const TextStyle(
                                color: ThemeConstants.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _localizationService
                                  .translate('security_subtitle'),
                              style: const TextStyle(
                                color: ThemeConstants.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Change Password Section
              ThemeConstants.buildGlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _localizationService.translate('change_password'),
                          style: const TextStyle(
                            color: ThemeConstants.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Current Password
                        TextFormField(
                          controller: _currentPasswordController,
                          obscureText: _obscureCurrentPassword,
                          style: const TextStyle(
                              color: ThemeConstants.textPrimary),
                          decoration: InputDecoration(
                            labelText: _localizationService
                                .translate('current_password'),
                            labelStyle: const TextStyle(
                                color: ThemeConstants.textSecondary),
                            prefixIcon: const Icon(Icons.lock_outline,
                                color: ThemeConstants.textSecondary),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureCurrentPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: ThemeConstants.textSecondary,
                              ),
                              onPressed: () => setState(() =>
                                  _obscureCurrentPassword =
                                      !_obscureCurrentPassword),
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.3)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: ThemeConstants.primaryOrange),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return _localizationService.isSwahili
                                  ? 'Ingiza neno la siri la sasa'
                                  : 'Enter current password';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // New Password
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: _obscureNewPassword,
                          style: const TextStyle(
                              color: ThemeConstants.textPrimary),
                          decoration: InputDecoration(
                            labelText:
                                _localizationService.translate('new_password'),
                            labelStyle: const TextStyle(
                                color: ThemeConstants.textSecondary),
                            prefixIcon: const Icon(Icons.lock,
                                color: ThemeConstants.textSecondary),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureNewPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: ThemeConstants.textSecondary,
                              ),
                              onPressed: () => setState(() =>
                                  _obscureNewPassword = !_obscureNewPassword),
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.3)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: ThemeConstants.primaryOrange),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return _localizationService.isSwahili
                                  ? 'Ingiza neno la siri jipya'
                                  : 'Enter new password';
                            }
                            if (value.length < 6) {
                              return _localizationService.isSwahili
                                  ? 'Neno la siri lazima liwe na angalau herufi 6'
                                  : 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // Confirm Password
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          style: const TextStyle(
                              color: ThemeConstants.textPrimary),
                          decoration: InputDecoration(
                            labelText: _localizationService
                                .translate('confirm_password'),
                            labelStyle: const TextStyle(
                                color: ThemeConstants.textSecondary),
                            prefixIcon: const Icon(Icons.lock_clock,
                                color: ThemeConstants.textSecondary),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: ThemeConstants.textSecondary,
                              ),
                              onPressed: () => setState(() =>
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword),
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.3)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: ThemeConstants.primaryOrange),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return _localizationService.isSwahili
                                  ? 'Thibitisha neno la siri'
                                  : 'Confirm password';
                            }
                            if (value != _newPasswordController.text) {
                              return _localizationService.isSwahili
                                  ? 'Maneno ya siri hayalingani'
                                  : 'Passwords do not match';
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 20),

                        // Change Password Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                _isChangingPassword ? null : _changePassword,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ThemeConstants.primaryOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isChangingPassword
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(_localizationService
                                    .translate('change_password')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Other Security Settings
              ThemeConstants.buildGlassCard(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      leading: const Icon(Icons.security,
                          color: ThemeConstants.textSecondary),
                      title: Text(
                        _localizationService.translate('two_factor_auth'),
                        style:
                            const TextStyle(color: ThemeConstants.textPrimary),
                      ),
                      trailing: _loadingSettings
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: ThemeConstants.primaryOrange),
                            )
                          : Switch.adaptive(
                              value: _twoFactorEnabled,
                              onChanged: _onToggleTwoFactor,
                              activeColor: ThemeConstants.primaryOrange,
                            ),
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      leading: const Icon(Icons.history,
                          color: ThemeConstants.textSecondary),
                      title: Text(
                        _localizationService.translate('login_history'),
                        style:
                            const TextStyle(color: ThemeConstants.textPrimary),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: ThemeConstants.textSecondary),
                      onTap: _viewLoginHistory,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isChangingPassword = true);

    try {
      // Call API to change password
      final response = await _apiService.post('/auth/change-password', {
        'current_password': _currentPasswordController.text,
        'new_password': _newPasswordController.text,
        'new_password_confirmation': _confirmPasswordController.text,
      });

      if (response['success'] == true) {
        // Clear form
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();

        // Show success message
        if (mounted) {
          ThemeConstants.showSuccessSnackBar(
            context,
            _localizationService.translate('password_changed'),
          );
        }

        // This device stays signed in: the server keeps the device the password was changed on
        // and signs out only the person's OTHER devices (those may have been using the old
        // password). Logging out here as well would sign the user out for no reason.
        return;
      } else {
        throw Exception(response['message'] ?? 'Failed to change password');
      }
    } catch (e) {
      if (!mounted) return;
      ThemeConstants.showErrorSnackBar(
        context,
        _localizationService.isSwahili
            ? 'Imeshindikana kubadilisha neno la siri: ${e}'
            : 'Failed to change password: ${e}',
      );
    } finally {
      if (!mounted) return;
      setState(() => _isChangingPassword = false);
    }
  }

  Future<void> _viewLoginHistory() async {
    try {
      final resp = await _apiService.getLoginHistory(limit: 50);
      final List<dynamic> items = resp['data'] as List<dynamic>? ?? <dynamic>[];
      if (!mounted) return;
      int page = 1;
      bool hasMore = false;
      bool loadingMore = false;
      final List<dynamic> all = List<dynamic>.from(items);
      final meta = resp['pagination'] as Map<String, dynamic>?;
      hasMore = meta?['has_more_pages'] == true;

      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            backgroundColor: ThemeConstants.primaryBlue,
            title: Text(
              _localizationService.translate('login_history'),
              style: const TextStyle(color: ThemeConstants.textPrimary),
            ),
            content: SizedBox(
              width: 420,
              child: all.isEmpty
                  ? Text(
                      _localizationService.translate('no_login_history'),
                      style:
                          const TextStyle(color: ThemeConstants.textSecondary),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 320,
                          child: ListView.separated(
                            itemCount: all.length,
                            separatorBuilder: (_, __) => const Divider(
                                color: Colors.white24, height: 12),
                            itemBuilder: (context, index) {
                              final m =
                                  Map<String, dynamic>.from(all[index] as Map);
                              final String when = (m['login_at'] ?? '')
                                  .toString()
                                  .replaceFirst('T', ' ');
                              final String ip =
                                  (m['ip_address'] ?? '').toString();
                              final String ua =
                                  (m['user_agent'] ?? '').toString();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(when,
                                      style: const TextStyle(
                                          color: ThemeConstants.textPrimary,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(ip.isNotEmpty ? 'IP: $ip' : 'IP: -',
                                      style: const TextStyle(
                                          color: ThemeConstants.textSecondary,
                                          fontSize: 12)),
                                  if (ua.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      ua,
                                      style: const TextStyle(
                                          color: ThemeConstants.textSecondary,
                                          fontSize: 12),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (hasMore)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: loadingMore
                                  ? null
                                  : () async {
                                      try {
                                        final next =
                                            await _apiService.getLoginHistory(
                                                page: ++page, limit: 50);
                                        final List<dynamic> nextItems =
                                            next['data'] as List<dynamic>? ??
                                                <dynamic>[];
                                        final nmeta = next['pagination']
                                            as Map<String, dynamic>?;
                                        setStateDialog(() {
                                          all.addAll(nextItems);
                                          hasMore =
                                              nmeta?['has_more_pages'] == true;
                                          loadingMore = false;
                                        });
                                      } catch (e) {
                                        setStateDialog(
                                            () => loadingMore = false);
                                        if (mounted) {
                                          ThemeConstants.showErrorSnackBar(context, e.toString());
                                        }
                                      }
                                    },
                              icon: loadingMore
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.expand_more,
                                      color: ThemeConstants.primaryOrange),
                              label: Text(
                                _localizationService.translate('view_all'),
                                style: const TextStyle(
                                    color: ThemeConstants.primaryOrange),
                              ),
                            ),
                          ),
                      ],
                    ),
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
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      ThemeConstants.showErrorSnackBar(context, e.toString());
    }
  }

  Future<void> _loadSecuritySettings() async {
    try {
      final resp = await _apiService.getSecuritySettings();
      final data = resp['data'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _twoFactorEnabled = (data?['two_factor_enabled'] == true);
          _loadingSettings = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _loadingSettings = false);
        ThemeConstants.showErrorSnackBar(context, e.toString());
      }
    }
  }

  Future<void> _onToggleTwoFactor(bool value) async {
    final prev = _twoFactorEnabled;
    setState(() => _twoFactorEnabled = value);
    try {
      final resp = await _apiService.setTwoFactor(value);
      final data = resp['data'] as Map<String, dynamic>?;
      final bool enabled = data?['two_factor_enabled'] == true;
      if (mounted) {
        setState(() => _twoFactorEnabled = enabled);
        ThemeConstants.showSuccessSnackBar(
          context,
          enabled
              ? _localizationService.translate('two_factor_enabled_msg')
              : _localizationService.translate('two_factor_disabled_msg'),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _twoFactorEnabled = prev);
        ThemeConstants.showErrorSnackBar(
          context,
          '${_localizationService.translate('failed_to_update')}: $e',
        );
      }
    }
  }
}
