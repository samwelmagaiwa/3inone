import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'widgets/groups_ui.dart';

/// More: the group's settings, who holds which office, and the activity log -- each shown only to whoever may open it.
class GroupMoreScreen extends StatelessWidget {
  const GroupMoreScreen({required this.me, required this.api, required this.onChanged, super.key});

  final GroupMe me;
  final GroupsApi api;
  final Future<void> Function() onChanged;

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    Widget entry(final Key key, final IconData icon, final String label, final Widget Function() page) => ListTile(
          key: key,
          leading: Icon(icon, color: ThemeConstants.invAccent),
          title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: () async {
            await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => page()));
            await onChanged();
          },
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        GlowListCard(
          dividerKey: 'grp_more_div',
          padding: const EdgeInsets.symmetric(horizontal: 4),
          children: <Widget>[
            if (me.can('manage_settings'))
              entry(const Key('grp_more_settings'), Icons.tune_rounded, sw ? 'Mipangilio ya kikundi' : 'Group settings', () => GroupSettingsScreen(api: api)),
            if (me.can('view_members')) entry(const Key('grp_more_offices'), Icons.workspace_premium_rounded, sw ? 'Viongozi' : 'Officers', () => GroupOfficesScreen(api: api)),
            if (me.can('view_audit')) entry(const Key('grp_more_activity'), Icons.history_rounded, sw ? 'Kumbukumbu za shughuli' : 'Activity log', () => GroupActivityScreen(api: api)),
          ],
        ),
      ],
    );
  }
}

/// The group's own values. A change starts on a day (today unless chosen) and never rewrites what applied before; every change needs a
/// reason and is listed below with who made it.
class GroupSettingsScreen extends StatefulWidget {
  const GroupSettingsScreen({required this.api, super.key});

