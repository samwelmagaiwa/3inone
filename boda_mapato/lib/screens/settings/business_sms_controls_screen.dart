import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../constants/theme_constants.dart';
import '../../models/sms_usage.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import '../../utils/server_message.dart';
import 'sms_confirm_dialog.dart';
import 'sms_counters_screen.dart';

/// Super admin, from Users & access > a business admin > "SMS controls": every SMS control of that one business on one page.
///
///   - the counter (used / limit, this week)
///   - its texts switched off or on (the super admin's switch: the owner cannot undo it; password and ZIMA, as everywhere)
///   - the SMS limit, and starting the counter at 0 for a new paid bundle
///   - its sender name, and the texts of the last 3 days
///
/// Read in one call (GET /admin/users/{id}/sms-controls); each change goes to the same endpoints the other SMS screens use, so a new
/// SMS control on the server shows here as soon as it is added to that answer.
class BusinessSmsControlsScreen extends StatefulWidget {
  BusinessSmsControlsScreen({required this.userId, required this.title, super.key, final ApiService? api}) : api = api ?? ApiService();

  /// The business admin (owner) whose business this is.
  final String userId;
  final String title;
  final ApiService api;

  @override
  State<BusinessSmsControlsScreen> createState() => _BusinessSmsControlsScreenState();
}

class _BusinessSmsControlsScreenState extends State<BusinessSmsControlsScreen> {
  final LocalizationService _loc = LocalizationService.instance;
  final TextEditingController _limit = TextEditingController();
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  bool _resetUsed = false;
  String? _limitError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  String get _businessId => '${_data?['id'] ?? ''}';
  String get _name => '${_data?['name'] ?? widget.title}';
  Map<String, dynamic> get _switch => _data?['switch'] is Map ? Map<String, dynamic>.from(_data!['switch'] as Map) : <String, dynamic>{};
  SmsUsage get _usage => SmsUsage.maybe(_data?['usage']) ?? const SmsUsage();

  Future<void> _load() async {
    try {
      final Map<String, dynamic> res = await widget.api.get('/admin/users/${widget.userId}/sms-controls');
      if (!mounted) return;
      setState(() {
        _data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
        _limit.text = _usage.limit?.toString() ?? '';
        _error = null;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  Future<void> _change(final Future<Map<String, dynamic>> Function() action, final String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, '$_name: $done');
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(final bool enable) async {
    final SmsConfirm? answer = await showDialog<SmsConfirm>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SmsConfirmDialog(
        enable: enable,
        word: '${_switch['confirm_word'] ?? ''}',
        title: _loc.translate(enable ? 'sms_master_on_title' : 'sms_master_off_title'),
        body: _loc.translateWith(enable ? 'sms_admin_on_body' : 'sms_admin_off_body', <Object?>[_name]),
      ),
    );
    if (answer == null || !mounted) return;
    await _change(
      () => widget.api.put('/admin/businesses/$_businessId/sms-switch', <String, dynamic>{
        'enabled': enable,
        'password': answer.password,
        if (!enable) 'confirm': answer.word,
      }),
      _loc.translate(enable ? 'sms_master_now_on' : 'sms_master_now_off'),
    );
  }

  Future<void> _saveLimit() async {
    final String text = _limit.text.trim();
    final int? limit = text.isEmpty ? null : int.tryParse(text);
    if (text.isNotEmpty && (limit == null || limit < 0)) {
      setState(() => _limitError = _loc.translate('sms_limit_invalid'));
      return;
    }
    setState(() => _limitError = null);
    final bool reset = _resetUsed;
    await _change(
      () => widget.api.put('/admin/sms-usage/$_businessId/limit', <String, dynamic>{'sms_limit': limit, 'reset_used': reset}),
      _loc.translate('sms_limit_saved'),
    );
    if (mounted) setState(() => _resetUsed = false);
  }

  @override
  Widget build(final BuildContext context) {
    final Map<String, dynamic>? d = _data;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar('${_loc.translate('sms_controls_title')}: ${widget.title}'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent))
            else if (d == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: ThemeConstants.primaryOrange)))
            else ...<Widget>[
              SmsUsageCard(usage: _usage),
              const SizedBox(height: 16),
              _switchCard(),
              const SizedBox(height: 16),
              _limitCard(),
              const SizedBox(height: 16),
              _senderLine(),
              const SizedBox(height: 20),
              ..._recent(d),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _box({required final Widget child, final Key? key}) => Material(
        key: key,
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      );

  Widget _switchCard() {
    final bool on = _switch['enabled'] != false;
    final bool byPlatform = _switch['paused_by_platform'] == true;
    return _box(
      key: const ValueKey<String>('sms_controls_switch'),
      child: Row(children: <Widget>[
        Icon(on ? Icons.sms : Icons.sms_failed, color: on ? Colors.greenAccent : Colors.redAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(_loc.translate('sms_controls_switch'), style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              _loc.translate(on ? 'sms_controls_on' : (byPlatform ? 'sms_controls_off_platform' : 'sms_controls_off_owner')),
              style: TextStyle(color: on ? Colors.greenAccent : Colors.redAccent, fontSize: 12.5),
            ),
          ]),
        ),
        Switch.adaptive(
          value: on,
          onChanged: _busy ? null : _toggle,
          activeThumbColor: ThemeConstants.primaryOrange,
          activeTrackColor: ThemeConstants.primaryOrange.withValues(alpha: 0.3),
          inactiveThumbColor: ThemeConstants.textSecondary,
          inactiveTrackColor: Colors.white24,
        ),
      ]),
    );
  }

