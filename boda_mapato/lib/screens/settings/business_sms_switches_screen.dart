import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/theme_constants.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import '../../utils/server_message.dart';
import 'sms_confirm_dialog.dart';

/// Super admin: every business with its SMS master switch. Pick one and switch ITS texts off (or on); every other business keeps
/// sending. A business the super admin switched off cannot be switched on by its owner. Each change needs the super admin's password,
/// and switching off also needs the word ZIMA (checked again on the server).
class BusinessSmsSwitchesScreen extends StatefulWidget {
  BusinessSmsSwitchesScreen({super.key, final ApiService? api}) : api = api ?? ApiService();

  final ApiService api;

  @override
  State<BusinessSmsSwitchesScreen> createState() => _BusinessSmsSwitchesScreenState();
}

class _BusinessSmsSwitchesScreenState extends State<BusinessSmsSwitchesScreen> {
  final LocalizationService _loc = LocalizationService.instance;
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  final Set<String> _saving = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final String q = _search.text.trim();
      final Map<String, dynamic> res = await widget.api.get(
        '/admin/businesses',
        queryParams: <String, dynamic>{'per_page': 100, if (q.isNotEmpty) 'q': q},
      );
      final dynamic data = res['data'];
      if (!mounted) {
        return;
      }
      setState(() {
        _items = data is List ? data.whereType<Map>().map(Map<String, dynamic>.from).toList() : <Map<String, dynamic>>[];
        _loading = false;
      });
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = readableErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  void _onSearch(final String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  static Map<String, dynamic> _sms(final Map<String, dynamic> b) =>
      b['sms_sender'] is Map ? Map<String, dynamic>.from(b['sms_sender'] as Map) : <String, dynamic>{};

  Future<void> _change(final Map<String, dynamic> business, final bool enable) async {
    final String id = (business['id'] ?? '').toString();
    final String name = (business['name'] ?? '').toString();
    final SmsConfirm? answer = await showDialog<SmsConfirm>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SmsConfirmDialog(
        enable: enable,
        word: 'ZIMA',
        title: _loc.translate(enable ? 'sms_master_on_title' : 'sms_master_off_title'),
        body: _loc.translateWith(enable ? 'sms_admin_on_body' : 'sms_admin_off_body', <Object?>[name]),
      ),
    );
    if (answer == null || !mounted) {
      return;
    }
    setState(() => _saving.add(id));
    try {
      final Map<String, dynamic> res = await widget.api.put('/admin/businesses/$id/sms-switch', <String, dynamic>{
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
          final Map<String, dynamic> sms = _sms(business)
            ..['paused'] = data['enabled'] == false
            ..['paused_at'] = data['paused_at']
            ..['paused_by_platform'] = data['paused_by_platform'] == true;
          business['sms_sender'] = sms;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$name: ${_loc.translate(enable ? 'sms_master_now_on' : 'sms_master_now_off')}'),
      ));
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(readableErrorMessage(e)), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) {
        setState(() => _saving.remove(id));
      }
    }
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(_loc.translate('sms_admin_screen_title')),
      body: SafeArea(
        child: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              key: const ValueKey<String>('sms_admin_search'),
              controller: _search,
              onChanged: _onSearch,
              style: const TextStyle(color: ThemeConstants.textPrimary),
              decoration: InputDecoration(
                hintText: _loc.translate('sms_admin_search'),
                hintStyle: const TextStyle(color: ThemeConstants.textSecondary),
                prefixIcon: const Icon(Icons.search, color: ThemeConstants.textSecondary),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: ThemeConstants.primaryOrange));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: ThemeConstants.textSecondary)));
    }
    if (_items.isEmpty) {
      return Center(child: Text(_loc.translate('sms_admin_empty'), style: const TextStyle(color: ThemeConstants.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, final int i) => _row(_items[i]),
      ),
    );
  }

  Widget _row(final Map<String, dynamic> b) {
    final String id = (b['id'] ?? '').toString();
    final Map<String, dynamic> sms = _sms(b);
    final bool on = sms['paused'] != true;
    final bool byPlatform = sms['paused_by_platform'] == true;
    final Map<String, dynamic> owner = b['owner'] is Map ? Map<String, dynamic>.from(b['owner'] as Map) : <String, dynamic>{};
    final String who = <String>[
      (owner['name'] ?? '').toString(),
      (owner['email'] ?? '').toString(),
    ].where((final String s) => s.isNotEmpty).join(' · ');

    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        key: ValueKey<String>('sms_admin_business_$id'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(on ? Icons.sms : Icons.sms_failed, color: on ? ThemeConstants.textSecondary : Colors.redAccent),
        title: Text((b['name'] ?? '').toString(), style: const TextStyle(color: ThemeConstants.textPrimary, fontWeight: FontWeight.w600)),
        subtitle: Text(
          <String>[
            if (who.isNotEmpty) who,
            if (!on) _loc.translate(byPlatform ? 'sms_admin_off_platform' : 'sms_admin_off_owner'),
          ].join('\n'),
          style: TextStyle(color: on ? ThemeConstants.textSecondary : Colors.redAccent, fontSize: 12),
        ),
        trailing: _saving.contains(id)
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: ThemeConstants.primaryOrange))
            : Switch.adaptive(
                value: on,
                onChanged: (final bool v) => _change(b, v),
                activeThumbColor: ThemeConstants.primaryOrange,
                activeTrackColor: ThemeConstants.primaryOrange.withValues(alpha: 0.3),
                inactiveThumbColor: ThemeConstants.textSecondary,
                inactiveTrackColor: Colors.white24,
              ),
      ),
    );
  }
}