  final GroupsApi api;

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final TextEditingController _joining = TextEditingController();
  final TextEditingController _shares = TextEditingController();
  final TextEditingController _multiplier = TextEditingController();
  final TextEditingController _prefix = TextEditingController();
  final TextEditingController _instructions = TextEditingController();
  String _sharesFor = 'loans';
  Map<String, dynamic> _current = const <String, dynamic>{};
  List<Map<String, dynamic>> _history = const <Map<String, dynamic>>[];
  DateTime? _from;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_joining, _shares, _multiplier, _prefix, _instructions]) {
      c.dispose();
    }
    super.dispose();
  }

  String _plain(final Object? v) {
    final double? d = double.tryParse('${v ?? ''}');
    return d == null ? '${v ?? ''}' : (d == d.roundToDouble() ? d.toStringAsFixed(0) : '$d');
  }

  void _fill(final Map<String, dynamic> data) {
    final Map<String, dynamic> s = data['settings'] is Map ? Map<String, dynamic>.from(data['settings'] as Map) : <String, dynamic>{};
    _current = s;
    _joining.text = _plain(s['joining_fee']);
    _shares.text = _plain(s['share_amount']);
    _multiplier.text = _plain(s['loan_multiplier']);
    _prefix.text = '${s['member_prefix'] ?? ''}';
    _instructions.text = '${s['payment_instructions'] ?? ''}';
    _sharesFor = '${s['shares_required_for'] ?? 'loans'}';
    _history = <Map<String, dynamic>>[for (final dynamic h in (data['history'] as List? ?? const <dynamic>[])) Map<String, dynamic>.from(h as Map)];
  }

  Future<void> _load() async {
    try {
      final Map<String, dynamic> data = await widget.api.settings();
      if (!mounted) return;
      setState(() {
        _fill(data);
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

  Map<String, dynamic> _changes() {
    final Map<String, dynamic> wanted = <String, dynamic>{
      'joining_fee': _joining.text.trim(),
      'share_amount': _shares.text.trim(),
      'loan_multiplier': _multiplier.text.trim(),
      'member_prefix': _prefix.text.trim().toUpperCase(),
      'payment_instructions': _instructions.text.trim(),
      'shares_required_for': _sharesFor,
    };
    return <String, dynamic>{
      for (final MapEntry<String, dynamic> e in wanted.entries)
        if (_plain(e.value) != _plain(_current[e.key])) e.key: e.value,
    };
  }

  String _label(final bool sw, final String key) => switch (key) {
        'joining_fee' => sw ? 'Ada ya kujiunga' : 'Joining fee',
        'share_amount' => sw ? 'Hisa za mradi' : 'Project shares',
        'loan_multiplier' => sw ? 'Mkopo hadi mara (x akiba)' : 'Loan up to (x savings)',
        'member_prefix' => sw ? 'Mwanzo wa namba ya uanachama' : 'Member number prefix',
        'payment_instructions' => sw ? 'Jinsi ya kulipa' : 'How to pay',
        'shares_required_for' => sw ? 'Hisa zinahitajika kwa' : 'Shares are required for',
        _ => key,
      };

  String _sharesForLabel(final bool sw, final String v) => switch (v) {
        'none' => sw ? 'Hapana' : 'Nothing',
        'loans' => sw ? 'Kukopa' : 'Borrowing',
        'membership' => sw ? 'Uanachama' : 'Membership',
        _ => v,
      };

  Future<void> _save() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final Map<String, dynamic> changes = _changes();
    if (changes.isEmpty) {
      ThemeConstants.showInfoSnackBar(context, sw ? 'Hakuna kilichobadilika.' : 'Nothing changed.');
      return;
    }
    final String from = _from == null ? (sw ? 'leo' : 'today') : dateLabel(_from!.toIso8601String());
    final String? reason = await groupReason(
      context,
      title: sw ? 'Hifadhi mabadiliko?' : 'Save the changes?',
      message: '${changes.keys.map((final String k) => _label(sw, k)).join(', ')}.\n'
          '${sw ? 'Yataanza $from; ya zamani yanabaki kwenye historia. Andika sababu (mfano: uamuzi wa kikao).' : "They start $from; the old values stay in the history. Write the reason (e.g. the meeting's decision)."}',
      yes: sw ? 'Hifadhi' : 'Save',
      tone: GroupTone.positive,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final Map<String, dynamic> data = await widget.api.saveSettings(
        changes,
        reason: reason,
        effectiveFrom: _from == null ? null : '${_from!.year.toString().padLeft(4, '0')}-${_from!.month.toString().padLeft(2, '0')}-${_from!.day.toString().padLeft(2, '0')}',
      );
      if (!mounted) return;
      setState(() {
        _fill(data);
        _busy = false;
        _from = null;
      });
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Mipangilio imehifadhiwa.' : 'Settings saved.');
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Widget _money(final TextEditingController c, final String label, final Key key) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          key: key,
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: const TextStyle(color: Colors.white),
          decoration: ThemeConstants.darkField(label),
        ),
      );

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Mipangilio ya kikundi' : 'Group settings', flat: true),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? GroupEmpty(_error!)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: <Widget>[
                      GlowCard(
                        title: sw ? 'Ada na hisa' : 'Fees and shares',
                        children: <Widget>[
                          _money(_joining, _label(sw, 'joining_fee'), const Key('grp_set_joining')),
                          _money(_shares, _label(sw, 'share_amount'), const Key('grp_set_shares')),
                          Text(_label(sw, 'shares_required_for'), style: const TextStyle(color: Colors.white70)),
                          Wrap(spacing: 8, children: <Widget>[
                            for (final String v in const <String>['none', 'loans', 'membership'])
                              ChoiceChip(
                                key: Key('grp_set_sharesfor_$v'),
                                label: Text(_sharesForLabel(sw, v)),
                                selected: _sharesFor == v,
                                onSelected: (_) => setState(() => _sharesFor = v),
                              ),
                          ]),
                        ],
                      ),
                      GlowCard(
                        title: sw ? 'Mikopo na namba' : 'Loans and numbers',
                        children: <Widget>[
                          _money(_multiplier, _label(sw, 'loan_multiplier'), const Key('grp_set_multiplier')),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: TextField(
                              key: const Key('grp_set_prefix'),
                              controller: _prefix,
                              maxLength: 8,
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(color: Colors.white),
                              decoration: ThemeConstants.darkField(_label(sw, 'member_prefix'), helper: sw ? 'Mfano: MEG → MEG-0001' : 'e.g. MEG → MEG-0001'),
                            ),
                          ),
                        ],
                      ),
                      GlowCard(
                        title: _label(sw, 'payment_instructions'),
                        children: <Widget>[
                          TextField(
                            key: const Key('grp_set_instructions'),
                            controller: _instructions,
                            maxLines: 4,
                            minLines: 2,
                            maxLength: 255,
                            style: const TextStyle(color: Colors.white),
                            decoration: ThemeConstants.darkField(
                              sw ? 'Namba ya M-Pesa, akaunti ya benki ...' : 'M-Pesa number, bank account ...',
                              helper: sw ? 'Wanachama wanaiona wanapolipa.' : 'Members see it when they pay.',
                            ),
                          ),
                        ],
                      ),
                      GlowCard(
                        children: <Widget>[
                          ListTile(
                            key: const Key('grp_set_from'),
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.event_outlined, color: Colors.white54),
                            title: Text(sw ? 'Yanaanza' : 'They start', style: const TextStyle(color: Colors.white70)),
                            trailing: Text(_from == null ? (sw ? 'Leo' : 'Today') : dateLabel(_from!.toIso8601String()), style: const TextStyle(color: Colors.white)),
                            onTap: () async {
                              final DateTime now = DateTime.now();
                              final DateTime? d = await showDatePicker(context: context, initialDate: _from ?? now, firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 3));
                              if (d != null) setState(() => _from = d);
                            },
                          ),
                          FilledButton.icon(
                            key: const Key('grp_set_save'),
                            style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
                            onPressed: _busy ? null : _save,
                            icon: const Icon(Icons.save_rounded),
                            label: Text(sw ? 'Hifadhi' : 'Save'),
                          ),
                        ],
                      ),
                      if (_history.isNotEmpty)
                        GlowCard(
                          title: sw ? 'Historia ya mabadiliko' : 'History of changes',
                          children: <Widget>[
                            for (final Map<String, dynamic> h in _history)
                              Text(
                                '${dateLabel('${h['effective_from']}')} · ${_label(sw, '${h['key']}')}: '
                                '${h['key'] == 'shares_required_for' ? _sharesForLabel(sw, '${h['value']}') : _plain(h['value'])}'
                                '${h['reason'] == null ? '' : ' · ${h['reason']}'}${h['changed_by_name'] == null ? '' : ' · ${h['changed_by_name']}'}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                          ],
                        ),
                    ],
                  ),
      ),
    );
  }
}

