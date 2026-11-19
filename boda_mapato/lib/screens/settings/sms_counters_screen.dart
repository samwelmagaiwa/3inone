import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../constants/theme_constants.dart';
import '../../models/sms_usage.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import '../../utils/server_message.dart';

/// The counter itself: "20/1000", a bar, what is left, this week, and why texts stopped when they did.
class SmsUsageCard extends StatelessWidget {
  const SmsUsageCard({required this.usage, super.key});

  final SmsUsage usage;

  @override
  Widget build(final BuildContext context) {
    final LocalizationService loc = LocalizationService.instance;
    final Color tone = usage.blocked ? Colors.redAccent : (usage.warned ? Colors.orangeAccent : Colors.greenAccent);

    return Container(
      key: const ValueKey<String>('sms_usage_card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(
          usage.hasLimit ? usage.badge : '${usage.used}',
          key: const ValueKey<String>('sms_usage_badge'),
          style: TextStyle(color: tone, fontSize: 34, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          usage.hasLimit
              ? loc.translateWith('sms_usage_used_of', <Object?>[usage.used, usage.limit])
              : loc.translateWith('sms_usage_used_nolimit', <Object?>[usage.used]),
          style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 15),
        ),
        if (usage.hasLimit) ...<Widget>[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: usage.fraction, minHeight: 10, color: tone, backgroundColor: Colors.white12),
          ),
          const SizedBox(height: 8),
          Text(
            loc.translateWith('sms_usage_remaining', <Object?>[usage.remaining ?? 0]),
            style: TextStyle(color: tone, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          loc.translateWith('sms_usage_week', <Object?>[usage.weekMessages, usage.weekParts]),
          style: const TextStyle(color: ThemeConstants.textSecondary, fontSize: 13),
        ),
        if (usage.blocked || usage.warned) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            loc.translate(usage.blocked ? 'sms_usage_blocked' : 'sms_usage_warned'),
            key: const ValueKey<String>('sms_usage_notice'),
            style: TextStyle(color: tone, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
        if (usage.countedIn == 'parts') ...<Widget>[
          const SizedBox(height: 8),
          Text(loc.translate('sms_usage_counted_parts'), style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
        ],
      ]),
    );
  }
}

/// The business owner: their own counter (from the ⋮ menu).
class OwnerSmsUsageScreen extends StatefulWidget {
  OwnerSmsUsageScreen({super.key, final ApiService? api}) : api = api ?? ApiService();

  final ApiService api;

  @override
  State<OwnerSmsUsageScreen> createState() => _OwnerSmsUsageScreenState();
}

