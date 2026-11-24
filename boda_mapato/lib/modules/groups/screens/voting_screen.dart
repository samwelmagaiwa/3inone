import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../../widgets/scrolling_chip_row.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../models/group_voting_models.dart';
import '../services/groups_api.dart';
import 'voting_common.dart';
import 'voting_detail_screen.dart';
import 'voting_form_screen.dart';
import 'widgets/groups_ui.dart';

/// The Voting Dashboard. Three views: every voting (filtered as Active, Upcoming, Waiting for my vote, Completed or Closed), My voting activity (what
/// I have voted in and what still waits for me) and, for leaders who run votings, Manage. Votings are grouped under their own series or kind so
/// one process is never mistaken for another; each row says exactly what is voted on and where the member stands in it.
class VotingScreen extends StatefulWidget {
  const VotingScreen({required this.me, required this.api, required this.onChanged, super.key});

  final GroupMe me;
  final GroupsApi api;
  final Future<void> Function() onChanged;

  @override
  State<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen> {
  List<GroupVoting> _all = const <GroupVoting>[];
  String _tab = 'all';
  String? _bucket;
  bool _loading = true;
  String? _error;
  int _unread = 0;

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
      final List<GroupVoting> rows = await widget.api.votings();
      int unread = 0;
      try {
        unread = (await widget.api.notifications()).$2;
      } on Exception {
        // the dashboard still works without the bell
      }
      if (mounted) {
        setState(() {
          _all = rows;
          _unread = unread;
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

  Future<void> _open(final GroupVoting v) async {
    final Object? changed = await Navigator.push<Object>(context, MaterialPageRoute<Object>(builder: (_) => VotingDetailScreen(api: widget.api, me: widget.me, votingId: v.id)));
    await _load();
    if (changed != null) await widget.onChanged();
  }

  Future<void> _create() async {
    final GroupVoting? made = await Navigator.push<GroupVoting>(context, MaterialPageRoute<GroupVoting>(builder: (_) => VotingFormScreen(api: widget.api)));
    if (made != null) await _load();
  }

  Future<void> _notices() async {
    await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => VotingNoticesScreen(api: widget.api, me: widget.me)));
    await _load();
  }

  bool get _manage => widget.me.can('manage_votings');

  List<GroupVoting> _visible() {
    switch (_tab) {
      case 'mine':
        final List<GroupVoting> mine = _all.where((final GroupVoting v) => v.my.state == 'voted' || (v.my.state == 'pending')).toList();
        return _bucket == null ? mine : mine.where((final GroupVoting v) => _bucket == 'voted' ? v.my.state == 'voted' : v.my.state == 'pending').toList();
      case 'manage':
        return _all;
      default:
        final List<GroupVoting> live = _all.where((final GroupVoting v) => v.status != 'draft').toList();
        return _bucket == null ? live : live.where((final GroupVoting v) => v.buckets.contains(_bucket)).toList();
    }
  }

  /// The group a voting is shown under: its series, or its kind of matter.
  String _groupOf(final GroupVoting v, final bool sw) => (v.series != null && v.series!.isNotEmpty) ? v.series! : votingCategoryLabel(sw: sw, category: v.category);

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final List<GroupVoting> rows = _visible();
    final Map<String, List<GroupVoting>> groups = <String, List<GroupVoting>>{};
    for (final GroupVoting v in rows) {
      groups.putIfAbsent(_tab == 'manage' ? votingStatusLabel(sw: sw, status: v.status) : _groupOf(v, sw), () => <GroupVoting>[]).add(v);
    }
    final List<(String?, String)> chips = _tab == 'mine'
        ? <(String?, String)>[(null, sw ? 'Zote' : 'All'), ('pending', sw ? 'Zinazonisubiri' : 'Waiting for me'), ('voted', sw ? 'Nimepiga' : 'I voted')]
        : <(String?, String)>[
            (null, sw ? 'Zote' : 'All'),
            ('active', sw ? 'Zinaendelea' : 'Active'),
            ('upcoming', sw ? 'Zinakuja' : 'Upcoming'),
            ('pending', sw ? 'Zinazosubiri kura yangu' : 'Waiting for my vote'),
            ('completed', sw ? 'Zilizokamilika' : 'Completed'),
            ('closed', sw ? 'Zilizofungwa' : 'Closed'),
          ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: joinGlowCards(<Widget>[
          Row(children: <Widget>[
            Expanded(
              child: SegmentedButton<String>(
                key: const Key('grp_vote_tabs'),
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'all', label: Text(sw ? 'Kura' : 'Voting'), icon: const Icon(Icons.how_to_vote_rounded)),
                  ButtonSegment<String>(value: 'mine', label: Text(sw ? 'Zangu' : 'Mine'), icon: const Icon(Icons.person_rounded)),
                  if (_manage) ButtonSegment<String>(value: 'manage', label: Text(sw ? 'Simamia' : 'Manage'), icon: const Icon(Icons.settings_rounded)),
                ],
                selected: <String>{_tab},
                onSelectionChanged: (final Set<String> v) => setState(() {
                  _tab = v.first;
                  _bucket = null;
                }),
              ),
            ),
            const SizedBox(width: 6),
            Badge(
              isLabelVisible: _unread > 0,
              label: Text('$_unread'),
              child: IconButton(key: const Key('grp_vote_bell'), tooltip: sw ? 'Taarifa' : 'Notifications', onPressed: _notices, icon: const Icon(Icons.notifications_rounded, color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 10),
          if (_tab != 'manage')
            ScrollingChipRow(
              padding: EdgeInsets.zero,
              children: <Widget>[
                for (final (String?, String) c in chips) ScrollChoiceChip(chipKey: Key('grp_vote_filter_${c.$1 ?? 'all'}'), label: c.$2, selected: _bucket == c.$1, onSelected: (_) => setState(() => _bucket = c.$1)),
              ],
            ),
          if (_tab == 'manage')
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('grp_vote_new'),
                style: FilledButton.styleFrom(backgroundColor: ThemeConstants.primaryOrange, padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: Text(sw ? 'Kura mpya' : 'New voting'),
              ),
            ),
          const SizedBox(height: 10),
          if (_error != null) GroupEmpty(_error!),
          if (_loading && _all.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (!_loading && _error == null && rows.isEmpty) GroupEmpty(_tab == 'mine' ? (sw ? 'Hakuna kura kwako kwa sasa.' : 'Nothing for you to vote in right now.') : (sw ? 'Hakuna kura hapa.' : 'No votings here.')),
          for (final MapEntry<String, List<GroupVoting>> g in groups.entries)
            GlowCard(
              title: g.key,
              dividerKey: 'grp_vote_group_div',
              children: <Widget>[for (final GroupVoting v in g.value) _row(v, sw)],
            ),
        ]),
      ),
    );
  }

  /// One voting: what exactly is voted on, who stands, when, its status and where the member stands.
  Widget _row(final GroupVoting v, final bool sw) {
    final String my = votingMyLabel(sw: sw, state: v.my.state);
    // A position names its candidates; an agenda says it is an agenda (and its kind of matter when it sits under a named series).
    final String who = v.isElection
        ? v.options.take(3).map((final VotingOption o) => o.label).join(' · ') + (v.options.length > 3 ? ' +${v.options.length - 3}' : '')
        : ((v.series != null && v.series!.isNotEmpty) ? '${sw ? 'Ajenda' : 'Agenda'} · ${votingCategoryLabel(sw: sw, category: v.category)}' : (sw ? 'Ajenda' : 'Agenda'));
    return InkWell(
      key: Key('grp_vote_row_${v.id}'),
      onTap: () => _open(v),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          CircleAvatar(radius: 20, backgroundColor: votingStatusColor(v.status).withValues(alpha: 0.2), child: Icon(votingCategoryIcon(v.category), color: votingStatusColor(v.status), size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(v.isElection ? (v.position ?? v.title) : v.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              if (v.isElection) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sw ? 'Wagombea: $who' : 'Candidates: $who', style: const TextStyle(color: Colors.white70, fontSize: 12))) else Padding(padding: const EdgeInsets.only(top: 2), child: Text(who, style: const TextStyle(color: Colors.white54, fontSize: 12))),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  v.status == 'scheduled' ? '${sw ? 'Inafunguliwa' : 'Opens'} ${votingWhen(v.opensAt)}' : '${sw ? 'Inafungwa' : 'Closes'} ${votingWhen(v.closesAt)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              if (v.progress != null && v.status == 'open') Padding(padding: const EdgeInsets.only(top: 2), child: Text('${v.progress!.turnout} / ${v.progress!.eligible} ${sw ? 'wamepiga' : 'voted'}', style: const TextStyle(color: Colors.white38, fontSize: 11))),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
            GroupPill(votingStatusLabel(sw: sw, status: v.status), color: votingStatusColor(v.status)),
            if (my.isNotEmpty && v.status != 'draft') ...<Widget>[const SizedBox(height: 6), GroupPill(my, color: votingMyColor(v.my.state))],
          ]),
        ]),
      ),
    );
  }
}

