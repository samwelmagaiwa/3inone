import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_governance_models.dart';
import '../models/group_models.dart';
import '../services/groups_api.dart';
import 'groups_text.dart';
import 'widgets/groups_ui.dart';
import 'widgets/member_picker.dart';

/// The record of a meeting under its minutes: what was decided (resolutions), what someone must do (actions), and the chair's approval of the
/// minutes. The secretary writes while the minutes are a draft; the chair approves (never ones they wrote); once approved, members see them
/// and whoever owns an action ticks it off. The server enforces every rule; this shows only what the person may do.
class MeetingRecordSection extends StatelessWidget {
  const MeetingRecordSection({required this.api, required this.me, required this.meeting, required this.onChanged, super.key});

  final GroupsApi api;
  final GroupMe me;
  final GroupMeeting meeting;
  final Future<void> Function() onChanged;

  bool get _draft => meeting.status == 'held' && meeting.minutesStatus == 'draft';
  bool get _approved => meeting.status == 'held' && meeting.minutesStatus == 'approved';

  Future<void> _run(final BuildContext context, final Future<void> Function() call, final String done) async {
    try {
      await call();
      if (!context.mounted) return;
      ThemeConstants.showSuccessSnackBar(context, done);
      await onChanged();
    } on Exception catch (e) {
      if (context.mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _add(final BuildContext context, final String kind) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final Map<String, dynamic>? body = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _ItemDialog(kind: kind, api: api));
    if (body == null || !context.mounted) return;
    await _run(context, () => api.addMeetingItem(meeting.id, body), kind == 'action' ? (sw ? 'Kazi imeongezwa.' : 'Action added.') : (sw ? 'Azimio limeongezwa.' : 'Resolution added.'));
  }

  Future<void> _remove(final BuildContext context, final GroupMeetingItem i) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (!await groupConfirm(context, title: sw ? 'Ondoa kipengele?' : 'Remove this item?', message: i.text, yes: sw ? 'Ondoa' : 'Remove', tone: GroupTone.danger)) return;
    if (!context.mounted) return;
    await _run(context, () => api.removeMeetingItem(meeting.id, i.id), sw ? 'Kimeondolewa.' : 'Removed.');
  }

