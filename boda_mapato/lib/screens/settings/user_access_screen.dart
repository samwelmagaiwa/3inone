import 'package:flutter/material.dart';

import '../../constants/theme_constants.dart';
import '../../modules/inventory/screens/widgets/glow_list_card.dart';
import '../../services/api_service.dart';
import '../../services/localization_service.dart';
import '../../utils/server_message.dart';

/// One switch of a person's access: a section or a right, with what the role gives and what the owner did for this person.
class AccessModule {
  AccessModule({required this.key, required this.group, required this.en, required this.sw, required this.fromRole, required this.on}) : initiallyOn = on;

  factory AccessModule.fromJson(final Map<String, dynamic> j) => AccessModule(
        key: '${j['key']}',
        group: '${j['group']}',
        en: '${j['en']}',
        sw: '${j['sw']}',
        fromRole: j['from_role'] == true,
        on: j['on'] == true,
      );

  final String key;
  final String group;
  final String en;
  final String sw;

  /// The role gives it to everybody with that role.
  final bool fromRole;
  bool on;

  /// As it was when the screen loaded (to know whether anything is left to save).
  final bool initiallyOn;

  String name(final bool swahili) => swahili ? sw : en;
}

/// What one person of the business may open, as switches the owner turns on and off. The role starts the list; each switch can be turned
/// off for this person (taking back what the role gave) or on (adding to it), and "Back to the role" puts everything as the role has it.
/// What is off here is off in the menu and refused by the server.
class UserAccessScreen extends StatefulWidget {
  const UserAccessScreen({super.key, required this.user, this.api});

  final Map<String, dynamic> user;

  /// The server calls (a fake in tests).
  final ApiService? api;

  @override
  State<UserAccessScreen> createState() => _UserAccessScreenState();
}

class _UserAccessScreenState extends State<UserAccessScreen> {
  late final ApiService _api = widget.api ?? ApiService();
  final LocalizationService _loc = LocalizationService.instance;

  List<AccessModule>? _modules;
  String? _error;
  bool _saving = false;

  static const List<String> _groups = <String>['goods', 'selling', 'money', 'reports', 'people'];
  static const Color _roleColor = Color(0xFF22C55E);
  static const Color _extraColor = Colors.cyanAccent;
  static const Color _takenColor = Color(0xFFF59E0B);
  static const Color _offColor = Color(0xFF94A3B8);

  String get _id => '${widget.user['id']}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final Map<String, dynamic> res = await _api.getUserAccess(_id);
      final Object? list = (res['data'] as Map?)?['modules'];
      if (!mounted) return;
      setState(() => _modules = <AccessModule>[
            if (list is List)
              for (final Object? m in list)
                if (m is Map) AccessModule.fromJson(Map<String, dynamic>.from(m)),
          ]);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  bool get _changed => _modules?.any((AccessModule m) => m.on != m.initiallyOn) ?? false;

  Future<void> _save() async {
    final List<AccessModule> modules = _modules ?? <AccessModule>[];
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> res = await _api.saveUserAccess(_id, <String>[for (final AccessModule m in modules) if (m.on) m.key]);
      if (res['success'] != true) throw Exception(res['message'] ?? _loc.translate('failed_to_update'));
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, _loc.translate('access_saved'));
      Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _backToRole() => setState(() {
        for (final AccessModule m in _modules ?? <AccessModule>[]) {
          m.on = m.fromRole;
        }
      });

  void _allOn() => setState(() {
        for (final AccessModule m in _modules ?? <AccessModule>[]) {
          m.on = true;
        }
      });

  /// How a switch stands, in words: given by the role, added for this person, taken back, or never allowed.
  ({String text, Color color}) _state(final AccessModule m) {
    if (m.on && m.fromRole) return (text: _loc.translate('access_given_by_role'), color: _roleColor);
    if (m.on) return (text: _loc.translate('access_added'), color: _extraColor);
    if (m.fromRole) return (text: _loc.translate('access_taken_back'), color: _takenColor);

    return (text: _loc.translate('access_not_allowed'), color: _offColor);
  }

