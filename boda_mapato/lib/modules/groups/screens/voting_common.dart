import 'package:flutter/material.dart';

import '../../../constants/theme_constants.dart';
import '../../inventory/screens/widgets/glow_list_card.dart';
import '../models/group_voting_models.dart';

/// The words and colours of voting, in one place so the dashboard, a voting's page, its results and its report all say the same thing.

String votingCategoryLabel({required final bool sw, required final String category}) => switch (category) {
      'leadership' => sw ? 'Uchaguzi wa viongozi' : 'Leadership election',
      'project' => sw ? 'Kuidhinisha mradi' : 'Project approval',
      'financial' => sw ? 'Uamuzi wa fedha' : 'Financial decision',
      'policy' => sw ? 'Mabadiliko ya sera' : 'Policy change',
      'proposal' => sw ? 'Pendekezo' : 'Proposal',
      _ => sw ? 'Uamuzi wa jumla' : 'General decision',
    };

const List<String> votingCategories = <String>['leadership', 'project', 'financial', 'policy', 'proposal', 'general'];

IconData votingCategoryIcon(final String category) => switch (category) {
      'leadership' => Icons.how_to_vote_rounded,
      'project' => Icons.business_center_rounded,
      'financial' => Icons.account_balance_rounded,
      'policy' => Icons.gavel_rounded,
      'proposal' => Icons.lightbulb_rounded,
      _ => Icons.fact_check_rounded,
    };

String votingStatusLabel({required final bool sw, required final String status}) => switch (status) {
      'draft' => sw ? 'Rasimu' : 'Draft',
      'scheduled' => sw ? 'Inakuja' : 'Upcoming',
      'open' => sw ? 'Wazi' : 'Open',
      'paused' => sw ? 'Imesimamishwa' : 'Paused',
      'closed' => sw ? 'Imefungwa' : 'Closed',
      'cancelled' => sw ? 'Imeghairiwa' : 'Cancelled',
      _ => status,
    };

Color votingStatusColor(final String status) => switch (status) {
      'open' => ThemeConstants.successGreen,
      'scheduled' => ThemeConstants.invAccent,
      'paused' => ThemeConstants.warningAmber,
      'cancelled' => ThemeConstants.errorRed,
      'closed' => const Color(0xFF94A3B8),
      _ => Colors.white54,
    };

/// Where the member stands in THIS voting: voted | pending (their vote is awaited) | not eligible | not open yet | over.
String votingMyLabel({required final bool sw, required final String state}) => switch (state) {
      'voted' => sw ? 'Umepiga kura' : 'Voted',
      'pending' => sw ? 'Piga kura sasa' : 'Vote now',
      'not_eligible' => sw ? 'Huruhusiwi' : 'Not eligible',
      'not_open' => sw ? 'Bado haijafunguliwa' : 'Not open yet',
      'over' => sw ? 'Imekwisha' : 'Over',
      _ => '',
    };

Color votingMyColor(final String state) => switch (state) {
      'voted' => ThemeConstants.successGreen,
      'pending' => ThemeConstants.warningAmber,
      _ => Colors.white54,
    };

/// A decision's answers carry their own words (so they follow the language); a candidate is the name given.
String votingOptionLabel({required final bool sw, required final VotingOption option}) => switch (option.role) {
      'approve' => sw ? 'Ndiyo (Kubali)' : 'Approve',
      'reject' => sw ? 'Hapana (Kataa)' : 'Reject',
      'abstain' => sw ? 'Sipigi (Nakaa kimya)' : 'Abstain',
      _ => option.label,
    };

String votingRoleLabel({required final bool sw, required final String? role, required final String label}) => switch (role) {
      'approve' => sw ? 'Ndiyo (Kubali)' : 'Approve',
      'reject' => sw ? 'Hapana (Kataa)' : 'Reject',
      'abstain' => sw ? 'Sipigi (Nakaa kimya)' : 'Abstain',
      _ => label,
    };

/// Function colours: approve green, reject red, abstain amber; a candidate takes the accent.
Color votingOptionColor(final String? role) => switch (role) {
      'approve' => ThemeConstants.successGreen,
      'reject' => ThemeConstants.errorRed,
      'abstain' => ThemeConstants.warningAmber,
      _ => ThemeConstants.invAccent,
    };

String votingEligibilityLabel({required final bool sw, required final GroupVoting v}) => switch (v.eligibility) {
      'selected' => sw ? 'Wanachama waliochaguliwa (${v.eligibleCount})' : 'Selected members (${v.eligibleCount})',
      _ => sw ? 'Wanachama wote hai (${v.eligibleCount})' : 'All active members (${v.eligibleCount})',
    };