  Future<void> _done(final BuildContext context, final GroupMeetingItem i) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (!await groupConfirm(context, title: sw ? 'Kazi imekamilika?' : 'Mark this action done?', message: i.text, yes: sw ? 'Ndiyo, imekamilika' : 'Yes, done', tone: GroupTone.positive)) return;
    if (!context.mounted) return;
    await _run(context, () => api.completeMeetingItem(meeting.id, i.id), sw ? 'Imewekwa kukamilika.' : 'Marked done.');
  }

  Future<void> _approve(final BuildContext context) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (!await groupConfirm(
      context,
      title: sw ? 'Idhinisha muhtasari?' : 'Approve the minutes?',
      message: sw ? 'Wanachama wote wataona muhtasari, maazimio na kazi. Haubadilishwi tena bila kuufungua upya.' : 'Every member will see the minutes, resolutions and actions. They are not edited again unless reopened.',
      yes: sw ? 'Idhinisha' : 'Approve',
      tone: GroupTone.positive,
    )) {
      return;
    }
    if (!context.mounted) return;
    await _run(context, () => api.approveMinutes(meeting.id), sw ? 'Muhtasari umeidhinishwa.' : 'Minutes approved.');
  }

  Future<void> _reopen(final BuildContext context) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final String? reason = await groupReason(context, title: sw ? 'Fungua upya muhtasari' : 'Reopen the minutes', message: sw ? 'Wanachama hawataona hadi uidhinishwe tena.' : 'Members will not see them until they are approved again.', yes: sw ? 'Fungua' : 'Reopen');
    if (reason == null || !context.mounted) return;
    await _run(context, () => api.reopenMinutes(meeting.id, reason), sw ? 'Muhtasari umefunguliwa.' : 'Minutes reopened.');
  }

  Widget _button(final String key, final IconData icon, final String label, final Color color, final VoidCallback onTap) => FilledButton.icon(
        key: Key(key),
        style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    if (meeting.status != 'held') return const SizedBox.shrink();
    final bool writes = me.can('record_meetings') && _draft;
    final List<GroupMeetingItem> resolutions = meeting.items.where((final GroupMeetingItem i) => i.kind == 'resolution').toList();
    final List<GroupMeetingItem> actions = meeting.items.where((final GroupMeetingItem i) => i.kind == 'action').toList();
    final int? myId = me.member?.id;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      GlowCard(children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(sw ? 'Hali ya muhtasari' : 'Minutes', style: const TextStyle(color: Colors.white70))),
          GroupPill(
            _approved ? (sw ? 'Umeidhinishwa' : 'Approved') : (sw ? 'Rasimu' : 'Draft'),
            color: _approved ? ThemeConstants.successGreen : ThemeConstants.warningAmber,
          ),
        ]),
        if (_approved && meeting.minutesApprovedByName != null) GroupDetailRow(sw ? 'Ameidhinisha' : 'Approved by', meeting.minutesApprovedByName!),
        if (_draft && !me.can('record_meetings') && !me.can('approve_minutes')) Text(sw ? 'Wanachama wataona baada ya Mwenyekiti kuidhinisha.' : 'Members see them once the chair approves.', style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
      if (resolutions.isNotEmpty)
        GlowCard(title: sw ? 'Maazimio' : 'Resolutions', dividerKey: 'grp_resolutions_div', children: <Widget>[
          for (final GroupMeetingItem i in resolutions)
            ListTile(
              key: Key('grp_item_${i.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.gavel_rounded, color: ThemeConstants.invAccent, size: 20),
              title: Text(i.text, style: const TextStyle(color: Colors.white)),
              trailing: writes ? IconButton(key: Key('grp_item_remove_${i.id}'), icon: const Icon(Icons.close_rounded, color: ThemeConstants.errorRed), onPressed: () => _remove(context, i)) : null,
            ),
        ]),
      if (actions.isNotEmpty)
        GlowCard(title: sw ? 'Kazi za kufanya' : 'Actions', dividerKey: 'grp_actions_div', children: <Widget>[
          for (final GroupMeetingItem i in actions)
            ListTile(
              key: Key('grp_item_${i.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(i.text, style: TextStyle(color: i.done ? Colors.white54 : Colors.white, decoration: i.done ? TextDecoration.lineThrough : null)),
              subtitle: Text(
                <String>[if (i.assigneeName != null) i.assigneeName!, if (i.dueDate != null) '${sw ? 'Mwisho' : 'By'} ${dateLabel(i.dueDate)}'].join(' · '),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              trailing: i.done
                  ? GroupPill(sw ? 'Imekamilika' : 'Done', color: ThemeConstants.successGreen)
                  : writes
                      ? IconButton(key: Key('grp_item_remove_${i.id}'), icon: const Icon(Icons.close_rounded, color: ThemeConstants.errorRed), onPressed: () => _remove(context, i))
                      : _approved && (i.assigneeId == myId || me.can('record_meetings'))
                          ? FilledButton(
                              key: Key('grp_item_done_${i.id}'),
                              style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                              onPressed: () => _done(context, i),
                              child: Text(sw ? 'Imekamilika' : 'Done'),
                            )
                          : i.overdue
                              ? GroupPill(sw ? 'Imechelewa' : 'Overdue', color: ThemeConstants.errorRed)
                              : null,
            ),
        ]),
      const SizedBox(height: 4),
      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
        if (writes) ...<Widget>[
          _button('grp_add_resolution', Icons.gavel_rounded, sw ? 'Ongeza azimio' : 'Add a resolution', ThemeConstants.primaryOrange, () => _add(context, 'resolution')),
          _button('grp_add_action', Icons.assignment_turned_in_rounded, sw ? 'Ongeza kazi' : 'Add an action', ThemeConstants.primaryOrange, () => _add(context, 'action')),
        ],
        if (_draft && me.can('approve_minutes')) _button('grp_minutes_approve', Icons.verified_rounded, sw ? 'Idhinisha muhtasari' : 'Approve the minutes', ThemeConstants.successGreen, () => _approve(context)),
        if (_approved && me.can('approve_minutes')) _button('grp_minutes_reopen', Icons.lock_open_rounded, sw ? 'Fungua upya' : 'Reopen', ThemeConstants.warningAmber, () => _reopen(context)),
      ]),
    ]);
  }
}

/// A resolution (just words) or an action (words, who does it, by when).
class _ItemDialog extends StatefulWidget {
  const _ItemDialog({required this.kind, required this.api});

