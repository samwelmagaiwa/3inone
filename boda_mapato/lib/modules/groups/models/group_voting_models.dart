/// Voting of the Groups (Vikundi) service, typed once here. Every voting process is independent: nothing here ever joins the options, ballots or
/// results of two processes.
library;

double _num(final Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

int? _int(final Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String? _str(final Object? v) => v == null || '$v'.isEmpty ? null : '$v';

Map<String, dynamic> _map(final Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class VotingOption {
  const VotingOption({required this.id, required this.label, this.description, this.memberId, this.role});

  factory VotingOption.fromJson(final Map<String, dynamic> j) =>
      VotingOption(id: _int(j['id']) ?? 0, label: '${j['label'] ?? ''}', description: _str(j['description']), memberId: _int(j['member_id']), role: _str(j['role']));

  final int id;
  final String label;
  final String? description;

  /// The candidate, when the option is a member.
  final int? memberId;

  /// A decision's answer: approve | reject | abstain.
  final String? role;
}

class VotingResultRow {
  const VotingResultRow({required this.optionId, required this.label, required this.votes, required this.percent, this.role, this.memberId});

  factory VotingResultRow.fromJson(final Map<String, dynamic> j) => VotingResultRow(
        optionId: _int(j['option_id']) ?? 0,
        label: '${j['label'] ?? ''}',
        votes: _int(j['votes']) ?? 0,
        percent: _num(j['percent']),
        role: _str(j['role']),
        memberId: _int(j['member_id']),
      );

  final int optionId;
  final String label;
  final int votes;
  final double percent;
  final String? role;
  final int? memberId;
}

class VotingResults {
  const VotingResults({
    required this.options,
    required this.ballots,
    required this.turnout,
    required this.eligible,
    required this.participationPercent,
    required this.quorumPercent,
    required this.quorumMet,
    required this.thresholdPercent,
    required this.decision,
    this.winnerOptionId,
  });

  factory VotingResults.fromJson(final Map<String, dynamic> j) => VotingResults(
        options: <VotingResultRow>[for (final dynamic o in (j['options'] as List? ?? const <dynamic>[])) VotingResultRow.fromJson(_map(o))],
        ballots: _int(j['ballots']) ?? 0,
        turnout: _int(j['turnout']) ?? 0,
        eligible: _int(j['eligible']) ?? 0,
        participationPercent: _num(j['participation_percent']),
        quorumPercent: _num(j['quorum_percent']),
        quorumMet: j['quorum_met'] == true,
        thresholdPercent: _num(j['threshold_percent']),
        decision: '${j['decision'] ?? 'none'}',
        winnerOptionId: _int(j['winner_option_id']),
      );

  final List<VotingResultRow> options;
  final int ballots;
  final int turnout;
  final int eligible;
  final double participationPercent;
  final double quorumPercent;
  final bool quorumMet;
  final double thresholdPercent;

  /// passed | failed | no_quorum | winner | tie | none
  final String decision;
  final int? winnerOptionId;
}

class VotingMy {
  const VotingMy({required this.eligible, required this.voted, required this.state, required this.canVote, this.choice});

  factory VotingMy.fromJson(final Map<String, dynamic> j) =>
      VotingMy(eligible: j['eligible'] == true, voted: j['voted'] == true, state: '${j['state'] ?? ''}', canVote: j['can_vote'] == true, choice: _int(j['choice']));

  final bool eligible;
  final bool voted;

  /// voted | pending | not_eligible | not_open | over | draft | not_a_member
  final String state;
  final bool canVote;

  /// What the member chose, only in an open ballot.
  final int? choice;
}

class VotingProgress {
  const VotingProgress({required this.turnout, required this.eligible, required this.percent});

  factory VotingProgress.fromJson(final Map<String, dynamic> j) => VotingProgress(turnout: _int(j['turnout']) ?? 0, eligible: _int(j['eligible']) ?? 0, percent: _num(j['percent']));

  final int turnout;
  final int eligible;
  final double percent;
}

class GroupVoting {
  const GroupVoting({
    required this.id,
    required this.reference,
    required this.category,
    required this.kind,
    required this.title,
    required this.target,
    required this.eligibility,
    required this.quorumPercent,
    required this.thresholdPercent,
    required this.secret,
    required this.allowChange,
    required this.showProgress,
    required this.resultsVisibility,
    required this.status,
    required this.eligibleCount,
    required this.resultsPublished,
    required this.my,
    required this.buckets,
    required this.options,
    required this.canManage,
    required this.canReport,
    this.series,
    this.description,
    this.position,
    this.opensAt,
    this.closesAt,
    this.cancelReason,
    this.progress,
    this.results,
    this.decision,
    this.winnerOptionId,
  });

  factory GroupVoting.fromJson(final Map<String, dynamic> j) => GroupVoting(
        id: _int(j['id']) ?? 0,
        reference: '${j['reference'] ?? ''}',
        series: _str(j['series']),
        category: '${j['category'] ?? 'general'}',
        kind: '${j['kind'] ?? 'decision'}',
        title: '${j['title'] ?? ''}',
        description: _str(j['description']),
        position: _str(j['position']),
        target: '${j['target'] ?? j['title'] ?? ''}',
        eligibility: '${j['eligibility'] ?? 'active'}',
        quorumPercent: _num(j['quorum_percent']),
        thresholdPercent: _num(j['threshold_percent']),
        secret: j['secret'] != false,
        allowChange: j['allow_change'] == true,
        showProgress: j['show_progress'] != false,
        resultsVisibility: '${j['results_visibility'] ?? 'after_close'}',
        opensAt: _str(j['opens_at']),
        closesAt: _str(j['closes_at']),
        status: '${j['status'] ?? 'draft'}',
        cancelReason: _str(j['cancel_reason']),
        eligibleCount: _int(j['eligible_count']) ?? 0,
        resultsPublished: j['results_published'] == true,
        my: VotingMy.fromJson(_map(j['my'])),
        buckets: <String>[for (final dynamic b in (j['buckets'] as List? ?? const <dynamic>[])) '$b'],
        options: <VotingOption>[for (final dynamic o in (j['options'] as List? ?? const <dynamic>[])) VotingOption.fromJson(_map(o))],
        canManage: j['can_manage'] == true,
        canReport: j['can_report'] == true,
        progress: j['progress'] is Map ? VotingProgress.fromJson(_map(j['progress'])) : null,
        results: j['results'] is Map ? VotingResults.fromJson(_map(j['results'])) : null,
        decision: _str(j['decision']),
        winnerOptionId: _int(j['winner_option_id']),
      );

  final int id;
  final String reference;
  final String? series;

  /// leadership | project | financial | policy | proposal | general
  final String category;

  /// election (candidates for ONE position) | decision (approve / reject / abstain on ONE agenda)
  final String kind;
  final String title;
  final String? description;
  final String? position;

  /// The exact thing voted on, as the server names it.
  final String target;

  /// active (every member) | selected
  final String eligibility;
  final double quorumPercent;
  final double thresholdPercent;
  final bool secret;
  final bool allowChange;
  final bool showProgress;

  /// live | after_close | after_publish
  final String resultsVisibility;
  final String? opensAt;
  final String? closesAt;

  /// draft | scheduled | open | paused | closed | cancelled
  final String status;
  final String? cancelReason;
  final int eligibleCount;
  final bool resultsPublished;
  final VotingMy my;

  /// active | upcoming | pending | completed | closed | draft
  final List<String> buckets;
  final List<VotingOption> options;
  final bool canManage;
  final bool canReport;
  final VotingProgress? progress;
  final VotingResults? results;
  final String? decision;
  final int? winnerOptionId;

  bool get isElection => kind == 'election';

  VotingOption? option(final int? id) {
    for (final VotingOption o in options) {
      if (o.id == id) return o;
    }
    return null;
  }
}

class VotingReport {
  const VotingReport({required this.voting, required this.results, required this.decision, required this.turnout, required this.notVoted, required this.secret, required this.isFinal, this.individual});

  factory VotingReport.fromJson(final Map<String, dynamic> j) => VotingReport(
        voting: GroupVoting.fromJson(_map(j['voting'])),
        results: VotingResults.fromJson(_map(j['results'])),
        decision: '${j['decision'] ?? 'none'}',
        turnout: <Map<String, dynamic>>[for (final dynamic t in (j['turnout'] as List? ?? const <dynamic>[])) _map(t)],
        notVoted: <Map<String, dynamic>>[for (final dynamic t in (j['not_voted'] as List? ?? const <dynamic>[])) _map(t)],
        individual: j['individual'] is List ? <Map<String, dynamic>>[for (final dynamic t in (j['individual'] as List)) _map(t)] : null,
        secret: j['secret'] != false,
        isFinal: j['final'] == true,
      );

  final GroupVoting voting;
  final VotingResults results;
  final String decision;

  /// Who has taken part (never what they chose).
  final List<Map<String, dynamic>> turnout;
  final List<Map<String, dynamic>> notVoted;

  /// Who chose what: only for an open ballot, once it has closed.
  final List<Map<String, dynamic>>? individual;
  final bool secret;
  final bool isFinal;
}

class GroupNotice {
  const GroupNotice({required this.id, required this.kind, required this.title, required this.titleEn, required this.read, required this.createdAt, this.body, this.bodyEn, this.linkType, this.linkId});

  factory GroupNotice.fromJson(final Map<String, dynamic> j) => GroupNotice(
        id: _int(j['id']) ?? 0,
        kind: '${j['kind'] ?? ''}',
        title: '${j['title'] ?? ''}',
        titleEn: '${j['title_en'] ?? ''}',
        body: _str(j['body']),
        bodyEn: _str(j['body_en']),
        linkType: _str(j['link_type']),
        linkId: _int(j['link_id']),
        read: j['read'] == true,
        createdAt: '${j['created_at'] ?? ''}',
      );

  final int id;
  final String kind;
  final String title;
  final String titleEn;
  final String? body;
  final String? bodyEn;

  /// voting: opens that exact voting item.
  final String? linkType;
  final int? linkId;
  final bool read;
  final String createdAt;
}
