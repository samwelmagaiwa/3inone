import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../../../utils/server_message.dart';
import '../../services/salon_api.dart';
import 'salon_input.dart';
import '../widgets/inventory_widgets.dart';

/// Vouchers and bulk texts to groups of clients, side by side.
class OffersHubScreen extends StatelessWidget {
  const OffersHubScreen({super.key, this.api});

  final SalonApi? api;

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return InvTabScaffold(
      title: '',
      tabs: <String>[sw ? 'Kuponi' : 'Vouchers', sw ? 'Ujumbe' : 'Messages'],
      views: <Widget>[VouchersScreen(api: api), CampaignsScreen(api: api)],
    );
  }
}

/// Voucher codes a client gives at the till: a percent or an amount off, optional expiry and use limit. One that was
/// used is switched off, never deleted.
class VouchersScreen extends StatefulWidget {
  const VouchersScreen({super.key, this.api});

  final SalonApi? api;

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Map<String, dynamic>> r = await _api.vouchers();
      if (!mounted) return;
      setState(() {
        _rows = r;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _run(final Future<void> Function() action) async {
    try {
      await action();
      if (mounted) await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _add() async {
    final Map<String, dynamic>? got = await showDialog<Map<String, dynamic>>(context: context, builder: (BuildContext d) => const _VoucherDialog());
    if (got == null || !mounted) return;
    await _run(() => _api.saveVoucher(got));
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(key: const Key('voucher_add'), onPressed: _add, icon: const Icon(Icons.add), label: Text(sw ? 'Kuponi mpya' : 'New voucher')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: <Widget>[
                    for (final Map<String, dynamic> v in _rows)
                      Card(
                        key: Key('voucher_${v['id']}'),
                        child: ListTile(
                          title: Text('${v['code']}  ·  ${v['kind'] == 'percent' ? '${v['value']}%' : 'TSH ${v['value']}'}'),
                          subtitle: Text(<String>[
                            '${sw ? 'Imetumika' : 'Used'}: ${v['used_count']}${v['max_uses'] == null ? '' : '/${v['max_uses']}'}',
                            if (v['expires_on'] != null) '${sw ? 'Mwisho' : 'Expires'}: ${v['expires_on']}',
                            if (v['usable'] != true) (sw ? 'Haitumiki' : 'Not usable'),
                          ].join(' · ')),
                          trailing: Switch(
                            key: Key('voucher_switch_${v['id']}'),
                            value: v['active'] == true,
                            onChanged: (bool on) => _run(() => _api.saveVoucher(<String, dynamic>{'active': on}, id: (v['id'] as num).toInt())),
                          ),
                          onLongPress: () => _run(() => _api.deleteVoucher((v['id'] as num).toInt())),
                        ),
                      ),
                    if (_rows.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(sw ? 'Hakuna kuponi bado.' : 'No vouchers yet.', textAlign: TextAlign.center)),
                  ]),
                ),
    );
  }
}

class _VoucherDialog extends StatefulWidget {
  const _VoucherDialog();

  @override
  State<_VoucherDialog> createState() => _VoucherDialogState();
}

class _VoucherDialogState extends State<_VoucherDialog> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _uses = TextEditingController();
  String _kind = 'percent';
  String? _problem;

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _uses.dispose();
    super.dispose();
  }

  void _save(final bool sw) {
    final String code = _code.text.trim().toUpperCase();
    final double value = double.tryParse(_value.text.trim()) ?? 0;
    if (!RegExp(r'^[A-Z0-9_-]{3,40}$').hasMatch(code)) return setState(() => _problem = sw ? 'Msimbo: herufi au namba 3 au zaidi.' : 'Code: at least 3 letters or numbers.');
    if (value <= 0) return setState(() => _problem = sw ? 'Weka kiasi.' : 'Enter an amount.');
    if (_kind == 'percent' && value > 100) return setState(() => _problem = sw ? 'Asilimia isizidi 100.' : 'A percent cannot be more than 100.');
    Navigator.pop(context, <String, dynamic>{'code': code, 'kind': _kind, 'value': value, if (int.tryParse(_uses.text.trim()) != null) 'max_uses': int.parse(_uses.text.trim())});
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;

    return AlertDialog(
      title: Text(sw ? 'Kuponi mpya' : 'New voucher'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(style: salonInputStyle, key: const Key('voucher_code'), controller: _code, textCapitalization: TextCapitalization.characters, decoration: salonInput(labelText: sw ? 'Msimbo' : 'Code')),
          SegmentedButton<String>(
            segments: <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'percent', label: Text(sw ? 'Asilimia' : 'Percent')),
              ButtonSegment<String>(value: 'amount', label: Text(sw ? 'Kiasi' : 'Amount')),
            ],
            selected: <String>{_kind},
            onSelectionChanged: (Set<String> s) => setState(() => _kind = s.first),
          ),
          TextField(style: salonInputStyle, key: const Key('voucher_value'), controller: _value, keyboardType: TextInputType.number, decoration: salonInput(labelText: sw ? 'Thamani' : 'Value')),
          TextField(style: salonInputStyle, key: const Key('voucher_uses'), controller: _uses, keyboardType: TextInputType.number, decoration: salonInput(labelText: sw ? 'Mara za kutumika (si lazima)' : 'Times it can be used (optional)')),
          if (_problem != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problem!, style: TextStyle(color: ThemeConstants.errorText))),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel')),
        FilledButton(key: const Key('voucher_save'), onPressed: () => _save(sw), child: Text(sw ? 'Hifadhi' : 'Save')),
      ],
    );
  }
}

