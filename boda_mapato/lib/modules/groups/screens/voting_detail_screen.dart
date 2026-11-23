import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_models.dart';
import '../models/group_voting_models.dart';
import '../services/groups_api.dart';
import 'voting_common.dart';
import 'voting_form_screen.dart';
import 'voting_report_screen.dart';
import 'widgets/groups_ui.dart';

/// ONE voting: exactly what is voted on (the position and its candidates, or the agenda), the background, the dates and rules, who may vote,
/// where the member stands, the choice (candidates for a position, approve / reject / abstain for an agenda), the confirmation, and the
/// result when the voting's own rules allow it to be seen. Officers who run votings have a Manage button at the top.
class VotingDetailScreen extends StatefulWidget {
  const VotingDetailScreen({required this.api, required this.me, required this.votingId, super.key});

  final GroupsApi api;
  final GroupMe me;
  final int votingId;

  @override
  State<VotingDetailScreen> createState() => _VotingDetailScreenState();
}

class _VotingDetailScreenState extends State<VotingDetailScreen> {
  GroupVoting? _v;
  String? _error;
  int? _picked;
  bool _busy = false;
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final GroupVoting v = await widget.api.voting(widget.votingId);
      if (mounted) {
        setState(() {
          _v = v;
          _error = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  /// The confirmation: the exact voting and the exact choice, then the vote goes in.
  Future<void> _submit(final GroupVoting v) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final VotingOption? o = v.option(_picked);
    if (o == null) return;
    final bool ok = await groupConfirm(
      context,
      title: sw ? 'Thibitisha kura yako' : 'Confirm your vote',
      message: '${sw ? 'Kura' : 'Voting'}: ${v.target}\n${sw ? 'Chaguo lako' : 'Your choice'}: ${votingOptionLabel(sw: sw, option: o)}\n\n'
          '${v.allowChange && !v.secret ? (sw ? 'Unaweza kubadilisha kura yako hadi kura ifungwe.' : 'You may change your vote until the voting closes.') : (sw ? 'Huwezi kubadilisha kura baada ya kuituma.' : 'You cannot change it after you submit.')}',
      yes: sw ? 'Tuma kura' : 'Submit vote',
      tone: GroupTone.positive,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final GroupVoting after = await widget.api.vote(v.id, o.id);
      if (!mounted) return;
      ThemeConstants.showSuccessSnackBar(context, sw ? 'Kura yako ya "${v.target}" imetumwa.' : 'Your vote in "${v.target}" was submitted.');
      setState(() {
        _v = after;
        _picked = null;
        _changing = false;
      });
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  // ---------------------------------------------------------------- the officers' side

  Future<void> _manage(final GroupVoting v) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final bool mayPublish = widget.me.can('publish_voting_results');
    final String? pick = await groupActions(context, title: v.target, actions: <GroupSheetAction>[
      if (v.status == 'draft') GroupSheetAction(icon: Icons.edit_rounded, label: sw ? 'Hariri rasimu' : 'Edit the draft', value: 'edit'),
      if (v.status == 'draft') GroupSheetAction(icon: Icons.rocket_launch_rounded, label: sw ? 'Chapisha' : 'Publish', value: 'publish', tone: GroupTone.positive),
      if (v.status == 'open') GroupSheetAction(icon: Icons.pause_circle_rounded, label: sw ? 'Simamisha' : 'Pause', value: 'pause'),
      if (v.status == 'paused') GroupSheetAction(icon: Icons.play_circle_rounded, label: sw ? 'Endeleza' : 'Resume', value: 'resume', tone: GroupTone.positive),
      if (<String>['scheduled', 'open', 'paused'].contains(v.status)) GroupSheetAction(icon: Icons.update_rounded, label: sw ? 'Ongeza muda wa kufunga' : 'Extend the closing time', value: 'extend'),
      if (<String>['open', 'paused'].contains(v.status)) GroupSheetAction(icon: Icons.lock_rounded, label: sw ? 'Funga sasa' : 'Close now', value: 'close', tone: GroupTone.danger),
      if (<String>['draft', 'scheduled', 'open', 'paused'].contains(v.status)) GroupSheetAction(icon: Icons.cancel_rounded, label: sw ? 'Ghairi' : 'Cancel', value: 'cancel', tone: GroupTone.danger),
      if (v.status == 'closed' && !v.resultsPublished && mayPublish) GroupSheetAction(icon: Icons.campaign_rounded, label: sw ? 'Tangaza matokeo' : 'Announce the results', value: 'results', tone: GroupTone.positive),
      if (v.status == 'draft') GroupSheetAction(icon: Icons.delete_outline_rounded, label: sw ? 'Futa rasimu' : 'Delete the draft', value: 'delete', tone: GroupTone.danger),
    ]);
    if (pick == null || !mounted) return;
    try {
      switch (pick) {
        case 'edit':
          final GroupVoting? saved = await Navigator.push<GroupVoting>(context, MaterialPageRoute<GroupVoting>(builder: (_) => VotingFormScreen(api: widget.api, existing: v)));
          if (saved != null) await _load();
        case 'publish':
          if (await groupConfirm(context, title: sw ? 'Chapisha kura hii?' : 'Publish this voting?', message: '${v.target}\n${sw ? 'Wapiga kura ${v.eligibleCount} wataarifiwa. Baada ya kuchapisha haibadilishwi.' : '${v.eligibleCount} voters will be told. It cannot be edited once published.'}', yes: sw ? 'Chapisha' : 'Publish', tone: GroupTone.positive)) {
            _set(await widget.api.votingAction(v.id, 'publish'));
          }
        case 'pause':
          _set(await widget.api.votingAction(v.id, 'pause'));
        case 'resume':
          _set(await widget.api.votingAction(v.id, 'resume'));
        case 'extend':
          await _extend(v, sw);
        case 'close':
          if (await groupConfirm(context, title: sw ? 'Funga kura sasa?' : 'Close this voting now?', message: '${v.target}\n${sw ? 'Hakuna kura itakayokubaliwa tena.' : 'No more votes will be accepted.'}', yes: sw ? 'Funga' : 'Close', tone: GroupTone.danger)) {
            _set(await widget.api.votingAction(v.id, 'close'));
          }
        case 'cancel':
          final String? why = await groupReason(context, title: sw ? 'Ghairi kura hii' : 'Cancel this voting', yes: sw ? 'Ghairi' : 'Cancel it', message: v.target);
          if (why != null) _set(await widget.api.votingAction(v.id, 'cancel', body: <String, dynamic>{'reason': why}));
        case 'results':
          if (await groupConfirm(context, title: sw ? 'Tangaza matokeo?' : 'Announce the results?', message: '${v.target}\n${sw ? 'Wapiga kura wote wataona matokeo.' : 'All voters will see the result.'}', yes: sw ? 'Tangaza' : 'Announce', tone: GroupTone.positive)) {
            _set(await widget.api.votingAction(v.id, 'publish-results'));
          }
        case 'delete':
          if (await groupConfirm(context, title: sw ? 'Futa rasimu?' : 'Delete the draft?', message: v.target, yes: sw ? 'Futa' : 'Delete', tone: GroupTone.danger)) {
            await widget.api.deleteVoting(v.id);
            if (mounted) Navigator.pop(context, true);
          }
      }
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  void _set(final GroupVoting v) {
    if (mounted) setState(() => _v = v);
  }

  Future<void> _extend(final GroupVoting v, final bool sw) async {
    final DateTime base = DateTime.tryParse((v.closesAt ?? '').replaceFirst(' ', 'T')) ?? DateTime.now();
    final DateTime? day = await showDatePicker(context: context, initialDate: base.isAfter(DateTime.now()) ? base : DateTime.now().add(const Duration(days: 1)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (day == null || !mounted) return;
    final TimeOfDay? time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (time == null || !mounted) return;
    final DateTime at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    String two(final int n) => n.toString().padLeft(2, '0');
    final String iso = '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}:00';
    _set(await widget.api.votingAction(v.id, 'extend', body: <String, dynamic>{'closes_at': iso}));
  }

  // ---------------------------------------------------------------- the page

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final GroupVoting? v = _v;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(v?.target ?? (sw ? 'Kura' : 'Voting'), flat: true),
      body: SafeArea(
        child: v == null
            ? Center(child: _error == null ? const CircularProgressIndicator() : GroupEmpty(_error!))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: <Widget>[
                    // The buttons come first, then the sections.
                    if (v.canManage || v.canReport)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(children: <Widget>[
                          if (v.canManage)
                            Expanded(
                              child: FilledButton.icon(
                                key: const Key('grp_vote_manage'),
                                style: FilledButton.styleFrom(backgroundColor: ThemeConstants.primaryOrange),
                                onPressed: () => _manage(v),
                                icon: const Icon(Icons.settings_rounded),
                                label: Text(sw ? 'Simamia' : 'Manage'),
                              ),
                            ),
                          if (v.canManage && v.canReport && v.status != 'draft') const SizedBox(width: 10),
                          if (v.canReport && v.status != 'draft')
                            Expanded(
                              child: OutlinedButton.icon(
                                key: const Key('grp_vote_report'),
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                                onPressed: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => VotingReportScreen(api: widget.api, votingId: v.id))),
                                icon: const Icon(Icons.insights_rounded),
                                label: Text(sw ? 'Ripoti' : 'Report'),
                              ),
                            ),
                        ]),
                      ),
                    ...joinGlowCards(<Widget>[
                      _headCard(v, sw),
                      _aboutCard(v, sw),
                      _myCard(v, sw),
                      if (v.results != null) VotingResultsCard(voting: v, results: v.results!, sw: sw, decision: v.decision),
                    ]),
                  ],
                ),
              ),
      ),
    );
  }