/// What the member has been told about votings, newest first; each notice opens that exact voting item.
class VotingNoticesScreen extends StatefulWidget {
  const VotingNoticesScreen({required this.api, required this.me, super.key});

  final GroupsApi api;
  final GroupMe me;

  @override
  State<VotingNoticesScreen> createState() => _VotingNoticesScreenState();
}

class _VotingNoticesScreenState extends State<VotingNoticesScreen> {
  List<GroupNotice> _rows = const <GroupNotice>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final (List<GroupNotice> rows, int _) = await widget.api.notifications();
      if (mounted) {
        setState(() {
          _rows = rows;
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

  Future<void> _tap(final GroupNotice n) async {
    try {
      if (!n.read) await widget.api.readNotifications(ids: <int>[n.id]);
    } on Exception {
      // opening the voting matters more than marking the notice
    }
    if (!mounted) return;
    if (n.linkType == 'voting' && n.linkId != null) {
      await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => VotingDetailScreen(api: widget.api, me: widget.me, votingId: n.linkId!)));
    }
    await _load();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Taarifa za kura' : 'Voting notices', flat: true, actions: <Widget>[
        IconButton(key: const Key('grp_notice_all'), tooltip: sw ? 'Weka zote kuwa zimesomwa' : 'Mark all as read', onPressed: () async {
          await widget.api.readNotifications(all: true);
          await _load();
        }, icon: const Icon(Icons.done_all_rounded)),
      ]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            if (_error != null) GroupEmpty(_error!),
            if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            if (!_loading && _error == null && _rows.isEmpty) GroupEmpty(sw ? 'Hakuna taarifa.' : 'No notices.'),
            if (_rows.isNotEmpty)
              GlowListCard(
                dividerKey: 'grp_notice_div',
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: <Widget>[
                  for (final GroupNotice n in _rows)
                    ListTile(
                      key: Key('grp_notice_${n.id}'),
                      onTap: () => _tap(n),
                      leading: Icon(n.read ? Icons.notifications_none_rounded : Icons.notifications_active_rounded, color: n.read ? Colors.white38 : ThemeConstants.warningAmber),
                      title: Text(sw ? n.title : n.titleEn, style: TextStyle(color: Colors.white, fontWeight: n.read ? FontWeight.w500 : FontWeight.w800)),
                      subtitle: Text((sw ? n.body : n.bodyEn) ?? '', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