class _OwnerSmsUsageScreenState extends State<OwnerSmsUsageScreen> {
  SmsUsage? _usage;
  String _name = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> res = await widget.api.get('/business/sms-usage');
      final Object? data = res['data'];
      if (!mounted) return;
      setState(() {
        _usage = SmsUsage.maybe(data) ?? const SmsUsage();
        _name = data is Map ? (data['business_name'] ?? '').toString() : '';
        _error = null;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final LocalizationService loc = LocalizationService.instance;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(loc.translate('sms_usage_title')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent))
            else if (_usage == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: ThemeConstants.primaryOrange)))
            else ...<Widget>[
              if (_name.isNotEmpty) ...<Widget>[
                Text(_name, style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
              ],
              SmsUsageCard(usage: _usage!),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Super admin: every business with its counter; tap one for its texts of the last 3 days.
class SmsCountersScreen extends StatefulWidget {
  SmsCountersScreen({super.key, final ApiService? api}) : api = api ?? ApiService();

  final ApiService api;

  @override
  State<SmsCountersScreen> createState() => _SmsCountersScreenState();
}

class _SmsCountersScreenState extends State<SmsCountersScreen> {
  final LocalizationService _loc = LocalizationService.instance;
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

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
      final Map<String, dynamic> res = await widget.api.get('/admin/sms-usage', queryParams: <String, dynamic>{if (q.isNotEmpty) 'q': q});
      final Object? data = res['data'];
      if (!mounted) return;
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

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(_loc.translate('sms_counter_row_title')),
      body: SafeArea(
        child: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              key: const ValueKey<String>('sms_counter_search'),
              controller: _search,
              onChanged: (final String _) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _load);
              },
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
    if (_loading) return const Center(child: CircularProgressIndicator(color: ThemeConstants.primaryOrange));
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: ThemeConstants.textSecondary)));
    if (_items.isEmpty) return Center(child: Text(_loc.translate('sms_admin_empty'), style: const TextStyle(color: ThemeConstants.textSecondary)));
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
    final SmsUsage usage = SmsUsage.maybe(b['usage']) ?? const SmsUsage();
    final Map<String, dynamic> owner = b['owner'] is Map ? Map<String, dynamic>.from(b['owner'] as Map) : <String, dynamic>{};
    final String who = <String>[(owner['name'] ?? '').toString(), (owner['email'] ?? '').toString()].where((final String s) => s.isNotEmpty).join(' · ');
    final Color tone = usage.blocked ? Colors.redAccent : (usage.warned ? Colors.orangeAccent : Colors.greenAccent);

    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        key: ValueKey<String>('sms_counter_business_$id'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text((b['name'] ?? '').toString(), style: const TextStyle(color: ThemeConstants.textPrimary, fontWeight: FontWeight.w600)),
        subtitle: who.isEmpty ? null : Text(who, style: const TextStyle(color: ThemeConstants.textSecondary, fontSize: 12)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: tone.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: tone.withValues(alpha: 0.6))),
          child: Text(
            usage.hasLimit ? usage.badge : '${usage.used} · ${_loc.translate('sms_usage_no_limit')}',
            key: ValueKey<String>('sms_counter_badge_$id'),
            style: TextStyle(color: tone, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SmsCounterDetailScreen(api: widget.api, businessId: id, title: (b['name'] ?? '').toString())));
          if (mounted) await _load();
        },
      ),
    );
  }
}

/// Super admin: one business's counter and the texts it sent in the last 3 days (older ones are cleared; the counter stays).
class SmsCounterDetailScreen extends StatefulWidget {
  const SmsCounterDetailScreen({required this.api, required this.businessId, required this.title, super.key});

  final ApiService api;
  final String businessId;
  final String title;

  @override
  State<SmsCounterDetailScreen> createState() => _SmsCounterDetailScreenState();
}

class _SmsCounterDetailScreenState extends State<SmsCounterDetailScreen> {
  final LocalizationService _loc = LocalizationService.instance;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> res = await widget.api.get('/admin/sms-usage/${widget.businessId}');
      if (!mounted) return;
      setState(() {
        _data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
        _error = null;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final Map<String, dynamic>? d = _data;
    final int days = (d?['log_days'] as num?)?.toInt() ?? 3;
    final List<Map<String, dynamic>> recent = d?['recent'] is List
        ? (d!['recent'] as List).whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(widget.title),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent))
            else if (d == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: ThemeConstants.primaryOrange)))
            else ...<Widget>[
              SmsUsageCard(usage: SmsUsage.maybe(d['usage']) ?? const SmsUsage()),
              const SizedBox(height: 20),
              Text(_loc.translateWith('sms_counter_recent', <Object?>[days]), style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (recent.isEmpty)
                Text(_loc.translateWith('sms_counter_recent_empty', <Object?>[days]), style: const TextStyle(color: ThemeConstants.textSecondary))
              else
                for (final Map<String, dynamic> m in recent) _message(m),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _message(final Map<String, dynamic> m) {
    final DateTime? at = DateTime.tryParse((m['sent_at'] ?? '').toString())?.toLocal();
    return Container(
      key: ValueKey<String>('sms_log_${m['id']}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(
            child: Text(
              _loc.translateWith('sms_counter_to', <Object?>[(m['to'] ?? '').toString()]),
              style: const TextStyle(color: ThemeConstants.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '${at == null ? '' : DateFormat('dd/MM HH:mm').format(at)}  ·  ${_loc.translateWith('sms_counter_parts', <Object?>[(m['parts'] as num?)?.toInt() ?? 1])}',
            style: const TextStyle(color: ThemeConstants.textSecondary, fontSize: 12),
          ),
        ]),
        const SizedBox(height: 6),
        Text((m['message'] ?? '').toString(), style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    );
  }
}