  /// What exactly is being voted on, in the plainest words, with its status and the member's own state.
  Widget _headCard(final GroupVoting v, final bool sw) => GlowCard(
        children: <Widget>[
          Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
            GroupPill(votingCategoryLabel(sw: sw, category: v.category), color: ThemeConstants.invAccent),
            GroupPill(votingStatusLabel(sw: sw, status: v.status), color: votingStatusColor(v.status)),
            if (votingMyLabel(sw: sw, state: v.my.state).isNotEmpty) GroupPill(votingMyLabel(sw: sw, state: v.my.state), color: votingMyColor(v.my.state)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(v.isElection ? (sw ? 'Nafasi inayogombewa' : 'Position being elected') : (sw ? 'Ajenda' : 'Agenda'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 2),
            Text(v.isElection ? (v.position ?? v.title) : v.title, key: const Key('grp_vote_target'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
            if (v.series != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(v.series!, style: const TextStyle(color: Color(0xFFFFD166), fontSize: 13, fontWeight: FontWeight.w700))),
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(v.reference, style: const TextStyle(color: Colors.white38, fontSize: 11))),
          ]),
          if (v.status == 'cancelled' && v.cancelReason != null) GroupDetailRow(sw ? 'Sababu ya kughairi' : 'Why it was cancelled', v.cancelReason!),
        ],
      );

  Widget _aboutCard(final GroupVoting v, final bool sw) => GlowCard(
        title: sw ? 'Kuhusu kura hii' : 'About this voting',
        dividerKey: 'grp_vote_about_div',
        children: <Widget>[
          if (v.description != null) Text(v.description!, key: const Key('grp_vote_description'), style: const TextStyle(color: Colors.white70, height: 1.35)),
          GroupDetailRow(sw ? 'Inafunguliwa' : 'Opens', votingWhen(v.opensAt)),
          GroupDetailRow(sw ? 'Inafungwa' : 'Closes', votingWhen(v.closesAt)),
          GroupDetailRow(sw ? 'Wanaoruhusiwa' : 'Who may vote', votingEligibilityLabel(sw: sw, v: v)),
          GroupDetailRow(sw ? 'Aina ya kura' : 'Ballot', v.secret ? (sw ? 'Ya siri: hakuna anayejua ulichagua nini' : 'Secret: nobody sees what you chose') : (sw ? 'Wazi: viongozi wanaweza kuona kila kura' : 'Open: the leaders of the group can see each vote')),
          if (v.quorumPercent > 0) GroupDetailRow(sw ? 'Idadi ya chini ya wapiga kura' : 'Quorum', '${v.quorumPercent.toStringAsFixed(0)}%'),
          if (!v.isElection) GroupDetailRow(sw ? 'Kiwango cha kupita' : 'Approval needed', '${v.thresholdPercent.toStringAsFixed(1)}%'),
          GroupDetailRow(sw ? 'Matokeo' : 'Results', votingVisibilityLabel(sw: sw, visibility: v.resultsVisibility)),
          if (v.progress != null)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Expanded(child: Text(sw ? 'Ushiriki' : 'Participation', style: const TextStyle(color: Colors.white60, fontSize: 13))),
                Text('${v.progress!.turnout} / ${v.progress!.eligible} (${v.progress!.percent.toStringAsFixed(0)}%)', key: const Key('grp_vote_progress'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: (v.progress!.percent / 100).clamp(0.0, 1.0), minHeight: 6, backgroundColor: Colors.white.withValues(alpha: 0.08), valueColor: const AlwaysStoppedAnimation<Color>(ThemeConstants.invAccent))),
            ]),
        ],
      );

  /// The member's own part: the choice to make, or where they stand.
  Widget _myCard(final GroupVoting v, final bool sw) {
    final bool choosing = v.my.canVote && (!v.my.voted || _changing);
    final VotingOption? chosen = v.option(v.my.choice);
    return GlowCard(
      title: v.isElection ? (sw ? 'Wagombea' : 'Candidates') : (sw ? 'Uamuzi wako' : 'Your decision'),
      dividerKey: 'grp_vote_my_div',
      children: <Widget>[
        if (v.my.voted && !_changing)
          Container(
            key: const Key('grp_vote_done'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: ThemeConstants.successGreen.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12), border: Border.all(color: ThemeConstants.successGreen.withValues(alpha: 0.7))),
            child: Row(children: <Widget>[
              const Icon(Icons.check_circle_rounded, color: ThemeConstants.successGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  chosen != null ? '${sw ? 'Umepiga kura: ' : 'You voted: '}${votingOptionLabel(sw: sw, option: chosen)}' : (sw ? 'Umepiga kura. Kura yako imehifadhiwa kwa siri.' : 'You have voted. Your vote is kept secret.'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
        if (v.my.voted && !_changing && v.my.canVote)
          TextButton.icon(key: const Key('grp_vote_change'), onPressed: () => setState(() => _changing = true), icon: const Icon(Icons.edit_rounded, color: ThemeConstants.primaryOrange), label: Text(sw ? 'Badilisha kura yangu' : 'Change my vote', style: const TextStyle(color: ThemeConstants.primaryOrange))),
        if (!v.my.voted && !v.my.canVote) Text(_why(v, sw), key: const Key('grp_vote_why'), style: const TextStyle(color: Colors.white70)),
        if (choosing) ...<Widget>[
          if (v.isElection) _candidates(v, sw) else _agenda(v, sw),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('grp_vote_review'),
              style: FilledButton.styleFrom(backgroundColor: ThemeConstants.successGreen, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _picked == null || _busy ? null : () => _submit(v),
              icon: const Icon(Icons.how_to_vote_rounded),
              label: Text(sw ? 'Hakiki na utume kura' : 'Review and submit my vote'),
            ),
          ),
        ] else if (v.isElection && !v.my.voted)
          // Not voting (yet): the candidates are still shown, plainly, so the member knows who stands.
          _candidates(v, sw, readOnly: true),
      ],
    );
  }

  String _why(final GroupVoting v, final bool sw) => switch (v.my.state) {
        'not_eligible' => sw ? 'Huruhusiwi kupiga kura hii.' : 'You may not vote in this one.',
        'not_open' => sw ? 'Kura itafunguliwa ${votingWhen(v.opensAt)}.' : 'Voting opens ${votingWhen(v.opensAt)}.',
        'draft' => sw ? 'Hii ni rasimu; haijachapishwa.' : 'This is a draft; it is not published.',
        'not_a_member' => sw ? 'Ni wanachama tu wanaopiga kura.' : 'Only members vote.',
        _ => v.status == 'paused' ? (sw ? 'Kura imesimamishwa kwa muda.' : 'Voting is paused for now.') : (sw ? 'Kura imekwisha.' : 'Voting is over.'),
      };

  /// Candidate selection: each candidate of THIS position, with what is known of them.
  Widget _candidates(final GroupVoting v, final bool sw, {final bool readOnly = false}) => Column(
        key: const Key('grp_vote_candidates'),
        children: <Widget>[
          for (final VotingOption o in v.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                key: Key('grp_vote_opt_${o.id}'),
                borderRadius: BorderRadius.circular(14),
                onTap: readOnly ? null : () => setState(() => _picked = o.id),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: _picked == o.id ? ThemeConstants.invAccent.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.04),
                    border: Border.all(color: _picked == o.id ? Colors.white : Colors.white24, width: _picked == o.id ? 1.6 : 1),
                  ),
                  child: Row(children: <Widget>[
                    CircleAvatar(radius: 20, backgroundColor: ThemeConstants.invAccent.withValues(alpha: 0.3), child: Text(o.label.isEmpty ? '?' : o.label.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        Text(o.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        if (o.description != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(o.description!, style: const TextStyle(color: Colors.white60, fontSize: 12))),
                      ]),
                    ),
                    if (!readOnly) Icon(_picked == o.id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: _picked == o.id ? Colors.white : Colors.white38),
                  ]),
                ),
              ),
            ),
        ],
      );

  /// Agenda decision: the answers of THIS agenda, each in its own colour.
  Widget _agenda(final GroupVoting v, final bool sw) => Column(
        key: const Key('grp_vote_agenda'),
        children: <Widget>[
          for (final VotingOption o in v.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: Key('grp_vote_opt_${o.id}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: _picked == o.id ? votingOptionColor(o.role).withValues(alpha: 0.4) : votingOptionColor(o.role).withValues(alpha: 0.1),
                    side: BorderSide(color: votingOptionColor(o.role), width: _picked == o.id ? 2.2 : 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => setState(() => _picked = o.id),
                  icon: Icon(o.role == 'approve' ? Icons.thumb_up_alt_rounded : (o.role == 'reject' ? Icons.thumb_down_alt_rounded : Icons.remove_circle_outline_rounded), color: votingOptionColor(o.role)),
                  label: Text(votingOptionLabel(sw: sw, option: o), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
        ],
      );
}
