import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../models/group_records_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'widgets/groups_ui.dart';

/// Invitations: one's own code to share (whoever applies with it is linked to you), and -- for whoever registers members -- the group's codes.
class InviteScreen extends StatefulWidget {
  const InviteScreen({required this.api, required this.me, super.key});

  final GroupsApi api;
  final GroupMe me;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  GroupInvitation? _mine;
  List<GroupInvitation> _group = const <GroupInvitation>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final (GroupInvitation?, List<GroupInvitation>) got = await widget.api.invitations();
      if (mounted) {
        setState(() {
          _mine = got.$1;
          _group = got.$2;
          _loading = false;
          _error = null;
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

  String _message(final bool sw, final String code) => sw
      ? 'Karibu ujiunge na ${widget.me.groupName ?? 'kikundi chetu'}. Fungua programu ya 3inone, chagua "Jiunge na kikundi" na uweke namba hii: $code'
      : 'Join ${widget.me.groupName ?? 'our group'}. Open the 3inone app, choose "Join a group" and enter this code: $code';

  Future<void> _stop(final GroupInvitation i) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Sitisha namba hii?' : 'Stop this code?',
      message: sw ? '${i.code} haitafanya kazi tena.' : '${i.code} will no longer work.',
      yes: sw ? 'Sitisha' : 'Stop',
      tone: GroupTone.danger,
    );
    if (!ok) return;
    try {
      await widget.api.stopCode(i.id);
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _newGroupCode() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Namba mpya ya kikundi?' : 'A new group code?',
      message: sw ? 'Kwa tangazo au kikao: atakayejiunga nayo hatakuwa na aliyemleta.' : 'For a poster or a meeting: whoever applies with it has no referrer.',
      yes: sw ? 'Tengeneza' : 'Make it',
      tone: GroupTone.positive,
    );
    if (!ok) return;
    try {
      await widget.api.newGroupCode();
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Widget _codeCard(final bool sw, final GroupInvitation i, {required final String title}) => GlowCard(
        key: Key('grp_code_${i.id}'),
        title: title,
        children: <Widget>[
          Center(
            child: SelectableText(i.code, key: Key('grp_code_text_${i.kind}'), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4)),
          ),
          Center(child: Text('${sw ? 'Imetumika mara' : 'Used'} ${i.used}${sw ? '' : ' time(s)'}', style: const TextStyle(color: Colors.white54, fontSize: 12))),
          Row(children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: i.code));
                  if (mounted) ThemeConstants.showSuccessSnackBar(context, sw ? 'Imenakiliwa.' : 'Copied.');
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text(sw ? 'Nakili' : 'Copy'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: Key('grp_code_share_${i.kind}'),
                style: FilledButton.styleFrom(backgroundColor: ThemeConstants.primaryOrange),
                onPressed: () => Share.share(_message(sw, i.code)),
                icon: const Icon(Icons.share_rounded),
                label: Text(sw ? 'Tuma' : 'Share'),
              ),
            ),
          ]),
          TextButton(
            key: Key('grp_code_stop_${i.id}'),
            onPressed: () => _stop(i),
            child: Text(sw ? 'Sitisha namba hii' : 'Stop this code', style: const TextStyle(color: ThemeConstants.errorText)),
          ),
        ],
      );

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Alika mwanachama' : 'Invite a member', flat: true),
      floatingActionButton: widget.me.can('manage_members')
          ? FloatingActionButton.extended(
              key: const Key('grp_group_code_new'),
              backgroundColor: ThemeConstants.primaryOrange,
              foregroundColor: Colors.white,
              onPressed: _newGroupCode,
              icon: const Icon(Icons.qr_code_rounded),
              label: Text(sw ? 'Namba ya kikundi' : 'Group code'),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: joinGlowCards(<Widget>[
                  if (_error != null) GroupEmpty(_error!),
                  if (_mine != null) _codeCard(sw, _mine!, title: sw ? 'Namba yangu ya mwaliko' : 'My invitation code'),
                  for (final GroupInvitation g in _group.where((final GroupInvitation g) => g.active)) _codeCard(sw, g, title: sw ? 'Namba ya kikundi' : 'Group code'),
                ])),
              ),
      ),
    );
  }
}

