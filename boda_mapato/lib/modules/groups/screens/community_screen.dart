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

String meetingStatusLabel({required final bool sw, required final String status}) => switch (status) {
      'scheduled' => sw ? 'Kimepangwa' : 'Called',
      'held' => sw ? 'Kimefanyika' : 'Held',
      'cancelled' => sw ? 'Kimesitishwa' : 'Cancelled',
      _ => status,
    };

Color meetingStatusColor(final String status) => switch (status) {
      'scheduled' => ThemeConstants.invAccent,
      'held' => ThemeConstants.successGreen,
      'cancelled' => ThemeConstants.errorRed,
      _ => Colors.white54,
    };

String audienceLabel({required final bool sw, required final String audience}) => switch (audience) {
      'all' => sw ? 'Wanachama wote' : 'All members',
      'officers' => sw ? 'Viongozi' : 'Officers',
      'overdue' => sw ? 'Wenye michango iliyopita muda' : 'With overdue contributions',
      'selected' => sw ? 'Waliochaguliwa' : 'Chosen members',
      _ => audience,
    };

/// "22/11/2026 14:00" from a stored time.
String dateTimeLabel(final String iso) {
  final DateTime? d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${dateLabel(iso)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Meetings and notices for every member; texts to many members for whoever may send them.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({required this.me, required this.api, required this.onChanged, super.key});

  final GroupMe me;
  final GroupsApi api;
  final Future<void> Function() onChanged;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  String _tab = 'meetings';
  List<GroupMeeting> _meetings = const <GroupMeeting>[];
  List<GroupAnnouncement> _notices = const <GroupAnnouncement>[];
  List<GroupMessage> _texts = const <GroupMessage>[];
  bool _loading = true;
  String? _error;

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
      final List<GroupMeeting> m = await widget.api.meetings();
      final List<GroupAnnouncement> n = await widget.api.announcements();
      final List<GroupMessage> t = widget.me.can('send_texts') ? await widget.api.texts() : const <GroupMessage>[];
      if (mounted) {
        setState(() {
          _meetings = m;
          _notices = n;
          _texts = t;
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

  Future<void> _done(final String text) async {
    if (!mounted) return;
    ThemeConstants.showSuccessSnackBar(context, text);
    await _load();
    await widget.onChanged();
  }

  Future<void> _callMeeting() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final Map<String, dynamic>? body = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _MeetingDialog());
    if (body == null || !mounted) return;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Itisha kikao?' : 'Call this meeting?',
      message: '${body['title']} · ${dateTimeLabel('${body['starts_at']}')}${body['notify'] == true ? (sw ? '\nWanachama watatumiwa SMS (za kikundi).' : '\nMembers will be texted (the group’s SMS).') : ''}',
      yes: sw ? 'Itisha' : 'Call it',
      tone: GroupTone.positive,
    );
    if (!ok) return;
    try {
      await widget.api.callMeeting(body);
      await _done(sw ? 'Kikao kimeitishwa.' : 'Meeting called.');
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _openMeeting(final GroupMeeting m) async {
    await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => MeetingDetailScreen(api: widget.api, me: widget.me, meeting: m)));
    await _load();
    await widget.onChanged();
  }

  Future<void> _newNotice() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final Map<String, dynamic>? body = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _NoticeDialog());
    if (body == null || !mounted) return;
    final bool ok = await groupConfirm(context, title: sw ? 'Tangaza?' : 'Post this notice?', message: '${body['title']} · ${audienceLabel(sw: sw, audience: '${body['audience']}')}', yes: sw ? 'Tangaza' : 'Post', tone: GroupTone.positive);
    if (!ok) return;
    try {
      await widget.api.postAnnouncement(body);
      await _done(sw ? 'Tangazo limewekwa.' : 'Notice posted.');
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _removeNotice(final GroupAnnouncement a) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    if (!widget.me.can('post_announcements')) return;
    final bool ok = await groupConfirm(context, title: sw ? 'Ondoa tangazo?' : 'Take the notice down?', message: a.title, yes: sw ? 'Ondoa' : 'Take down', tone: GroupTone.danger);
    if (!ok) return;
    try {
      await widget.api.removeAnnouncement(a.id);
      await _done(sw ? 'Tangazo limeondolewa.' : 'Notice taken down.');
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _sendText() async {
    final bool? sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.bgMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (final BuildContext c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom), child: _TextForm(api: widget.api)),
    );
    if (sent ?? false) await _load();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupMe me = widget.me;
    final Widget? fab = switch (_tab) {
      'meetings' when me.can('call_meetings') => FloatingActionButton.extended(
          key: const Key('grp_meeting_call'),
          backgroundColor: ThemeConstants.primaryOrange,
          foregroundColor: Colors.white,
          onPressed: _callMeeting,
          icon: const Icon(Icons.event_rounded),
          label: Text(sw ? 'Itisha kikao' : 'Call a meeting'),
        ),
      'notices' when me.can('post_announcements') => FloatingActionButton.extended(
          key: const Key('grp_notice_new'),
          backgroundColor: ThemeConstants.primaryOrange,
          foregroundColor: Colors.white,
          onPressed: _newNotice,
          icon: const Icon(Icons.campaign_rounded),
          label: Text(sw ? 'Tangazo jipya' : 'New notice'),
        ),
      'texts' => FloatingActionButton.extended(
          key: const Key('grp_text_new'),
          backgroundColor: ThemeConstants.primaryOrange,
          foregroundColor: Colors.white,
          onPressed: _sendText,
          icon: const Icon(Icons.sms_rounded),
          label: Text(sw ? 'Tuma ujumbe' : 'Send a text'),
        ),
      _ => null,
    };
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: fab,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: <Widget>[
          SegmentedButton<String>(
            key: const Key('grp_community_tabs'),
            segments: <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'meetings', label: Text(sw ? 'Vikao' : 'Meetings')),
              ButtonSegment<String>(value: 'notices', label: Text(sw ? 'Matangazo' : 'Notices')),
              if (me.can('send_texts')) ButtonSegment<String>(value: 'texts', label: Text(sw ? 'Ujumbe' : 'Texts')),
            ],
            selected: <String>{_tab},
            onSelectionChanged: (final Set<String> v) => setState(() => _tab = v.first),
          ),
          const SizedBox(height: 12),
          if (_error != null) GroupEmpty(_error!),
          if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (!_loading && _tab == 'meetings') ...<Widget>[
            if (_meetings.isEmpty) GroupEmpty(sw ? 'Hakuna kikao bado.' : 'No meetings yet.'),
            if (_meetings.isNotEmpty)
              GlowListCard(
                dividerKey: 'grp_meetings_div',
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: <Widget>[
                  for (final GroupMeeting m in _meetings)
                    ListTile(
                      key: Key('grp_meeting_${m.id}'),
                      onTap: () => _openMeeting(m),
                      title: Text(m.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      subtitle: Text('${dateTimeLabel(m.startsAt)}${m.venue == null ? '' : ' · ${m.venue}'}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      trailing: GroupPill(meetingStatusLabel(sw: sw, status: m.status), color: meetingStatusColor(m.status)),
                    ),
                ],
              ),
          ],
          if (!_loading && _tab == 'notices') ...<Widget>[
            if (_notices.isEmpty) GroupEmpty(sw ? 'Hakuna tangazo.' : 'No notices.'),
            for (final GroupAnnouncement a in _notices)
              GlowCard(
                key: Key('grp_notice_${a.id}'),
                title: a.title,
                children: <Widget>[
                  Text(a.body, style: const TextStyle(color: Colors.white)),
                  Row(children: <Widget>[
                    Expanded(
                      child: Text(
                        '${a.authorName ?? ''} · ${dateLabel(a.createdAt)}${a.audience == 'officers' ? ' · ${audienceLabel(sw: sw, audience: 'officers')}' : ''}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    if (me.can('post_announcements'))
                      IconButton(key: Key('grp_notice_remove_${a.id}'), icon: const Icon(Icons.delete_outline, color: ThemeConstants.errorText), onPressed: () => _removeNotice(a)),
                  ]),
                ],
              ),
          ],
          if (!_loading && _tab == 'texts') ...<Widget>[
            if (_texts.isEmpty) GroupEmpty(sw ? 'Hakuna ujumbe uliotumwa.' : 'No texts sent.'),
            if (_texts.isNotEmpty)
              GlowListCard(
                dividerKey: 'grp_texts_div',
                children: <Widget>[
                  for (final GroupMessage t in _texts)
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(t.body, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(
                        '${audienceLabel(sw: sw, audience: t.audience)} · ${t.sent}/${t.recipients} ${sw ? 'zimefika' : 'sent'} · ${dateLabel(t.createdAt)} · ${t.sentByName ?? ''}',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ]),
                ],
              ),
          ],
        ]),
      ),
    );
  }
}