  Widget _limitCard() {
    return _box(
      key: const ValueKey<String>('sms_controls_limit'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(_loc.translate('sms_limit_section'), style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey<String>('sms_controls_limit_field'),
          controller: _limit,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            labelText: _loc.translate('sms_limit_field'),
            labelStyle: const TextStyle(color: Colors.white70),
            hintText: '1000',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white38)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white, width: 1.5)),
          ),
        ),
        CheckboxListTile(
          key: const ValueKey<String>('sms_controls_reset'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _resetUsed,
          onChanged: _busy ? null : (final bool? v) => setState(() => _resetUsed = v ?? false),
          title: Text(_loc.translate('sms_limit_reset'), style: const TextStyle(color: Colors.white, fontSize: 14)),
        ),
        Text(_loc.translate('sms_limit_help'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
        if (_limitError != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_limitError!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey<String>('sms_controls_limit_save'),
            onPressed: _busy ? null : _saveLimit,
            icon: const Icon(Icons.speed, size: 18),
            label: Text(_loc.translate('sms_limit_save')),
          ),
        ),
      ]),
    );
  }

  Widget _senderLine() {
    final Map<String, dynamic> s = _data?['sender'] is Map ? Map<String, dynamic>.from(_data!['sender'] as Map) : <String, dynamic>{};
    final String id = '${s['sender_id'] ?? ''}'.trim();
    final String status = '${s['status'] ?? 'none'}';
    return _box(
      key: const ValueKey<String>('sms_controls_sender'),
      child: Row(children: <Widget>[
        const Icon(Icons.badge_outlined, color: ThemeConstants.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            id.isEmpty || status == 'none'
                ? _loc.translate('sms_controls_sender_none')
                : _loc.translateWith('sms_controls_sender', <Object?>[id.toUpperCase(), _loc.translate('sms_sender_status_$status')]),
            style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
          ),
        ),
      ]),
    );
  }

  List<Widget> _recent(final Map<String, dynamic> d) {
    final int days = (d['log_days'] as num?)?.toInt() ?? 3;
    final List<Map<String, dynamic>> recent = d['recent'] is List
        ? (d['recent'] as List).whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    return <Widget>[
      Text(_loc.translateWith('sms_counter_recent', <Object?>[days]), style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (recent.isEmpty)
        Text(_loc.translateWith('sms_counter_recent_empty', <Object?>[days]), style: const TextStyle(color: ThemeConstants.textSecondary))
      else
        for (final Map<String, dynamic> m in recent)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Expanded(
                  child: Text(_loc.translateWith('sms_counter_to', <Object?>['${m['to'] ?? ''}']),
                      style: const TextStyle(color: ThemeConstants.textPrimary, fontWeight: FontWeight.w600)),
                ),
                Text(
                  '${_when(m['sent_at'])}  ·  ${_loc.translateWith('sms_counter_parts', <Object?>[(m['parts'] as num?)?.toInt() ?? 1])}',
                  style: const TextStyle(color: ThemeConstants.textSecondary, fontSize: 12),
                ),
              ]),
              const SizedBox(height: 6),
              Text('${m['message'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
    ];
  }

  String _when(final Object? at) {
    final DateTime? t = DateTime.tryParse('${at ?? ''}')?.toLocal();
    return t == null ? '' : DateFormat('dd/MM HH:mm').format(t);
  }
}
