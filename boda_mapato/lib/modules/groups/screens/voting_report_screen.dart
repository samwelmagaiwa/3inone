import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../constants/theme_constants.dart';
import '../../../services/localization_service.dart';
import '../../../utils/server_message.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_voting_models.dart';
import '../services/group_documents.dart';
import '../services/groups_api.dart';
import 'voting_common.dart';
import 'widgets/groups_ui.dart';

/// The report of ONE voting: participation, the result for each option, the decision, who has taken part (never what they chose in a secret
/// ballot) and, for an open ballot that has closed, who chose what. It can be exported; the server logs every export.
class VotingReportScreen extends StatefulWidget {
  const VotingReportScreen({required this.api, required this.votingId, super.key});

  final GroupsApi api;
  final int votingId;

  @override
  State<VotingReportScreen> createState() => _VotingReportScreenState();
}

class _VotingReportScreenState extends State<VotingReportScreen> {
  VotingReport? _r;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final VotingReport r = await widget.api.votingReport(widget.votingId);
      if (mounted) setState(() => _r = r);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = readableErrorMessage(e));
    }
  }

  Future<void> _export(final GroupVoting v) async {
    final bool sw = context.read<LocalizationService>().isSwahili;
    final bool ok = await groupConfirm(context, title: sw ? 'Hamisha ripoti?' : 'Export the report?', message: '${v.target}\n${sw ? 'Uhamishaji unarekodiwa kwenye kumbukumbu za shughuli.' : 'The export is recorded in the activity log.'}', yes: sw ? 'Hamisha' : 'Export', tone: GroupTone.positive);
    if (!ok || !mounted) return;
    try {
      final Uint8List bytes = await widget.api.votingReportCsv(v.id);
      final VotingReport? r = _r;
      if (r == null || !mounted) return;
      final String group = (await widget.api.me()).groupName ?? '';
      if (!mounted) return;
      await GroupDocuments.shareDoc(context, GroupDocuments.votingDoc(r, sw: sw, group: group, decisionLabel: votingDecisionLabel(sw: sw, decision: r.decision)), sw: sw, csv: bytes);
    } on Exception catch (e) {
      if (mounted) ThemeConstants.showErrorSnackBar(context, readableErrorMessage(e));
    }
  }

  @override
  Widget build(final BuildContext context) {
    final bool sw = context.watch<LocalizationService>().isSwahili;
    final VotingReport? r = _r;
    return Scaffold(
      backgroundColor: ThemeConstants.primaryBlue,
      appBar: ThemeConstants.buildAppBar(sw ? 'Ripoti ya kura' : 'Voting report', flat: true),
      body: SafeArea(
        child: r == null
            ? Center(child: _error == null ? const CircularProgressIndicator() : GroupEmpty(_error!))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: <Widget>[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const Key('grp_vote_export'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: () => _export(r.voting),
                        icon: const Icon(Icons.table_view_rounded),
                        label: Text(sw ? 'Hamisha (PDF, Word, CSV)' : 'Export (PDF, Word, CSV)'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...joinGlowCards(<Widget>[
                      GlowCard(
                        children: <Widget>[
                          Text(r.voting.target, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                          Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
                            GroupPill(votingCategoryLabel(sw: sw, category: r.voting.category), color: ThemeConstants.invAccent),
                            GroupPill(votingStatusLabel(sw: sw, status: r.voting.status), color: votingStatusColor(r.voting.status)),
                            GroupPill(r.voting.secret ? (sw ? 'Kura ya siri' : 'Secret ballot') : (sw ? 'Kura wazi' : 'Open ballot'), color: Colors.white54),
                          ]),
                          GroupDetailRow(sw ? 'Uamuzi' : 'Decision', votingDecisionLabel(sw: sw, decision: r.decision), valueColor: votingDecisionColor(r.decision)),
                          GroupDetailRow(sw ? 'Hali' : 'Standing', r.isFinal ? (sw ? 'Ya mwisho' : 'Final') : (sw ? 'Bado inaendelea' : 'Still running')),
                        ],
                      ),
                      VotingResultsCard(voting: r.voting, results: r.results, sw: sw, decision: r.decision),
                      GlowCard(
                        title: sw ? 'Waliopiga kura (${r.turnout.length})' : 'Who has voted (${r.turnout.length})',
                        dividerKey: 'grp_vote_turnout_div',
                        children: <Widget>[
                          if (r.turnout.isEmpty) Text(sw ? 'Bado hakuna.' : 'Nobody yet.', style: const TextStyle(color: Colors.white60)),
                          for (final Map<String, dynamic> t in r.turnout) _person(t, sw ? 'Alipiga ${t['date']}' : 'Voted ${t['date']}'),
                        ],
                      ),
                      GlowCard(
                        title: sw ? 'Hawajapiga kura (${r.notVoted.length})' : 'Not yet voted (${r.notVoted.length})',
                        dividerKey: 'grp_vote_notvoted_div',
                        children: <Widget>[
                          if (r.notVoted.isEmpty) Text(sw ? 'Wote wameshiriki.' : 'Everyone has taken part.', style: const TextStyle(color: Colors.white60)),
                          for (final Map<String, dynamic> t in r.notVoted) _person(t, ''),
                        ],
                      ),
                      GlowCard(
                        title: sw ? 'Kura za mmoja mmoja' : 'Individual votes',
                        dividerKey: 'grp_vote_individual_div',
                        children: <Widget>[
                          if (r.secret)
                            Text(sw ? 'Kura ya siri: ulichochagua kila mtu hakirekodiwi kamwe.' : 'Secret ballot: what each person chose is never recorded.', key: const Key('grp_vote_secret_note'), style: const TextStyle(color: Colors.white70))
                          else if (r.individual == null)
                            Text(sw ? 'Zitaonekana kura ikifungwa.' : 'They show once the voting has closed.', style: const TextStyle(color: Colors.white70))
                          else
                            for (final Map<String, dynamic> i in r.individual!) _person(i, '${i['option']}'),
                        ],
                      ),
                    ]),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _person(final Map<String, dynamic> t, final String note) => Row(children: <Widget>[
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('${t['name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            if ('${t['member_number'] ?? ''}'.isNotEmpty) Text('${t['member_number']}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
        ),
        if (note.isNotEmpty) Flexible(child: Text(note, textAlign: TextAlign.end, style: const TextStyle(color: Colors.white70, fontSize: 12))),
      ]);
}