  @override
  Widget build(final BuildContext context) {
    final String name = '${widget.user['name'] ?? ''}';
    final String role = '${widget.user['role'] ?? ''}'.replaceAll('_', ' ');
    final List<AccessModule>? modules = _modules;

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: AppBar(
        title: Text(_loc.translate('access_title'), style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: <Widget>[
          if (_saving)
            const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
          else
            TextButton(
              key: const Key('access_save'),
              onPressed: modules == null || !_changed ? null : _save,
              child: Text(_loc.translate('access_save'), style: TextStyle(color: modules == null || !_changed ? Colors.white38 : ThemeConstants.primaryOrange, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: modules == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                        Text(_error!, key: const Key('access_error'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: Text(_loc.translate('retry'))),
                      ]),
                    ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
              children: <Widget>[
                GlowListCard(
                  dividerKey: 'access_head_divider',
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  children: <Widget>[
                    Row(children: <Widget>[
                      CircleAvatar(radius: 22, backgroundColor: ThemeConstants.primaryOrange.withValues(alpha: 0.2), child: Text(name.isEmpty ? 'U' : name[0].toUpperCase(), style: const TextStyle(color: ThemeConstants.primaryOrange, fontWeight: FontWeight.bold, fontSize: 18))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Text(name, style: const TextStyle(color: ThemeConstants.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(role.toUpperCase(), key: const Key('access_role'), style: const TextStyle(color: ThemeConstants.primaryCyan, fontSize: 11, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ]),
                    Text(_loc.translate('access_hint'), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    _summary(modules),
                  ],
                ),
                const SizedBox(height: 12),
                for (final String group in _groups)
                  if (modules.any((AccessModule m) => m.group == group)) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                      child: Center(child: Text(_loc.translate('access_group_$group'), key: Key('access_group_$group'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFFFD166)))),
                    ),
                    GlowListCard(
                      dividerKey: 'access_${group}_divider',
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      children: <Widget>[for (final AccessModule m in modules.where((AccessModule m) => m.group == group)) _row(m)],
                    ),
                  ],
              ],
            ),
    );
  }

  Widget _summary(final List<AccessModule> modules) {
    final int role = modules.where((AccessModule m) => m.on && m.fromRole).length;
    final int extra = modules.where((AccessModule m) => m.on && !m.fromRole).length;
    final int off = modules.where((AccessModule m) => !m.on).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
        _pill('access_count_role', role, _loc.translate('access_from_role'), _roleColor),
        _pill('access_count_extra', extra, _loc.translate('access_extra'), _extraColor),
        _pill('access_count_off', off, _loc.translate('access_off'), _offColor),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 4, children: <Widget>[
        TextButton.icon(key: const Key('access_all_on'), onPressed: off == 0 ? null : _allOn, icon: const Icon(Icons.done_all_rounded, size: 18), label: Text(_loc.translate('access_turn_all_on'))),
        TextButton.icon(key: const Key('access_back_to_role'), onPressed: modules.every((AccessModule m) => m.on == m.fromRole) ? null : _backToRole, icon: const Icon(Icons.restart_alt_rounded, size: 18), label: Text(_loc.translate('access_back_to_role'))),
      ]),
    ]);
  }

  Widget _pill(final String key, final int n, final String label, final Color color) => Container(
        key: Key(key),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.45))),
        child: Text('$n  $label', style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );

  Widget _row(final AccessModule m) {
    final ({String text, Color color}) s = _state(m);

    return InkWell(
      key: Key('access_row_${m.key}'),
      onTap: () => setState(() => m.on = !m.on),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: <Widget>[
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(m.name(_loc.isSwahili), style: TextStyle(color: m.on ? ThemeConstants.textPrimary : Colors.white60, fontSize: 13.5, fontWeight: m.on ? FontWeight.w700 : FontWeight.w500)),
              const SizedBox(height: 2),
              Text(s.text, key: Key('access_state_${m.key}'), style: TextStyle(color: s.color, fontSize: 10.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          Switch(
            key: Key('access_switch_${m.key}'),
            value: m.on,
            onChanged: (bool v) => setState(() => m.on = v),
            activeThumbColor: s.color,
            activeTrackColor: s.color.withValues(alpha: 0.35),
            inactiveThumbColor: _offColor,
            inactiveTrackColor: Colors.white10,
          ),
        ]),
      ),
    );
  }
}
