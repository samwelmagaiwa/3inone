import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/theme_constants.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';

class NotificationsScreen extends StatefulWidget {
  NotificationsScreen({super.key, final ApiService? api}) : api = api ?? ApiService();

  /// Where the SMS master switch is read and saved (a fake in tests).
  final ApiService api;

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadSmsSwitch();
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
    final _SmsConfirm? answer = await showDialog<_SmsConfirm>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SmsConfirmDialog(enable: enable, word: word),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_localizationService.translate(enable ? 'sms_master_now_on' : 'sms_master_now_off')),
      ));
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
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
    final List<String> lines = <String>[
      if (on) _localizationService.translate('sms_master_on_subtitle')
      else _localizationService.translateWith('sms_master_off_subtitle', <Object?>[since.length >= 10 ? since.substring(0, 10) : since]),
      if (!on && by.isNotEmpty) _localizationService.translateWith('sms_master_off_by', <Object?>[by]),
      if (!canChange) _localizationService.translate('sms_master_owner_only'),
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

/// What the owner typed to confirm a change of the SMS master switch.
class _SmsConfirm {
  const _SmsConfirm(this.password, this.word);
  final String password;
  final String word;
}

/// Asks for the password, and (to switch OFF) the confirm word typed exactly; the button stays grey until both are there.
class _SmsConfirmDialog extends StatefulWidget {
  const _SmsConfirmDialog({required this.enable, required this.word});

  final bool enable;
  final String word;

  @override
  State<_SmsConfirmDialog> createState() => _SmsConfirmDialogState();
}

class _SmsConfirmDialogState extends State<_SmsConfirmDialog> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _word = TextEditingController();
  bool _hide = true;

  @override
  void dispose() {
    _password.dispose();
    _word.dispose();
    super.dispose();
  }

  bool get _ready =>
      _password.text.isNotEmpty && (widget.enable || widget.word.isEmpty || _word.text.trim().toUpperCase() == widget.word.toUpperCase());

  @override
  Widget build(final BuildContext context) {
    final LocalizationService loc = LocalizationService.instance;
    return AlertDialog(
      title: Row(children: <Widget>[
        Icon(widget.enable ? Icons.sms : Icons.warning_amber_rounded, color: widget.enable ? Colors.green : Colors.red),
        const SizedBox(width: 8),
        Expanded(child: Text(loc.translate(widget.enable ? 'sms_master_on_title' : 'sms_master_off_title'))),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(loc.translate(widget.enable ? 'sms_master_on_body' : 'sms_master_off_body')),
          const SizedBox(height: 16),
          if (!widget.enable && widget.word.isNotEmpty) ...<Widget>[
            TextField(
              key: const ValueKey<String>('sms_master_word'),
              controller: _word,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: loc.translateWith('sms_master_type_word', <Object?>[widget.word])),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            key: const ValueKey<String>('sms_master_password'),
            controller: _password,
            obscureText: _hide,
            decoration: InputDecoration(
              labelText: loc.translate('sms_master_password'),
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(loc.translate('cancel'))),
        FilledButton(
          key: const ValueKey<String>('sms_master_confirm'),
          style: FilledButton.styleFrom(backgroundColor: widget.enable ? Colors.green : Colors.red),
          onPressed: _ready ? () => Navigator.of(context).pop(_SmsConfirm(_password.text, _word.text.trim())) : null,
          child: Text(loc.translate(widget.enable ? 'sms_master_switch_on' : 'sms_master_switch_off')),
        ),
      ],
    );
  }
}