/// Who holds each office now, with what the office is for.
class GroupOfficesScreen extends StatefulWidget {
  const GroupOfficesScreen({required this.api, super.key});

  final GroupsApi api;

  @override
  State<GroupOfficesScreen> createState() => _GroupOfficesScreenState();
}

class _GroupOfficesScreenState extends State<GroupOfficesScreen> {
  List<GroupMember> _holders = const <GroupMember>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final GroupMemberPage page = await widget.api.members(office: 'any');
      if (mounted) {
        setState(() {
          _holders = page.members;
          _loading = false;
        });
      }
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
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Viongozi' : 'Officers', flat: true),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? GroupEmpty(_error!)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: <Widget>[
                      GlowListCard(
                        dividerKey: 'grp_offices_div',
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        children: <Widget>[
                          for (final String o in groupOffices)
                            ListTile(
                              key: Key('grp_office_$o'),
                              title: Text(officeLabel(sw: sw, office: o), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                              subtitle: Text(officeDuty(sw: sw, office: o), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                              trailing: Text(
                                _holders.where((final GroupMember m) => m.office == o).map((final GroupMember m) => m.fullName).join('\n').ifEmpty(sw ? 'Wazi' : 'Vacant'),
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  color: _holders.any((final GroupMember m) => m.office == o) ? Colors.white : ThemeConstants.warningAmber,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(final String other) => isEmpty ? other : this;
}

/// The group's activity log: who did what, newest first, a page at a time.
class GroupActivityScreen extends StatefulWidget {
  const GroupActivityScreen({required this.api, super.key});

  final GroupsApi api;

  @override
  State<GroupActivityScreen> createState() => _GroupActivityScreenState();
}

class _GroupActivityScreenState extends State<GroupActivityScreen> {
  final List<Map<String, dynamic>> _entries = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({final bool more = false}) async {
    setState(() => _loading = true);
    try {
      final int? before = more && _entries.isNotEmpty ? (_entries.last['id'] as num?)?.toInt() : null;
      final List<Map<String, dynamic>> got = await widget.api.activity(before: before);
      if (!mounted) return;
      setState(() {
        if (!more) _entries.clear();
        _entries.addAll(got);
        _hasMore = got.length >= 50;
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
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Kumbukumbu za shughuli' : 'Activity log', flat: true),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: <Widget>[
              if (_error != null) GroupEmpty(_error!),
              if (!_loading && _error == null && _entries.isEmpty) GroupEmpty(sw ? 'Bado hakuna shughuli.' : 'Nothing done yet.'),
              if (_entries.isNotEmpty)
                GlowListCard(
                  dividerKey: 'grp_activity_div',
                  children: <Widget>[
                    for (final Map<String, dynamic> e in _entries)
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        Text(activityLabel(sw: sw, action: '${e['action'] ?? ''}'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        Text('${e['summary'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text('${dateLabel('${e['created_at'] ?? ''}')} · ${e['by_name'] ?? '-'}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ]),
                  ],
                ),
              if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              if (_hasMore && !_loading)
                TextButton(
                  onPressed: () => _load(more: true),
                  child: Text(LocalizationService.instance.translate('list_show_more'), style: const TextStyle(color: ThemeConstants.primaryOrange)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
