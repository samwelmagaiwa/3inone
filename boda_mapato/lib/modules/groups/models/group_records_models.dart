/// Invitations, the referral tree, documents and reports of the Groups (Vikundi) service.
library;

double _num(final Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

int? _int(final Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String? _str(final Object? v) => v == null || '$v'.isEmpty ? null : '$v';

class GroupInvitation {
  const GroupInvitation({required this.id, required this.code, required this.kind, required this.active, required this.used});

  factory GroupInvitation.fromJson(final Map<String, dynamic> j) =>
      GroupInvitation(id: _int(j['id']) ?? 0, code: '${j['code'] ?? ''}', kind: '${j['kind'] ?? 'member'}', active: j['active'] != false, used: _int(j['used']) ?? 0);

  final int id;
  final String code;

  /// member | group
  final String kind;
  final bool active;
  final int used;
}

/// One person in the referral tree.
class GroupTreeNode {
  const GroupTreeNode({required this.id, required this.name, required this.status, this.memberNumber, this.referrerId, this.joinedOn, this.founding = false, this.office});

  factory GroupTreeNode.fromJson(final Map<String, dynamic> j) => GroupTreeNode(
        id: _int(j['id']) ?? 0,
        name: '${j['name'] ?? ''}',
        status: '${j['status'] ?? 'active'}',
        memberNumber: _str(j['member_number']),
        referrerId: _int(j['referrer_id']),
        joinedOn: _str(j['joined_on']),
        founding: j['founding'] == true,
        office: _str(j['office']),
      );

  final int id;
  final String name;
  final String status;
  final String? memberNumber;
  final int? referrerId;
  final String? joinedOn;
  final bool founding;
  final String? office;
}

class GroupDocument {
  const GroupDocument({required this.id, required this.kind, this.caption, this.url});

  factory GroupDocument.fromJson(final Map<String, dynamic> j) => GroupDocument(id: _int(j['id']) ?? 0, kind: '${j['kind'] ?? 'other'}', caption: _str(j['caption']), url: _str(j['url']));

  final int id;

  /// photo | id | other
  final String kind;
  final String? caption;
  final String? url;
}

/// The group in numbers for a period.
class GroupReport {
  const GroupReport({required this.byStatus, required this.joined, required this.money, required this.contributions, required this.loans, required this.meetingsHeld});

  factory GroupReport.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> members = j['members'] is Map ? Map<String, dynamic>.from(j['members'] as Map) : <String, dynamic>{};
    return GroupReport(
      byStatus: <String, int>{if (members['by_status'] is Map) for (final MapEntry<dynamic, dynamic> e in (members['by_status'] as Map).entries) '${e.key}': _int(e.value) ?? 0},
      joined: _int(members['joined']) ?? 0,
      money: <String, (double, double)>{
        if (j['money'] is Map)
          for (final MapEntry<dynamic, dynamic> e in (j['money'] as Map).entries)
            '${e.key}': (_num((e.value as Map)['in']), _num((e.value as Map)['out'])),
      },
      contributions: <String, double>{if (j['contributions'] is Map) for (final MapEntry<dynamic, dynamic> e in (j['contributions'] as Map).entries) '${e.key}': _num(e.value)},
      loans: <String, double>{if (j['loans_now'] is Map) for (final MapEntry<dynamic, dynamic> e in (j['loans_now'] as Map).entries) '${e.key}': _num(e.value)},
      meetingsHeld: _int(j['meetings_held']) ?? 0,
    );
  }

  final Map<String, int> byStatus;
  final int joined;

  /// kind of money => (in, out)
  final Map<String, (double, double)> money;
  final Map<String, double> contributions;
  final Map<String, double> loans;
  final int meetingsHeld;
}

/// What a code shows someone outside the group.
class GroupPublicInfo {
  const GroupPublicInfo({required this.group, required this.assets, this.invitedBy});

  factory GroupPublicInfo.fromJson(final Map<String, dynamic> j) => GroupPublicInfo(
        group: '${j['group'] ?? ''}',
        invitedBy: _str(j['invited_by']),
        assets: <(int, String, double, int)>[
          for (final dynamic a in (j['assets'] as List? ?? const <dynamic>[]))
            if (a is Map) (_int(a['id']) ?? 0, '${a['name'] ?? ''}', _num(a['hire_rate']), _int(a['free_today']) ?? 0),
        ],
      );

  final String group;
  final String? invitedBy;

  /// (id, name, rate a day, free today)
  final List<(int, String, double, int)> assets;
}

/// The leaders' dashboard in one go. [money] is null for whoever may not see the group's money.
class GroupDashboardData {
  const GroupDashboardData({required this.month, required this.active, required this.applications, required this.suspended, required this.joinedInMonth, this.money, this.nextMeetingTitle, this.nextMeetingAt, this.loansDesk, this.projectsDesk, this.meetingsDesk});

  factory GroupDashboardData.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> m = j['members'] is Map ? Map<String, dynamic>.from(j['members'] as Map) : <String, dynamic>{};
    final Map<String, dynamic>? meeting = j['next_meeting'] is Map ? Map<String, dynamic>.from(j['next_meeting'] as Map) : null;
    Map<String, double>? desk(final String k) {
      final Object? d = j['desk'] is Map ? (j['desk'] as Map)[k] : null;
      return d is Map ? <String, double>{for (final MapEntry<dynamic, dynamic> e in d.entries) '${e.key}': _num(e.value)} : null;
    }

    return GroupDashboardData(
      loansDesk: desk('loans'),
      projectsDesk: desk('projects'),
      meetingsDesk: desk('meetings'),
      month: '${j['month'] ?? ''}',
      active: _int(m['active']) ?? 0,
      applications: _int(m['applications']) ?? 0,
      suspended: _int(m['suspended']) ?? 0,
      joinedInMonth: _int(m['joined_in_month']) ?? 0,
      money: j['money'] is Map ? GroupDashboardMoney.fromJson(Map<String, dynamic>.from(j['money'] as Map)) : null,
      nextMeetingTitle: _str(meeting?['title']),
      nextMeetingAt: _str(meeting?['starts_at']),
    );
  }

  final String month;
  final int active;
  final int applications;
  final int suspended;
  final int joinedInMonth;
  final GroupDashboardMoney? money;
  final String? nextMeetingTitle;
  final String? nextMeetingAt;

  /// What the person's office oversees, whether or not they see the money: the loan pipeline, the projects, the meetings (null when not theirs).
  final Map<String, double>? loansDesk;
  final Map<String, double>? projectsDesk;
  final Map<String, double>? meetingsDesk;
}