/// Who brought whom: the whole tree for officers (with a search), one's own branch for a member.
class ReferralTreeScreen extends StatefulWidget {
  const ReferralTreeScreen({required this.api, required this.whole, super.key});

  final GroupsApi api;

  /// The whole group (officers) or one's own branch.
  final bool whole;

  @override
  State<ReferralTreeScreen> createState() => _ReferralTreeScreenState();
}

class _ReferralTreeScreenState extends State<ReferralTreeScreen> {
  List<GroupTreeNode> _nodes = const <GroupTreeNode>[];
  int? _root;
  bool _loading = true;
  String _q = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      if (widget.whole) {
        final List<GroupTreeNode> n = await widget.api.tree();
        if (mounted) setState(() => _nodes = n);
      } else {
        final (List<GroupTreeNode>, int?) b = await widget.api.myBranch();
        if (mounted) {
          setState(() {
            _nodes = b.$1;
            _root = b.$2;
          });
        }
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  /// How many someone brought in, and how many those brought in, all the way down.
  int _descendants(final int id, final Map<int, List<GroupTreeNode>> children) {
    int n = 0;
    for (final GroupTreeNode c in children[id] ?? const <GroupTreeNode>[]) {
      n += 1 + _descendants(c.id, children);
    }
    return n;
  }

  Widget _node(final GroupTreeNode n, final Map<int, List<GroupTreeNode>> children, final bool sw, final int depth) {
    final List<GroupTreeNode> kids = children[n.id] ?? const <GroupTreeNode>[];
    final Widget title = Text('${n.name}${n.memberNumber == null ? '' : ' · ${n.memberNumber}'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600));
    final Widget subtitle = Text(
      <String>[
        statusLabel(sw: sw, status: n.status),
        if (n.office != null) officeLabel(sw: sw, office: n.office),
        if (kids.isNotEmpty) '${sw ? 'Aliowaleta' : 'Brought in'} ${kids.length} · ${sw ? 'jumla' : 'in all'} ${_descendants(n.id, children)}',
      ].join(' · '),
      style: const TextStyle(color: Colors.white60, fontSize: 12),
    );
    if (kids.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: 16.0 * depth),
        child: ListTile(key: Key('grp_tree_${n.id}'), dense: true, leading: Icon(Icons.person_rounded, color: statusColor(n.status)), title: title, subtitle: subtitle),
      );
    }
    return Padding(
      padding: EdgeInsets.only(left: 16.0 * depth),
      child: ExpansionTile(
        key: Key('grp_tree_${n.id}'),
        initiallyExpanded: depth < 1,
        iconColor: Colors.white70,
        collapsedIconColor: Colors.white54,
        leading: Icon(Icons.account_tree_rounded, color: statusColor(n.status)),
        title: title,
        subtitle: subtitle,
        children: <Widget>[for (final GroupTreeNode k in kids) _node(k, children, sw, depth + 1)],
      ),
    );
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final Map<int, List<GroupTreeNode>> children = <int, List<GroupTreeNode>>{};
    final Set<int> ids = _nodes.map((final GroupTreeNode n) => n.id).toSet();
    for (final GroupTreeNode n in _nodes) {
      if (n.referrerId != null && ids.contains(n.referrerId)) children.putIfAbsent(n.referrerId!, () => <GroupTreeNode>[]).add(n);
    }
    final List<GroupTreeNode> roots = _root != null
        ? _nodes.where((final GroupTreeNode n) => n.id == _root).toList()
        : _nodes.where((final GroupTreeNode n) => n.referrerId == null || !ids.contains(n.referrerId)).toList();
    final String q = _q.trim().toLowerCase();
    final List<GroupTreeNode> found = q.isEmpty
        ? const <GroupTreeNode>[]
        : _nodes.where((final GroupTreeNode n) => n.name.toLowerCase().contains(q) || (n.memberNumber ?? '').toLowerCase().contains(q)).toList();
    final Map<int, GroupTreeNode> byId = <int, GroupTreeNode>{for (final GroupTreeNode n in _nodes) n.id: n};
    String path(final GroupTreeNode n) {
      final List<String> names = <String>[n.name];
      GroupTreeNode? at = n;
      for (int i = 0; i < 30 && at?.referrerId != null && byId[at!.referrerId] != null; i++) {
        at = byId[at.referrerId];
        names.insert(0, at!.name);
      }
      return names.join(' → ');
    }

    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(widget.whole ? (sw ? 'Mti wa uanachama' : 'Membership tree') : (sw ? 'Niliowaleta' : 'Whom I brought in'), flat: true),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: joinGlowCards(<Widget>[
                if (widget.whole)
                  TextField(
                    key: const Key('grp_tree_search'),
                    onChanged: (final String v) => setState(() => _q = v),
                    style: const TextStyle(color: Colors.white),
                    decoration: ThemeConstants.darkField(sw ? 'Tafuta jina au namba' : 'Search name or number', prefix: const Icon(Icons.search, color: Colors.white54)),
                  ),
                const SizedBox(height: 10),
                if (_error != null) GroupEmpty(_error!),
                if (found.isNotEmpty)
                  GlowCard(title: sw ? 'Njia ya uanachama' : 'Path in the tree', children: <Widget>[
                    for (final GroupTreeNode n in found.take(10)) Text(path(n), key: Key('grp_tree_path_${n.id}'), style: const TextStyle(color: Colors.white)),
                  ]),
                if (_nodes.isEmpty && _error == null) GroupEmpty(sw ? 'Hakuna bado.' : 'Nobody yet.'),
                if (roots.isNotEmpty)
                  GlowListCard(
                    dividerKey: 'grp_tree_div',
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    children: <Widget>[for (final GroupTreeNode r in roots) Material(type: MaterialType.transparency, child: _node(r, children, sw, 0))],
                  ),
              ])),
      ),
    );
  }
}

