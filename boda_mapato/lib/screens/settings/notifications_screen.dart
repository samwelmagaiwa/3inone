import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/theme_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import '../../utils/server_message.dart';
import 'business_sms_switches_screen.dart';
import 'sms_confirm_dialog.dart';
import 'sms_counters_screen.dart';

class NotificationsScreen extends StatefulWidget {
  NotificationsScreen({super.key, final ApiService? api, this.superAdmin}) : api = api ?? ApiService();

  /// Where the SMS master switch is read and saved (a fake in tests).
  final ApiService api;

  /// Whether the person is the super admin (then the row opens the list of businesses). Null = read it from the signed-in user.
  final bool? superAdmin;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final LocalizationService _localizationService = LocalizationService.instance;

  bool _pushNotifications = true;
  bool _emailNotifications = true;
  bool _paymentAlerts = true;
  bool _debtReminders = true;
  bool _systemUpdates = false;
  bool _isLoading = true;

  /// The business's SMS master switch as the server has it; null when this account has no business (a super admin) or it could not be read.
  Map<String, dynamic>? _sms;
  bool _smsSaving = false;

  /// The super admin belongs to no business: their row opens the list of businesses instead.
  bool _superAdmin = false;

  @override
  void initState() {
    super.initState();
    _superAdmin = widget.superAdmin ?? _signedInIsSuperAdmin();
    _loadSettings();
    if (!_superAdmin) {
      _loadSmsSwitch();
    }
  }

  bool _signedInIsSuperAdmin() {
    try {
      return Provider.of<AuthProvider>(context, listen: false).user?.isSuperAdmin ?? false;
    } on Object {
      return false;
    }
  }

  Future<void> _loadSmsSwitch() async {
    final Map<String, dynamic>? res = await widget.api.getOrNull('/business/sms-switch');
    final dynamic data = res?['data'];
    if (!mounted || data is! Map) {
      return;
    }
    setState(() => _sms = Map<String, dynamic>.from(data));
  }