/// A text to a group of clients (all, new, returning, away a while, birthday this month, top spenders). The page shows
/// how many are in the group and how many can actually be texted before anything is sent.
class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key, this.api});

  final SalonApi? api;

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  late final SalonApi _api = widget.api ?? SalonApi();
  Map<String, dynamic> _data = <String, dynamic>{};
  final TextEditingController _message = TextEditingController();
  String _segment = 'all';
  String? _error;
  bool _loading = true;
  bool _busy = false;

  List<Map<String, dynamic>> _list(final dynamic v) => <Map<String, dynamic>>[
        if (v is List)
          for (final dynamic r in v)
            if (r is Map) Map<String, dynamic>.from(r),
      ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> d = await _api.campaigns();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = readableErrorMessage(e);
        _loading = false;
      });
    }
  }

  static String label(final String s, final bool sw) {
    switch (s) {
      case 'all':
        return sw ? 'Wote' : 'Everyone';
      case 'new':
        return sw ? 'Wapya' : 'New';
      case 'returning':
        return sw ? 'Wanaorudi' : 'Returning';
      case 'inactive':
        return sw ? 'Hawajaja muda' : 'Away a while';
      case 'birthday_month':
        return sw ? 'Kuzaliwa mwezi huu' : 'Birthday this month';
      default:
        return sw ? 'Wanaotumia zaidi' : 'Top spenders';
    }
  }

  Future<void> _send() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final String text = _message.text.trim();
    if (text.length < 5) return ThemeConstants.showErrorSnackBar(context, sw ? 'Andika ujumbe (herufi 5 au zaidi).' : 'Write a message (5 letters or more).');
    setState(() => _busy = true);
    try {
      await _api.sendCampaign(segment: _segment, message: text);
      if (!mounted) return;
      _message.clear();
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Ujumbe umetumwa' : 'Messages sent');
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final List<Map<String, dynamic>> segments = _list(_data['segments']);
    final Map<String, dynamic> current = segments.firstWhere((Map<String, dynamic> s) => s['segment'] == _segment, orElse: () => <String, dynamic>{});

    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(_error!))
            : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                Wrap(spacing: 8, children: <Widget>[
                  for (final Map<String, dynamic> s in segments)
                    ChoiceChip(
                      key: Key('seg_${s['segment']}'),
                      label: Text('${label('${s['segment']}', sw)} (${s['members']})'),
                      selected: _segment == s['segment'],
                      onSelected: (_) => setState(() => _segment = '${s['segment']}'),
                    ),
                ]),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(sw ? 'Wanaoweza kutumiwa ujumbe: ${current['reachable'] ?? 0}' : 'Can be texted: ${current['reachable'] ?? 0}', key: const Key('seg_reach')),
                ),
                TextField(style: salonInputStyle, key: const Key('camp_message'), controller: _message, maxLength: 320, minLines: 3, maxLines: 5, decoration: salonInput(labelText: sw ? 'Ujumbe' : 'Message')),
                FilledButton.icon(key: const Key('camp_send'), onPressed: _busy ? null : _send, icon: const Icon(Icons.send), label: Text(sw ? 'Tuma' : 'Send')),
                const SizedBox(height: 16),
                Text(sw ? 'Zilizotumwa' : 'Sent', style: const TextStyle(fontWeight: FontWeight.bold)),
                for (final Map<String, dynamic> c in _list(_data['campaigns']))
                  ListTile(dense: true, title: Text('${c['message']}', maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text('${c['at']} · ${c['sent']}/${c['recipients']}')),
              ]);
  }
}