/// The group in numbers for a period, and the exports (the member register, the period's payments) to share.
class GroupReportsScreen extends StatefulWidget {
  const GroupReportsScreen({required this.api, required this.me, super.key});

  final GroupsApi api;
  final GroupMe me;

  @override
  State<GroupReportsScreen> createState() => _GroupReportsScreenState();
}

class _GroupReportsScreenState extends State<GroupReportsScreen> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _to = DateTime.now();
  GroupReport? _r;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String _iso(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final GroupReport r = await widget.api.report(from: _iso(_from), to: _iso(_to));
      if (mounted) {
        setState(() {
          _r = r;
          _loading = false;
          _error = null;
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

  /// Fetch a CSV, keep it for a moment and hand it to the phone's share sheet (WhatsApp, email, Drive ...).
  Future<void> _export(final Future<Uint8List> Function() fetch, final String name) async {
    try {
      final Uint8List bytes = await fetch();
      final Directory dir = await getTemporaryDirectory();
      final File file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(<XFile>[XFile(file.path, mimeType: 'text/csv')], subject: name);
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupReport? r = _r;
    Widget date(final String label, final DateTime value, final ValueChanged<DateTime> set, final Key key) => Expanded(
          child: ListTile(
            key: key,
            contentPadding: EdgeInsets.zero,
            title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            subtitle: Text(dateLabel(_iso(value)), style: const TextStyle(color: Colors.white)),
            onTap: () async {
              final DateTime? d = await showDatePicker(context: context, initialDate: value, firstDate: DateTime(2015), lastDate: DateTime.now());
              if (d != null) {
                setState(() => set(d));
                await _load();
              }
            },
          ),
        );
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Ripoti za kikundi' : 'Group reports', flat: true),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: joinGlowCards(<Widget>[
          Row(children: <Widget>[
            date(sw ? 'Kuanzia' : 'From', _from, (final DateTime d) => _from = d, const Key('grp_rep_from')),
            date(sw ? 'Hadi' : 'To', _to, (final DateTime d) => _to = d, const Key('grp_rep_to')),
          ]),
          if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_error != null) GroupEmpty(_error!),
          if (r != null && !_loading) ...<Widget>[
            GlowCard(title: sw ? 'Wanachama' : 'Members', children: <Widget>[
              for (final MapEntry<String, int> e in r.byStatus.entries)
                if (e.value > 0) GroupDetailRow(statusLabel(sw: sw, status: e.key), '${e.value}'),
              GroupDetailRow(sw ? 'Waliojiunga katika kipindi' : 'Joined in the period', '${r.joined}'),
              GroupDetailRow(sw ? 'Vikao vilivyofanyika' : 'Meetings held', '${r.meetingsHeld}'),
            ]),
            GlowCard(title: sw ? 'Fedha (zilizothibitishwa)' : 'Money (verified)', children: <Widget>[
              if (r.money.isEmpty) Text(sw ? 'Hakuna katika kipindi hiki.' : 'Nothing in this period.', style: const TextStyle(color: Colors.white60)),
              for (final MapEntry<String, (double, double)> e in r.money.entries)
                GroupDetailRow(
                  categoryLabel(sw: sw, category: e.key),
                  '${e.value.$1 > 0 ? '+${tsh(e.value.$1)}' : ''}${e.value.$1 > 0 && e.value.$2 > 0 ? '  ' : ''}${e.value.$2 > 0 ? '−${tsh(e.value.$2)}' : ''}',
                ),
            ]),
            GlowCard(title: sw ? 'Michango' : 'Contributions', children: <Widget>[
              GroupDetailRow(sw ? 'Iliyotarajiwa' : 'Expected', tsh(r.contributions['expected'] ?? 0)),
              GroupDetailRow(sw ? 'Iliyolipwa' : 'Collected', tsh(r.contributions['collected'] ?? 0), valueColor: ThemeConstants.successGreen),
              GroupDetailRow(sw ? 'Iliyopita muda (sasa)' : 'Overdue (now)', '${tsh(r.contributions['overdue_now'] ?? 0)} · ${(r.contributions['overdue_members'] ?? 0).toStringAsFixed(0)}',
                  valueColor: (r.contributions['overdue_now'] ?? 0) > 0 ? ThemeConstants.errorText : null),
            ]),
            GlowCard(title: sw ? 'Mikopo (sasa)' : 'Loans (now)', children: <Widget>[
              GroupDetailRow(sw ? 'Msingi unaodaiwa' : 'Principal owed', tsh(r.loans['principal'] ?? 0)),
              GroupDetailRow(sw ? 'Riba inayodaiwa' : 'Interest owed', tsh(r.loans['interest'] ?? 0)),
              GroupDetailRow(sw ? 'Imepita muda' : 'Overdue', tsh(r.loans['arrears'] ?? 0), valueColor: (r.loans['arrears'] ?? 0) > 0 ? ThemeConstants.errorText : null),
            ]),
          ],
          const SizedBox(height: 8),
          if (widget.me.can('view_members'))
            OutlinedButton.icon(
              key: const Key('grp_export_members'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: () => _export(widget.api.exportMembers, 'wanachama.csv'),
              icon: const Icon(Icons.table_view_rounded),
              label: Text(sw ? 'Daftari la wanachama (CSV)' : 'Member register (CSV)'),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('grp_export_payments'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), padding: const EdgeInsets.symmetric(vertical: 12)),
            onPressed: () => _export(() => widget.api.exportPayments(from: _iso(_from), to: _iso(_to)), 'malipo_${_iso(_from)}_${_iso(_to)}.csv'),
            icon: const Icon(Icons.receipt_long_rounded),
            label: Text(sw ? 'Malipo ya kipindi (CSV)' : 'Payments of the period (CSV)'),
          ),
        ])),
      ),
    );
  }
}
