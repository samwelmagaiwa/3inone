import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../constants/theme_constants.dart';
import '../../../../services/localization_service.dart';
import '../../models/group_models.dart';
import '../../services/groups_api.dart';
import '../groups_text.dart';
import 'groups_ui.dart';

/// Choose a member from the register, searching by name, phone or number. [statuses] limits who can be chosen (active members only to be a
/// referrer; applicants too to receive a payment); [exceptId] leaves one person out (nobody refers themself).
Future<GroupMember?> pickGroupMember(
  final BuildContext context, {
  required final GroupsApi api,
  final Set<String> statuses = const <String>{'active'},
  final int? exceptId,
}) =>
    showDialog<GroupMember>(context: context, builder: (_) => _MemberPicker(api: api, statuses: statuses, exceptId: exceptId));

class _MemberPicker extends StatefulWidget {
  const _MemberPicker({required this.api, required this.statuses, this.exceptId});

  final GroupsApi api;
  final Set<String> statuses;
  final int? exceptId;

  @override
  State<_MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<_MemberPicker> {
  final TextEditingController _q = TextEditingController();
  List<GroupMember> _found = const <GroupMember>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final String? only = widget.statuses.length == 1 ? widget.statuses.first : null;
      final GroupMemberPage page = await widget.api.members(status: only, query: _q.text);
      if (mounted) {
        setState(() => _found = page.members.where((final GroupMember m) => m.id != widget.exceptId && widget.statuses.contains(m.status)).toList());
      }
    } on Exception {
      if (mounted) setState(() => _found = const <GroupMember>[]);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return AlertDialog(
      key: const Key('grp_member_picker'),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(sw ? 'Chagua mwanachama' : 'Choose a member', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(children: <Widget>[
          TextField(
            key: const Key('grp_picker_search'),
            controller: _q,
            onSubmitted: (_) => _search(),
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Tafuta' : 'Search', suffix: IconButton(icon: const Icon(Icons.search, color: Colors.white54), onPressed: _search)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _found.isEmpty
                    ? GroupEmpty(sw ? 'Hakuna mwanachama.' : 'No member found.')
                    : ListView(children: <Widget>[
                        for (final GroupMember m in _found)
                          ListTile(
                            key: Key('grp_pick_${m.id}'),
                            title: Text(m.fullName, style: const TextStyle(color: Colors.white)),
                            subtitle: Text('${m.memberNumber ?? m.applicationRef ?? ''} · ${statusLabel(sw: sw, status: m.status)}', style: const TextStyle(color: Colors.white60)),
                            onTap: () => Navigator.pop(context, m),
                          ),
                      ]),
          ),
        ]),
      ),
      actions: <Widget>[TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Funga' : 'Close', style: const TextStyle(color: Colors.white60)))],
    );
  }
}