String votingVisibilityLabel({required final bool sw, required final String visibility}) => switch (visibility) {
      'live' => sw ? 'Matokeo yanaonekana wakati kura inaendelea' : 'Results show while the voting runs',
      'after_publish' => sw ? 'Matokeo yanaonekana baada ya kutangazwa rasmi' : 'Results show once the leaders of the group announce them',
      _ => sw ? 'Matokeo yanaonekana kura ikifungwa' : 'Results show when the voting closes',
    };

String votingDecisionLabel({required final bool sw, required final String decision}) => switch (decision) {
      'passed' => sw ? 'Imepitishwa' : 'Passed',
      'failed' => sw ? 'Haijapitishwa' : 'Did not pass',
      'winner' => sw ? 'Mshindi amepatikana' : 'A winner',
      'tie' => sw ? 'Sare: kura zimelingana' : 'A tie: the votes are equal',
      'no_quorum' => sw ? 'Idadi ya wapiga kura haikutosha' : 'Not enough voters (no quorum)',
      _ => sw ? 'Hakuna kura zilizopigwa' : 'No votes were cast',
    };

Color votingDecisionColor(final String decision) => switch (decision) {
      'passed' || 'winner' => ThemeConstants.successGreen,
      'failed' => ThemeConstants.errorRed,
      'tie' || 'no_quorum' => ThemeConstants.warningAmber,
      _ => Colors.white54,
    };

/// "05/12/2026 14:00" from the server's "2026-12-05 14:00:00".
String votingWhen(final String? at) {
  if (at == null || at.isEmpty) return '-';
  final DateTime? d = DateTime.tryParse(at.replaceFirst(' ', 'T'));
  if (d == null) return at;
  String two(final int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// The results of ONE voting: the decision, each option's votes and share, and who took part. It never shows anything of another voting.
class VotingResultsCard extends StatelessWidget with GlowSectionWidget {
  const VotingResultsCard({required this.voting, required this.results, required this.sw, super.key, this.decision});

  final GroupVoting voting;
  final VotingResults results;
  final bool sw;

  /// The decision as it stands (final once the voting has closed).
  final String? decision;

  @override
  Widget build(final BuildContext context) {
    final String d = decision ?? voting.decision ?? results.decision;
    final bool closed = voting.status == 'closed';
    final int top = results.options.fold<int>(0, (final int a, final VotingResultRow r) => r.votes > a ? r.votes : a);
    return GlowCard(
      title: sw ? 'Matokeo' : 'Results',
      dividerKey: 'grp_vote_results_div',
      children: <Widget>[
        Container(
          key: const Key('grp_vote_decision'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: votingDecisionColor(d).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12), border: Border.all(color: votingDecisionColor(d).withValues(alpha: 0.7))),
          child: Row(children: <Widget>[
            Icon(closed ? Icons.verified_rounded : Icons.hourglass_top_rounded, color: votingDecisionColor(d), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                closed ? votingDecisionLabel(sw: sw, decision: d) : '${sw ? 'Hadi sasa' : 'So far'}: ${votingDecisionLabel(sw: sw, decision: d)}',
                style: TextStyle(color: Color.lerp(votingDecisionColor(d), Colors.white, 0.6), fontWeight: FontWeight.w800),
              ),
            ),
          ]),
        ),
        Column(children: <Widget>[
          for (final VotingResultRow r in results.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  if (closed && voting.winnerOptionId == r.optionId) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD166), size: 18)),
                  Expanded(child: Text(votingRoleLabel(sw: sw, role: r.role, label: r.label), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                  Text('${r.votes}  ·  ${r.percent.toStringAsFixed(1)}%', key: Key('grp_vote_result_${r.optionId}'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (r.percent / 100).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(votingOptionColor(r.role).withValues(alpha: r.votes == top && top > 0 ? 1 : 0.65)),
                  ),
                ),
              ]),
            ),
        ]),
        Column(children: <Widget>[
          _line(sw ? 'Waliopiga kura' : 'Voted', '${results.turnout} / ${results.eligible} (${results.participationPercent.toStringAsFixed(1)}%)'),
          if (results.quorumPercent > 0)
            _line(sw ? 'Idadi ya chini' : 'Quorum', '${results.quorumPercent.toStringAsFixed(0)}% · ${results.quorumMet ? (sw ? 'imefikiwa' : 'met') : (sw ? 'haijafikiwa' : 'not met')}'),
          if (!voting.isElection) _line(sw ? 'Kiwango cha kupita' : 'Approval needed', '${results.thresholdPercent.toStringAsFixed(1)}%'),
        ]),
      ],
    );
  }

  Widget _line(final String label, final String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: <Widget>[
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13))),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}