/// One meeting: when, where, the agenda, who was there and the minutes. The secretary records it once it has started; the chair can cancel it before.
class MeetingDetailScreen extends StatefulWidget {
  const MeetingDetailScreen({required this.api, required this.me, required this.meeting, super.key});

  final GroupsApi api;
  final GroupMe me;
  final GroupMeeting meeting;

  @override
  State<MeetingDetailScreen> createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends State<MeetingDetailScreen> {
  late GroupMeeting _m = widget.meeting;

  Future<void> _reload() async {
    try {
      final List<GroupMeeting> all = await widget.api.meetings();
      final GroupMeeting? m = all.where((final GroupMeeting x) => x.id == _m.id).firstOrNull;
      if (m != null && mounted) setState(() => _m = m);
    } on Exception {
      return;
    }
  }

  Future<void> _cancel() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final String? reason = await groupReason(context, title: sw ? 'Sitisha kikao' : 'Cancel the meeting', message: _m.title, yes: sw ? 'Sitisha' : 'Cancel it');
    if (reason == null) return;
    try {
      await widget.api.cancelMeeting(_m.id, reason);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Kikao kimesitishwa.' : 'Meeting cancelled.');
      await _reload();
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  Future<void> _record() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final bool? saved = await Navigator.push<bool>(context, MaterialPageRoute<bool>(builder: (_) => _RecordMeetingScreen(api: widget.api, meeting: _m)));
    if ((saved ?? false) && mounted) {
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Kikao kimehifadhiwa.' : 'Meeting recorded.');
      await _reload();
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool started = (_m.when ?? DateTime.now()).isBefore(DateTime.now());
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(_m.title, flat: true),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: <Widget>[
          GlowCard(children: <Widget>[
            Row(children: <Widget>[
              Expanded(child: Text(dateTimeLabel(_m.startsAt), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              GroupPill(meetingStatusLabel(sw: sw, status: _m.status), color: meetingStatusColor(_m.status)),
            ]),
            if (_m.venue != null) GroupDetailRow(sw ? 'Mahali' : 'Where', _m.venue!),
            if (_m.calledByName != null) GroupDetailRow(sw ? 'Kimeitishwa na' : 'Called by', _m.calledByName!),
            if (_m.status == 'held') GroupDetailRow(sw ? 'Waliohudhuria' : 'Present', '${_m.presentCount}'),
            if (_m.iWasThere != null && _m.status == 'held')
              GroupDetailRow(sw ? 'Mimi' : 'Me', _m.iWasThere! ? (sw ? 'Nilihudhuria' : 'Present') : (sw ? 'Sikuhudhuria' : 'Absent'),
                  valueColor: _m.iWasThere! ? ThemeConstants.successGreen : ThemeConstants.warningAmber),
            if (_m.cancelReason != null) GroupDetailRow(sw ? 'Sababu' : 'Reason', _m.cancelReason!, valueColor: ThemeConstants.errorText),
          ]),
          if (_m.agenda != null) GlowCard(title: sw ? 'Ajenda' : 'Agenda', children: <Widget>[Text(_m.agenda!, style: const TextStyle(color: Colors.white))]),
          if (_m.minutes != null) GlowCard(title: sw ? 'Muhtasari wa kikao' : 'Minutes', children: <Widget>[Text(_m.minutes!, key: const Key('grp_minutes'), style: const TextStyle(color: Colors.white))]),
          const SizedBox(height: 12),
          if (widget.me.can('record_meetings') && _m.status != 'cancelled' && started)
            FilledButton.icon(
              key: const Key('grp_meeting_record'),
              style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: _record,
              icon: const Icon(Icons.fact_check_rounded),
              label: Text(_m.status == 'held' ? (sw ? 'Rekebisha mahudhurio na muhtasari' : 'Correct attendance and minutes') : (sw ? 'Rekodi mahudhurio na muhtasari' : 'Record attendance and minutes')),
            ),
          if (widget.me.can('call_meetings') && _m.status == 'scheduled' && !started) ...<Widget>[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('grp_meeting_cancel'),
              style: OutlinedButton.styleFrom(foregroundColor: ThemeConstants.errorRed, side: const BorderSide(color: ThemeConstants.errorRed), padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: _cancel,
              icon: const Icon(Icons.event_busy_rounded),
              label: Text(sw ? 'Sitisha kikao' : 'Cancel the meeting'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Tick who was there and write the minutes.
class _RecordMeetingScreen extends StatefulWidget {
  const _RecordMeetingScreen({required this.api, required this.meeting});

  final GroupsApi api;
  final GroupMeeting meeting;

  @override
  State<_RecordMeetingScreen> createState() => _RecordMeetingScreenState();
}

class _RecordMeetingScreenState extends State<_RecordMeetingScreen> {
  late final Set<int> _present = widget.meeting.presentIds.toSet();
  late final TextEditingController _minutes = TextEditingController(text: widget.meeting.minutes);
  List<GroupMember> _members = const <GroupMember>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<GroupMember> all = <GroupMember>[];
    try {
      for (int page = 1; page <= 20; page++) {
        final GroupMemberPage p = await widget.api.members(status: 'active', page: page);
        all.addAll(p.members);
        if (!p.hasMore) break;
      }
    } on Exception {
      // Whatever came back is shown.
    }
    if (mounted) {
      setState(() {
        _members = all;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Hifadhi kikao?' : 'Save the meeting?',
      message: '${sw ? 'Waliohudhuria' : 'Present'}: ${_present.length} / ${_members.length}',
      yes: sw ? 'Hifadhi' : 'Save',
      tone: GroupTone.positive,
    );
    if (!ok) return;
    try {
      await widget.api.recordMeeting(widget.meeting.id, presentIds: _present.toList(), minutes: _minutes.text.trim().isEmpty ? null : _minutes.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Mahudhurio na muhtasari' : 'Attendance and minutes', flat: true),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: <Widget>[
                GlowListCard(
                  dividerKey: 'grp_attend_div',
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  children: <Widget>[
                    for (final GroupMember m in _members)
                      CheckboxListTile(
                        key: Key('grp_attend_${m.id}'),
                        value: _present.contains(m.id),
                        onChanged: (final bool? v) => setState(() => (v ?? false) ? _present.add(m.id) : _present.remove(m.id)),
                        title: Text(m.fullName, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(m.memberNumber ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('grp_minutes_field'),
                  controller: _minutes,
                  maxLines: 10,
                  minLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: ThemeConstants.darkField(sw ? 'Muhtasari wa kikao' : 'Minutes'),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('grp_record_save'),
                  style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(sw ? 'Hifadhi' : 'Save'),
                ),
              ]),
      ),
    );
  }
}

class _MeetingDialog extends StatefulWidget {
  const _MeetingDialog();

  @override
  State<_MeetingDialog> createState() => _MeetingDialogState();
}

class _MeetingDialogState extends State<_MeetingDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _agenda = TextEditingController();
  final TextEditingController _venue = TextEditingController();
  DateTime _at = DateTime.now().add(const Duration(days: 7)).copyWith(hour: 14, minute: 0, second: 0, millisecond: 0, microsecond: 0);
  bool _notify = false;

  @override
  void dispose() {
    _title.dispose();
    _agenda.dispose();
    _venue.dispose();
    super.dispose();
  }

  String _iso(final DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:00';

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool ready = _title.text.trim().length >= 3;
    return AlertDialog(
      key: const Key('grp_meeting_dialog'),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(sw ? 'Itisha kikao' : 'Call a meeting', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(key: const Key('grp_meeting_title'), controller: _title, onChanged: (_) => setState(() {}), style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Kichwa' : 'Title')),
          const SizedBox(height: 10),
          ListTile(
            key: const Key('grp_meeting_when'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_rounded, color: Colors.white54),
            title: Text(dateTimeLabel(_iso(_at)), style: const TextStyle(color: Colors.white)),
            onTap: () async {
              final DateTime now = DateTime.now();
              final DateTime? d = await showDatePicker(context: context, initialDate: _at, firstDate: now, lastDate: now.add(const Duration(days: 365)));
              if (d == null || !context.mounted) return;
              final TimeOfDay? t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
              setState(() => _at = DateTime(d.year, d.month, d.day, t?.hour ?? _at.hour, t?.minute ?? _at.minute));
            },
          ),
          TextField(controller: _venue, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Mahali' : 'Where')),
          const SizedBox(height: 10),
          TextField(controller: _agenda, maxLines: 5, minLines: 2, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Ajenda' : 'Agenda')),
          SwitchListTile(
            key: const Key('grp_meeting_notify'),
            contentPadding: EdgeInsets.zero,
            value: _notify,
            onChanged: (final bool v) => setState(() => _notify = v),
            title: Text(sw ? 'Tuma SMS kwa wanachama' : 'Text the members', style: const TextStyle(color: Colors.white)),
          ),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white60))),
        TextButton(
          key: const Key('grp_meeting_next'),
          onPressed: ready
              ? () => Navigator.pop(context, <String, dynamic>{
                    'title': _title.text.trim(),
                    'starts_at': _iso(_at),
                    if (_venue.text.trim().isNotEmpty) 'venue': _venue.text.trim(),
                    if (_agenda.text.trim().isNotEmpty) 'agenda': _agenda.text.trim(),
                    'notify': _notify,
                  })
              : null,
          child: Text(sw ? 'Endelea' : 'Next', style: TextStyle(color: ready ? ThemeConstants.successGreen : Colors.white24, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _NoticeDialog extends StatefulWidget {
  const _NoticeDialog();

  @override
  State<_NoticeDialog> createState() => _NoticeDialogState();
}

class _NoticeDialogState extends State<_NoticeDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  String _audience = 'all';

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final bool ready = _title.text.trim().length >= 3 && _body.text.trim().length >= 3;
    return AlertDialog(
      key: const Key('grp_notice_dialog'),
      backgroundColor: ThemeConstants.bgMid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(sw ? 'Tangazo jipya' : 'New notice', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(key: const Key('grp_notice_title'), controller: _title, onChanged: (_) => setState(() {}), style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Kichwa' : 'Title')),
          const SizedBox(height: 10),
          TextField(key: const Key('grp_notice_body'), controller: _body, onChanged: (_) => setState(() {}), maxLines: 6, minLines: 3, style: const TextStyle(color: Colors.white), decoration: ThemeConstants.darkField(sw ? 'Ujumbe' : 'Message')),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: <Widget>[
            for (final String a in const <String>['all', 'officers'])
              ChoiceChip(label: Text(audienceLabel(sw: sw, audience: a)), selected: _audience == a, onSelected: (_) => setState(() => _audience = a)),
          ]),
        ]),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text(sw ? 'Ghairi' : 'Cancel', style: const TextStyle(color: Colors.white60))),
        TextButton(
          key: const Key('grp_notice_next'),
          onPressed: ready ? () => Navigator.pop(context, <String, dynamic>{'title': _title.text.trim(), 'body': _body.text.trim(), 'audience': _audience}) : null,
          child: Text(sw ? 'Endelea' : 'Next', style: TextStyle(color: ready ? ThemeConstants.successGreen : Colors.white24, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

/// A text to many members: who, what, and how many people and SMS it takes -- shown before it is sent.
class _TextForm extends StatefulWidget {
  const _TextForm({required this.api});

  final GroupsApi api;

  @override
  State<_TextForm> createState() => _TextFormState();
}

class _TextFormState extends State<_TextForm> {
  final TextEditingController _body = TextEditingController();
  String _audience = 'all';
  (int, int, int)? _estimate;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_body.text.trim().length < 2) return;
    try {
      final (int, int, int) e = await widget.api.estimateText(audience: _audience, body: _body.text.trim());
      if (mounted) setState(() => _estimate = e);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  Future<void> _send() async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    await _check();
    final (int, int, int)? e = _estimate;
    if (e == null || !mounted) return;
    if (e.$1 == 0) {
      setState(() => _error = sw ? 'Hakuna wa kutumiwa.' : 'Nobody to send it to.');
      return;
    }
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Tuma ujumbe?' : 'Send this text?',
      message: '${audienceLabel(sw: sw, audience: _audience)}: ${e.$1} ${sw ? 'watu' : 'people'} · ${e.$3} SMS (${e.$2} ${sw ? 'kila mmoja' : 'each'}).\n${_body.text.trim()}',
      yes: sw ? 'Tuma' : 'Send',
      tone: GroupTone.positive,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.sendText(audience: _audience, body: _body.text.trim());
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Ujumbe unatumwa.' : 'The text is going out.');
      Navigator.pop(context, true);
    } on Exception catch (err) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = readableErrorMessage(err);
        });
      }
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(sw ? 'Ujumbe kwa wanachama' : 'Text to members', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const Divider(color: Colors.white12, height: 24),
          Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
            for (final String a in const <String>['all', 'officers', 'overdue'])
              ChoiceChip(
                key: Key('grp_text_aud_$a'),
                label: Text(audienceLabel(sw: sw, audience: a)),
                selected: _audience == a,
                onSelected: (_) => setState(() {
                  _audience = a;
                  _estimate = null;
                }),
              ),
          ]),
          const SizedBox(height: 10),
          TextField(
            key: const Key('grp_text_body'),
            controller: _body,
            maxLength: 640,
            maxLines: 5,
            minLines: 3,
            onChanged: (_) => setState(() => _estimate = null),
            style: const TextStyle(color: Colors.white),
            decoration: ThemeConstants.darkField(sw ? 'Ujumbe (usiandike madeni wala mambo ya siri)' : 'Message (no debts or private matters)'),
          ),
          if (_estimate != null)
            Text(
              '${_estimate!.$1} ${sw ? 'watu' : 'people'} · ${_estimate!.$3} SMS',
              key: const Key('grp_text_estimate'),
              style: const TextStyle(color: ThemeConstants.invAccent, fontWeight: FontWeight.w700),
            ),
          if (_error != null) Text(_error!, style: const TextStyle(color: ThemeConstants.errorText)),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Expanded(
              child: OutlinedButton(
                key: const Key('grp_text_check'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                onPressed: _check,
                child: Text(sw ? 'Hesabu gharama' : 'Count the cost'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                key: const Key('grp_text_send'),
                style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen),
                onPressed: _busy ? null : _send,
                child: Text(sw ? 'Tuma' : 'Send'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