class GroupDashboardMoney {
  const GroupDashboardMoney({
    required this.cash,
    required this.monthIn,
    required this.monthOut,
    required this.savings,
    required this.shares,
    required this.expected,
    required this.collected,
    required this.overdueAmount,
    required this.overdueMembers,
    required this.loanPrincipal,
    required this.loanInterest,
    required this.loanArrears,
    required this.loansRunning,
    required this.loansOverdue,
    required this.pendingCount,
    required this.welfarePaid,
    required this.dividends,
    required this.hireIncome,
    required this.expenses,
    required this.trend,
    required this.mix,
  });

  factory GroupDashboardMoney.fromJson(final Map<String, dynamic> j) {
    Map<String, dynamic> sub(final String k) => j[k] is Map ? Map<String, dynamic>.from(j[k] as Map) : <String, dynamic>{};
    final Map<String, dynamic> c = sub('contributions');
    final Map<String, dynamic> l = sub('loans');
    final Map<String, dynamic> y = sub('year');
    return GroupDashboardMoney(
      cash: _num(j['cash_on_record']),
      monthIn: _num(j['month_in']),
      monthOut: _num(j['month_out']),
      savings: _num(j['savings']),
      shares: _num(j['shares']),
      expected: _num(c['expected']),
      collected: _num(c['collected']),
      overdueAmount: _num(c['overdue_amount']),
      overdueMembers: _int(c['overdue_members']) ?? 0,
      loanPrincipal: _num(l['principal']),
      loanInterest: _num(l['interest']),
      loanArrears: _num(l['arrears']),
      loansRunning: _int(l['running']) ?? 0,
      loansOverdue: _int(l['overdue']) ?? 0,
      pendingCount: _int(j['pending_count']) ?? 0,
      welfarePaid: _num(y['welfare_paid']),
      dividends: _num(y['dividends']),
      hireIncome: _num(y['hire_income']),
      expenses: _num(y['expenses']),
      trend: <(String, double, double)>[
        for (final dynamic t in (j['trend'] as List? ?? const <dynamic>[]))
          if (t is Map) ('${t['month']}', _num(t['in']), _num(t['out'])),
      ],
      mix: <(String, double, double)>[
        for (final dynamic t in (j['mix'] as List? ?? const <dynamic>[]))
          if (t is Map) ('${t['category']}', _num(t['in']), _num(t['out'])),
      ],
    );
  }

  final double cash;
  final double monthIn;
  final double monthOut;
  final double savings;
  final double shares;
  final double expected;
  final double collected;
  final double overdueAmount;
  final int overdueMembers;
  final double loanPrincipal;
  final double loanInterest;
  final double loanArrears;
  final int loansRunning;
  final int loansOverdue;
  final int pendingCount;
  final double welfarePaid;
  final double dividends;
  final double hireIncome;
  final double expenses;

  /// (YYYY-MM, in, out) for the 12 months up to the chosen one.
  final List<(String, double, double)> trend;

  /// (kind of money, in, out) in the chosen month.
  final List<(String, double, double)> mix;

  /// How much of what was expected this month came in (0..1); null when nothing was expected.
  double? get collectionRate => expected <= 0 ? null : (collected / expected).clamp(0, 1).toDouble();
}