  final String kind;
  final GroupsApi api;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  final TextEditingController _text = TextEditingController();
  GroupMember? _who;
  DateTime? _due;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String _iso(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool action = widget.kind == 'action';
    final bool ready = _text.text.trim().length >= 3;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(action ? (sw ? 'Kazi mpya' : 'New action') : (sw ? 'Azimio jipya' : 'New resolution'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        const SizedBox(width: double.maxFinite),
        TextField(
          key: const Key('grp_item_text'),
          controller: _text,
          onChanged: (_) => setState(() {}),
          maxLines: 3,
          minLines: 1,
          maxLength: 500,
          style: const TextStyle(color: Colors.white),
          decoration: ThemeConstants.darkField(action ? (sw ? 'Kinachopaswa kufanywa' : 'What must be done') : (sw ? 'Tulichoamua' : 'What was decided')),
        ),
        if (action) ...<Widget>[
          ListTile(
            key: const Key('grp_item_who'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline, color: Colors.white54),
            title: Text(_who?.fullName ?? (sw ? 'Atakayefanya (hiari)' : 'Who does it (optional)'), style: const TextStyle(color: Colors.white70)),
            onTap: () async {
              final GroupMember? m = await pickGroupMember(context, api: widget.api);
              if (m != null) setState(() => _who = m);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined, color: Colors.white54),
            title: Text(_due == null ? (sw ? 'Mwisho (hiari)' : 'By when (optional)') : dateLabel(_iso(_due!)), style: const TextStyle(color: Colors.white70)),
            onTap: () async {
              final DateTime now = DateTime.now();
              final DateTime? d = await showDatePicker(context: context, initialDate: _due ?? now, firstDate: now.subtract(const Duration(days: 30)), lastDate: now.add(const Duration(days: 730)));
              if (d != null) setState(() => _due = d);
            },
          ),
        ],
      ]),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white60))),
        TextButton(
          key: const Key('grp_item_save'),
          onPressed: ready
              ? () => Navigator.pop(context, <String, dynamic>{
                    'kind': widget.kind,
                    'text': _text.text.trim(),
                    if (action && _who != null) 'assignee_id': _who!.id,
                    if (action && _due != null) 'due_date': _iso(_due!),
                  })
              : null,
          child: Text(sw ? 'Hifadhi' : 'Save', style: TextStyle(color: ready ? ThemeConstants.successGreen : Colors.white24, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

/// The follow-up of actions from approved minutes: one's own, or (for whoever records meetings) everyone's.
class MeetingActionsScreen extends StatefulWidget {
  const MeetingActionsScreen({required this.api, required this.all, super.key});

  final GroupsApi api;
  final bool all;

  @override
  State<MeetingActionsScreen> createState() => _MeetingActionsScreenState();
}

class _MeetingActionsScreenState extends State<MeetingActionsScreen> {
  List<GroupMeetingItem> _rows = const <GroupMeetingItem>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final List<GroupMeetingItem> rows = await widget.api.meetingActions(all: widget.all);
      if (mounted) {
        setState(() {
          _rows = rows;
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

  Future<void> _done(final GroupMeetingItem i) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (!await groupConfirm(context, title: sw ? 'Kazi imekamilika?' : 'Mark this action done?', message: i.text, yes: sw ? 'Ndiyo, imekamilika' : 'Yes, done', tone: GroupTone.positive)) return;
    try {
      await widget.api.completeMeetingItem(i.meetingId, i.id);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Imewekwa kukamilika.' : 'Marked done.');
      await _load();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(widget.all ? (sw ? 'Kazi za vikao (zote)' : 'Meeting actions (all)') : (sw ? 'Kazi zangu za vikao' : 'My meeting actions'), flat: true),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: joinGlowCards(<Widget>[
                  if (_error != null) GroupEmpty(_error!),
                  if (_error == null && _rows.isEmpty) GroupEmpty(sw ? 'Hakuna kazi zinazosubiri.' : 'Nothing waiting.'),
                  if (_rows.isNotEmpty)
                    GlowListCard(
                      dividerKey: 'grp_mactions_div',
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      children: <Widget>[
                        for (final GroupMeetingItem i in _rows)
                          ListTile(
                            key: Key('grp_maction_${i.id}'),
                            title: Text(i.text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              <String>[
                                if (i.meetingTitle != null) i.meetingTitle!,
                                if (widget.all && i.assigneeName != null) i.assigneeName!,
                                if (i.dueDate != null) '${sw ? 'Mwisho' : 'By'} ${dateLabel(i.dueDate)}',
                              ].join(' · '),
                              style: TextStyle(color: i.overdue ? ThemeConstants.errorText : Colors.white60, fontSize: 12),
                            ),
                            trailing: FilledButton(
                              key: Key('grp_maction_done_${i.id}'),
                              style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                              onPressed: () => _done(i),
                              child: Text(sw ? 'Imekamilika' : 'Done'),
                            ),
                          ),
                      ],
                    ),
                ])),
              ),
      ),
    );
  }
}