  /// Switching needs the owner's password, and switching OFF also needs the word the server names typed in, so it is never flipped by a
  /// stray tap. The server checks both again.
  Future<void> _changeSms(final bool enable) async {
    final String word = (_sms?['confirm_word'] ?? '').toString();
    final SmsConfirm? answer = await showDialog<SmsConfirm>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SmsConfirmDialog(
        enable: enable,
        word: word,
        title: _localizationService.translate(enable ? 'sms_master_on_title' : 'sms_master_off_title'),
        body: _localizationService.translate(enable ? 'sms_master_on_body' : 'sms_master_off_body'),
      ),
    );
    if (answer == null || !mounted) {
      return;
    }
    setState(() => _smsSaving = true);
    try {
      final Map<String, dynamic> res = await widget.api.put('/business/sms-switch', <String, dynamic>{
        'enabled': enable,
        'password': answer.password,
        if (!enable) 'confirm': answer.word,
      });
      final dynamic data = res['data'];
      if (!mounted) {
        return;
      }
      setState(() {
        if (data is Map) {
          _sms = Map<String, dynamic>.from(data);
        }
      });
      // The app's own green banner at the top, like every other saved change.
      ThemeConstants.showSuccessSnackBar(context, _localizationService.translate(enable ? 'sms_master_now_on' : 'sms_master_now_off'));
    } on Exception catch (e) {
      if (mounted) {
        ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _smsSaving = false);
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pushNotifications = prefs.getBool('push_notifications') ?? true;
      _emailNotifications = prefs.getBool('email_notifications') ?? true;
      _paymentAlerts = prefs.getBool('payment_alerts') ?? true;
      _debtReminders = prefs.getBool('debt_reminders') ?? true;
      _systemUpdates = prefs.getBool('system_updates') ?? false;
      _isLoading = false;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(
        _localizationService.translate('notifications'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: ThemeConstants.primaryOrange,
              ),
            )
          : SafeArea(
              child: Padding(
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
                                color: ThemeConstants.primaryOrange
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.notifications,
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
                                    _localizationService
                                        .translate('notifications'),
                                    style: const TextStyle(
                                      color: ThemeConstants.textPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _localizationService
                                        .translate('notifications_subtitle'),
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

                    // Notification Settings
                    ThemeConstants.buildGlassCard(
                      child: Column(
                        children: [
                          _buildNotificationSwitch(
                            Icons.notifications_active,
                            _localizationService
                                .translate('push_notifications'),
                            'push_notifications',
                            _pushNotifications,
                            (value) =>
                                setState(() => _pushNotifications = value),
                          ),
                          const Divider(color: Colors.white24, height: 1),
                          _buildNotificationSwitch(
                            Icons.email,
                            _localizationService
                                .translate('email_notifications'),
                            'email_notifications',
                            _emailNotifications,
                            (value) =>
                                setState(() => _emailNotifications = value),
                          ),
                          const Divider(color: Colors.white24, height: 1),
                          _buildNotificationSwitch(
                            Icons.payment,
                            _localizationService.translate('payment_alerts'),
                            'payment_alerts',
                            _paymentAlerts,
                            (value) => setState(() => _paymentAlerts = value),
                          ),
                          // The owner's master switch for every text the business sends (kept on the server, not on this phone).
                          if (_sms != null) ...<Widget>[
                            const Divider(color: Colors.white24, height: 1),
                            _buildSmsMasterSwitch(_sms!),
                          ],
                          // The super admin picks a business and switches ITS texts off or on.
                          if (_superAdmin) ...<Widget>[
                            const Divider(color: Colors.white24, height: 1),
                            _buildSuperAdminSmsRow(),
                            // How many SMS each business used against its limit, and its texts of the last 3 days.
                            const Divider(color: Colors.white24, height: 1),
                            _buildSmsCounterRow(),
                          ],
                          const Divider(color: Colors.white24, height: 1),
                          _buildNotificationSwitch(
                            Icons.schedule,
                            _localizationService.translate('debt_reminders'),
                            'debt_reminders',
                            _debtReminders,
                            (value) => setState(() => _debtReminders = value),
                          ),
                          const Divider(color: Colors.white24, height: 1),
                          _buildNotificationSwitch(
                            Icons.system_update,
                            _localizationService.translate('system_updates'),
                            'system_updates',
                            _systemUpdates,
                            (value) => setState(() => _systemUpdates = value),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Info Card
                    ThemeConstants.buildGlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: ThemeConstants.primaryOrange,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _localizationService.isSwahili
                                    ? 'Mipangilio hii itasaidia kudhibiti aina za arifa unazopokea.'
                                    : 'These settings help control what types of notifications you receive.',
                                style: const TextStyle(
                                  color: ThemeConstants.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSmsMasterSwitch(final Map<String, dynamic> sms) {
    final bool on = sms['enabled'] != false;
    final bool canChange = sms['can_change'] == true;
    final String since = (sms['paused_at'] ?? '').toString();
    final String by = (sms['paused_by'] ?? '').toString();
    final bool byPlatform = sms['paused_by_platform'] == true;
    final List<String> lines = <String>[
      if (on) _localizationService.translate('sms_master_on_subtitle')
      else _localizationService.translateWith('sms_master_off_subtitle', <Object?>[since.length >= 10 ? since.substring(0, 10) : since]),
      if (!on && byPlatform) _localizationService.translate('sms_master_off_platform')
      else if (!on && by.isNotEmpty) _localizationService.translateWith('sms_master_off_by', <Object?>[by]),
      if (!canChange && !byPlatform) _localizationService.translate('sms_master_owner_only'),
    ];

    return ListTile(
      key: const ValueKey<String>('sms_master_switch'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(on ? Icons.sms : Icons.sms_failed, color: on ? ThemeConstants.textSecondary : Colors.redAccent, size: 24),
      title: Text(
        _localizationService.translate('sms_master_title'),
        style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 16),
      ),
      subtitle: Text(
        lines.join('\n'),
        style: TextStyle(color: on ? ThemeConstants.textSecondary : Colors.redAccent, fontSize: 12),
      ),
      trailing: _smsSaving
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: ThemeConstants.primaryOrange))
          : Switch.adaptive(
              value: on,
              // Staff see the state but cannot change it.
              onChanged: canChange ? (final bool v) => _changeSms(v) : null,
              activeColor: ThemeConstants.primaryOrange,
              activeTrackColor: ThemeConstants.primaryOrange.withOpacity(0.3),
              inactiveThumbColor: ThemeConstants.textSecondary,
              inactiveTrackColor: Colors.white24,
            ),
    );
  }

  Widget _buildSmsCounterRow() {
    return ListTile(
      key: const ValueKey<String>('sms_counter_row'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: const Icon(Icons.speed, color: ThemeConstants.textSecondary, size: 24),
      title: Text(
        _localizationService.translate('sms_counter_row_title'),
        style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 16),
      ),
      subtitle: Text(
        _localizationService.translate('sms_counter_row_subtitle'),
        style: const TextStyle(color: ThemeConstants.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: ThemeConstants.textSecondary),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SmsCountersScreen(api: widget.api)),
      ),
    );
  }

  Widget _buildSuperAdminSmsRow() {
    return ListTile(
      key: const ValueKey<String>('sms_admin_row'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: const Icon(Icons.sms, color: ThemeConstants.textSecondary, size: 24),
      title: Text(
        _localizationService.translate('sms_admin_tile_title'),
        style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 16),
      ),
      subtitle: Text(
        _localizationService.translate('sms_admin_tile_subtitle'),
        style: const TextStyle(color: ThemeConstants.textSecondary, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: ThemeConstants.textSecondary),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => BusinessSmsSwitchesScreen(api: widget.api)),
      ),
    );
  }

  Widget _buildNotificationSwitch(
    IconData icon,
    String title,
    String key,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
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
        ),
      ),
      trailing: Switch.adaptive(
        value: value,
        onChanged: (newValue) {
          onChanged(newValue);
          _saveSetting(key, newValue);
        },
        activeColor: ThemeConstants.primaryOrange,
        activeTrackColor: ThemeConstants.primaryOrange.withOpacity(0.3),
        inactiveThumbColor: ThemeConstants.textSecondary,
        inactiveTrackColor: Colors.white24,
      ),
    );
  }
}

