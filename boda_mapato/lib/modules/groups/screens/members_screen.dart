import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'member_detail_screen.dart';
import 'member_form_screen.dart';
import 'widgets/groups_ui.dart';

/// The member register: applications first, then members, a page at a time, with a filter per status and a search by name, phone or number.
class MembersScreen extends StatefulWidget {
  const MembersScreen({required this.me, required this.api, required this.onChanged, super.key});

  final GroupMe me;
  final GroupsApi api;
  final Future<void> Function() onChanged;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String? _status;
  final List<GroupMember> _members = <GroupMember>[];
  Map<String, int> _counts = const <String, int>{};
  int _page = 1;
  bool _hasMore = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({final bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final int page = more ? _page + 1 : 1;
      final GroupMemberPage got = await widget.api.members(status: _status, query: _search.text, page: page);
      if (!mounted) return;
      setState(() {
        if (!more) _members.clear();
        _members.addAll(got.members);
        _counts = got.counts;
        _page = page;
        _hasMore = got.hasMore;
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

  void _searchChanged(final String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _openMember(final GroupMember m) async {
    await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => MemberDetailScreen(api: widget.api, me: widget.me, memberId: m.id)));
    if (!mounted) return;
    await _load();
    await widget.onChanged();
  }

  Future<void> _add() async {
    final GroupMemberFile? created = await Navigator.push<GroupMemberFile>(
      context,
      MaterialPageRoute<GroupMemberFile>(builder: (_) => MemberFormScreen(api: widget.api, me: widget.me)),
    );
    if (created == null || !mounted) return;
    await _load();
    await widget.onChanged();
    if (mounted) await _openMember(created.member);
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final int all = _counts.values.fold(0, (final int a, final int b) => a + b);
    final List<(String?, String)> filters = <(String?, String)>[
      (null, '${sw ? 'Wote' : 'All'} ($all)'),
      for (final String s in const <String>['submitted', 'active', 'suspended', 'exited', 'rejected', 'deceased'])
        if ((_counts[s] ?? 0) > 0 || s == 'submitted' || s == 'active') (s, '${statusLabel(sw: sw, status: s)} (${_counts[s] ?? 0})'),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.me.can('manage_members')
          ? FloatingActionButton.extended(
              key: const Key('grp_member_add'),
              backgroundColor: ThemeConstants.primaryOrange,
              foregroundColor: Colors.white,
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(sw ? 'Ongeza mwanachama' : 'Add member'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: joinGlowCards(<Widget>[
            TextField(
              key: const Key('grp_member_search'),
              controller: _search,
              onChanged: _searchChanged,
              style: const TextStyle(color: Colors.white),
              decoration: ThemeConstants.darkField(sw ? 'Tafuta jina, simu au namba' : 'Search name, phone or number', prefix: const Icon(Icons.search, color: Colors.white54)),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: <Widget>[
                for (final (String?, String) f in filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: Key('grp_member_filter_${f.$1 ?? 'all'}'),
                      label: Text(f.$2),
                      selected: _status == f.$1,
                      onSelected: (_) {
                        setState(() => _status = f.$1);
                        _load();
                      },
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            if (_error != null) GroupEmpty(_error!),
            if (!_loading && _error == null && _members.isEmpty) GroupEmpty(sw ? 'Hakuna mwanachama hapa bado.' : 'No members here yet.'),
            if (_members.isNotEmpty)
              GlowListCard(
                dividerKey: 'grp_members_div',
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: <Widget>[for (final GroupMember m in _members) _MemberTile(m: m, sw: sw, onTap: () => _openMember(m))],
              ),
            if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            if (_hasMore && !_loading)
              TextButton(
                key: const Key('grp_members_more'),
                onPressed: () => _load(more: true),
                child: Text(LocalizationService.instance.translate('list_show_more'), style: const TextStyle(color: ThemeConstants.primaryOrange)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.m, required this.sw, required this.onTap});

  final GroupMember m;
  final bool sw;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) => ListTile(
        key: Key('grp_member_${m.id}'),
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: statusColor(m.status).withValues(alpha: 0.2),
          child: Text(m.fullName.isEmpty ? '?' : m.fullName.characters.first.toUpperCase(), style: TextStyle(color: statusColor(m.status), fontWeight: FontWeight.w800)),
        ),
        title: Text(m.fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(
          <String>[
            m.memberNumber ?? m.applicationRef ?? '',
            if (m.office != null) officeLabel(sw: sw, office: m.office),
            m.phone,
          ].where((final String s) => s.isNotEmpty).join(' · '),
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: GroupPill(statusLabel(sw: sw, status: m.status), color: statusColor(m.status)),
      );
}
