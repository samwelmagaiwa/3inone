/// What the Groups (Vikundi) screens read from the server, typed once here so the screens never dig in raw maps.
library;

double _num(final Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

int? _int(final Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String? _str(final Object? v) => v == null || '$v'.isEmpty ? null : '$v';

/// One person in the member register (an application, an active member, someone who left).
class GroupMember {
  const GroupMember({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.status,
    this.memberNumber,
    this.applicationRef,
    this.altPhone,
    this.email,
    this.nida,
    this.nidaMasked = false,
    this.dateOfBirth,
    this.gender,
    this.region,
    this.district,
    this.ward,
    this.street,
    this.occupation,
    this.office,
    this.statusReason,
    this.referrerId,
    this.referrerName,
    this.founding = false,
    this.joinedOn,
    this.hasSignIn = false,
  });

  factory GroupMember.fromJson(final Map<String, dynamic> j) => GroupMember(
        id: _int(j['id']) ?? 0,
        fullName: '${j['full_name'] ?? ''}',
        phone: '${j['phone'] ?? ''}',
        status: '${j['status'] ?? 'submitted'}',
        memberNumber: _str(j['member_number']),
        applicationRef: _str(j['application_ref']),
        altPhone: _str(j['alt_phone']),
        email: _str(j['email']),
        nida: _str(j['nida']),
        nidaMasked: j['nida_masked'] == true,
        dateOfBirth: _str(j['date_of_birth']),
        gender: _str(j['gender']),
        region: _str(j['region']),
        district: _str(j['district']),
        ward: _str(j['ward']),
        street: _str(j['street']),
        occupation: _str(j['occupation']),
        office: _str(j['office']),
        statusReason: _str(j['status_reason']),
        referrerId: _int(j['referrer_id']),
        referrerName: _str(j['referrer_name']),
        founding: j['founding'] == true,
        joinedOn: _str(j['joined_on']),
        hasSignIn: j['has_sign_in'] == true,
      );

  final int id;
  final String fullName;
  final String phone;
  final String status;
  final String? memberNumber;
  final String? applicationRef;
  final String? altPhone;
  final String? email;
  final String? nida;
  final bool nidaMasked;
  final String? dateOfBirth;
  final String? gender;
  final String? region;
  final String? district;
  final String? ward;
  final String? street;
  final String? occupation;
  final String? office;
  final String? statusReason;
  final int? referrerId;
  final String? referrerName;
  final bool founding;
  final String? joinedOn;
  final bool hasSignIn;

  bool get isActive => status == 'active';
  bool get isApplication => status == 'submitted';
}

class GroupDependant {
  const GroupDependant({required this.id, required this.name, required this.relationship, this.phone, this.dateOfBirth, this.notes});

  factory GroupDependant.fromJson(final Map<String, dynamic> j) => GroupDependant(
        id: _int(j['id']) ?? 0,
        name: '${j['name'] ?? ''}',
        relationship: '${j['relationship'] ?? 'other'}',
        phone: _str(j['phone']),
        dateOfBirth: _str(j['date_of_birth']),
        notes: _str(j['notes']),
      );

  final int id;
  final String name;
  final String relationship;
  final String? phone;
  final String? dateOfBirth;
  final String? notes;
}

/// A change of a member's status or office, as the history shows it.
class GroupMemberEvent {
  const GroupMemberEvent({required this.kind, this.from, this.to, this.reason, this.byName, this.at});

  factory GroupMemberEvent.fromJson(final Map<String, dynamic> j) => GroupMemberEvent(
        kind: '${j['kind'] ?? ''}',
        from: _str(j['from_value']),
        to: _str(j['to_value']),
        reason: _str(j['reason']),
        byName: _str(j['by_name']),
        at: _str(j['created_at']),
      );

  final String kind;
  final String? from;
  final String? to;
  final String? reason;
  final String? byName;
  final String? at;
}

/// One member's whole file.
class GroupMemberFile {
  const GroupMemberFile({
    required this.member,
    this.dependants = const <GroupDependant>[],
    this.events = const <GroupMemberEvent>[],
    this.referrals = const <GroupMember>[],
    this.balances,
    this.approvalBlockers = const <String>[],
  });

  factory GroupMemberFile.fromJson(final Map<String, dynamic> j) => GroupMemberFile(
        member: GroupMember.fromJson(Map<String, dynamic>.from(j['member'] as Map)),
        dependants: <GroupDependant>[for (final dynamic d in (j['dependants'] as List? ?? const <dynamic>[])) GroupDependant.fromJson(Map<String, dynamic>.from(d as Map))],
        events: <GroupMemberEvent>[for (final dynamic e in (j['events'] as List? ?? const <dynamic>[])) GroupMemberEvent.fromJson(Map<String, dynamic>.from(e as Map))],
        referrals: <GroupMember>[for (final dynamic r in (j['referrals'] as List? ?? const <dynamic>[])) GroupMember.fromJson(Map<String, dynamic>.from(r as Map))],
        balances: j['balances'] is Map ? <String, double>{for (final MapEntry<dynamic, dynamic> e in (j['balances'] as Map).entries) '${e.key}': _num(e.value)} : null,
        approvalBlockers: <String>[for (final dynamic b in (j['approval_blockers'] as List? ?? const <dynamic>[])) '$b'],
      );

  final GroupMember member;
  final List<GroupDependant> dependants;
  final List<GroupMemberEvent> events;
  final List<GroupMember> referrals;

  /// What the member has paid per category (verified only); null when the viewer may not see money.
  final Map<String, double>? balances;

  /// Why an application cannot be approved yet (joining_fee_unpaid, shares_unpaid).
  final List<String> approvalBlockers;
}

/// A page of the member register.
class GroupMemberPage {
  const GroupMemberPage({required this.members, required this.counts, required this.hasMore, required this.total});

  factory GroupMemberPage.fromJson(final Map<String, dynamic> res) {
    final Map<String, dynamic> data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
    final Map<String, dynamic> paging = res['meta'] is Map && (res['meta'] as Map)['pagination'] is Map
        ? Map<String, dynamic>.from((res['meta'] as Map)['pagination'] as Map)
        : <String, dynamic>{};
    return GroupMemberPage(
      members: <GroupMember>[for (final dynamic m in (data['members'] as List? ?? const <dynamic>[])) GroupMember.fromJson(Map<String, dynamic>.from(m as Map))],
      counts: <String, int>{if (data['counts'] is Map) for (final MapEntry<dynamic, dynamic> e in (data['counts'] as Map).entries) '${e.key}': _int(e.value) ?? 0},
      hasMore: paging['has_more'] == true,
      total: _int(paging['total']) ?? 0,
    );
  }

  final List<GroupMember> members;
  final Map<String, int> counts;
  final bool hasMore;
  final int total;
}

/// One payment (or reversal) in the group's money records.
class GroupTransaction {
  const GroupTransaction({
    required this.id,
    required this.reference,
    required this.category,
    required this.direction,
    required this.amount,
    required this.method,
    required this.paidOn,
    required this.status,
    this.receiptNumber,
    this.memberId,
    this.memberName,
    this.memberNumber,
    this.externalRef,
    this.note,
    this.rejectReason,
    this.submittedByName,
    this.verifiedByName,
    this.verifiedAt,
    this.reversesId,
    this.reversedById,
    this.obligationId,
    this.obligationLabel,
    this.payee,
  });

  factory GroupTransaction.fromJson(final Map<String, dynamic> j) => GroupTransaction(
        id: _int(j['id']) ?? 0,
        reference: '${j['reference'] ?? ''}',
        category: '${j['category'] ?? ''}',
        direction: '${j['direction'] ?? 'in'}',
        amount: _num(j['amount']),
        method: '${j['method'] ?? ''}',
        paidOn: '${j['paid_on'] ?? ''}',
        status: '${j['status'] ?? 'pending'}',
        receiptNumber: _str(j['receipt_number']),
        memberId: _int(j['member_id']),
        memberName: _str(j['member_name']),
        memberNumber: _str(j['member_number']),
        externalRef: _str(j['external_ref']),
        note: _str(j['note']),
        rejectReason: _str(j['reject_reason']),
        submittedByName: _str(j['submitted_by_name']),
        verifiedByName: _str(j['verified_by_name']),
        verifiedAt: _str(j['verified_at']),
        reversesId: _int(j['reverses_id']),
        reversedById: _int(j['reversed_by_id']),
        obligationId: _int(j['obligation_id']),
        obligationLabel: _str(j['obligation_label']),
        payee: _str(j['payee']),
      );

  final int id;
  final String reference;
  final String category;
  final String direction;
  final double amount;
  final String method;
  final String paidOn;
  final String status;
  final String? receiptNumber;
  final int? memberId;
  final String? memberName;
  final String? memberNumber;
  final String? externalRef;
  final String? note;
  final String? rejectReason;
  final String? submittedByName;
  final String? verifiedByName;
  final String? verifiedAt;
  final int? reversesId;
  final int? reversedById;

  /// The contribution it pays ("JAMII · 2026-11").
  final int? obligationId;
  final String? obligationLabel;

  /// Who a group expense was paid to.
  final String? payee;

  bool get isPending => status == 'pending';
  bool get isVerified => status == 'verified';
  bool get isReversal => reversesId != null;
  bool get isReversed => reversedById != null;

  /// The amount as it counts: a reversal takes money back out.
  double get signedAmount => direction == 'out' ? -amount : amount;
}

class GroupTransactionPage {
  const GroupTransactionPage({required this.transactions, required this.hasMore});

  factory GroupTransactionPage.fromJson(final Map<String, dynamic> res) {
    final Map<String, dynamic> data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
    final Map<String, dynamic> paging = res['meta'] is Map && (res['meta'] as Map)['pagination'] is Map
        ? Map<String, dynamic>.from((res['meta'] as Map)['pagination'] as Map)
        : <String, dynamic>{};
    return GroupTransactionPage(
      transactions: <GroupTransaction>[
        for (final dynamic t in (data['transactions'] as List? ?? const <dynamic>[])) GroupTransaction.fromJson(Map<String, dynamic>.from(t as Map)),
      ],
      hasMore: paging['has_more'] == true,
    );
  }

  final List<GroupTransaction> transactions;
  final bool hasMore;
}

/// Who the signed-in person is in their group, what they may do, and what waits for them.
class GroupMe {
  const GroupMe({
    required this.isOwner,
    required this.rights,
    this.member,
    this.balances,
    this.pending = 0,
    this.joiningFee = 0,
    this.shareAmount = 0,
    this.sharesRequiredFor = 'loans',
    this.paymentInstructions = '',
    this.waiting = const <String, int>{},
    this.groupName,
    this.owing = const <GroupObligation>[],
    this.promises = const <GroupPromise>[],
    this.keepsAssets = false,
    this.nextMeetingTitle,
    this.nextMeetingAt,
    this.nextMeetingVenue,
    this.notices = 0,
  });

  factory GroupMe.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> s = j['settings'] is Map ? Map<String, dynamic>.from(j['settings'] as Map) : <String, dynamic>{};
    return GroupMe(
      isOwner: j['is_owner'] == true,
      rights: <String>{for (final dynamic r in (j['rights'] as List? ?? const <dynamic>[])) '$r'},
      member: j['member'] is Map ? GroupMember.fromJson(Map<String, dynamic>.from(j['member'] as Map)) : null,
      balances: j['balances'] is Map ? <String, double>{for (final MapEntry<dynamic, dynamic> e in (j['balances'] as Map).entries) '${e.key}': _num(e.value)} : null,
      pending: _int(j['pending']) ?? 0,
      joiningFee: _num(s['joining_fee']),
      shareAmount: _num(s['share_amount']),
      sharesRequiredFor: '${s['shares_required_for'] ?? 'loans'}',
      paymentInstructions: '${s['payment_instructions'] ?? ''}',
      waiting: <String, int>{if (j['waiting'] is Map) for (final MapEntry<dynamic, dynamic> e in (j['waiting'] as Map).entries) '${e.key}': _int(e.value) ?? 0},
      groupName: _str(j['group'] is Map ? (j['group'] as Map)['name'] : null),
      owing: <GroupObligation>[for (final dynamic o in (j['owing'] as List? ?? const <dynamic>[])) GroupObligation.fromJson(Map<String, dynamic>.from(o as Map))],
      promises: <GroupPromise>[for (final dynamic p in (j['promises'] as List? ?? const <dynamic>[])) GroupPromise.fromJson(Map<String, dynamic>.from(p as Map))],
      keepsAssets: j['keeps_assets'] == true,
      nextMeetingTitle: _str(j['next_meeting'] is Map ? (j['next_meeting'] as Map)['title'] : null),
      nextMeetingAt: _str(j['next_meeting'] is Map ? (j['next_meeting'] as Map)['starts_at'] : null),
      nextMeetingVenue: _str(j['next_meeting'] is Map ? (j['next_meeting'] as Map)['venue'] : null),
      notices: _int(j['notices']) ?? 0,
    );
  }

  final bool isOwner;
  final Set<String> rights;
  final GroupMember? member;
  final Map<String, double>? balances;
  final int pending;
  final double joiningFee;
  final double shareAmount;
  final String sharesRequiredFor;
  final String paymentInstructions;
  final Map<String, int> waiting;
  final String? groupName;

  /// The contributions they still owe, oldest first.
  final List<GroupObligation> owing;
  final List<GroupPromise> promises;

  /// Keeps one of the group's assets (or manages the register): the hires section is theirs.
  final bool keepsAssets;

  /// The next meeting, if one is called.
  final String? nextMeetingTitle;
  final String? nextMeetingAt;
  final String? nextMeetingVenue;

  /// How many notices are up for this person.
  final int notices;

  bool can(final String right) => rights.contains(right);

  /// Sees the money of the whole group (the payments section).
  bool get seesPayments => can('view_finance') || can('verify_payments');

  /// Sees who owes what (the contributions section).
  bool get seesContributions => can('view_finance') || can('record_payments') || can('verify_payments') || can('manage_contributions');
}

/// A contribution the group asks of its members (monthly JAMII, a one-off, an event call).
class GroupContributionType {
  const GroupContributionType({
    required this.id,
    required this.name,
    required this.amount,
    required this.frequency,
    this.description,
    this.dueDay,
    this.mandatory = true,
    this.startsOn,
    this.endsOn,
    this.active = true,
  });

  factory GroupContributionType.fromJson(final Map<String, dynamic> j) => GroupContributionType(
        id: _int(j['id']) ?? 0,
        name: '${j['name'] ?? ''}',
        amount: _num(j['amount']),
        frequency: '${j['frequency'] ?? 'monthly'}',
        description: _str(j['description']),
        dueDay: _int(j['due_day']),
        mandatory: j['mandatory'] != false,
        startsOn: _str(j['starts_on']),
        endsOn: _str(j['ends_on']),
        active: j['active'] != false,
      );

  final int id;
  final String name;
  final double amount;
  final String frequency;
  final String? description;
  final int? dueDay;
  final bool mandatory;
  final String? startsOn;
  final String? endsOn;
  final bool active;
}

/// What one member owes for one contribution in one period, and where it stands.
class GroupObligation {
  const GroupObligation({
    required this.id,
    required this.memberId,
    required this.period,
    required this.amountDue,
    required this.paid,
    required this.remaining,
    required this.dueDate,
    required this.state,
    this.memberName,
    this.memberNumber,
    this.typeName,
    this.label,
    this.daysOverdue = 0,
    this.exemptReason,
  });

  factory GroupObligation.fromJson(final Map<String, dynamic> j) => GroupObligation(
        id: _int(j['id']) ?? 0,
        memberId: _int(j['member_id']) ?? 0,
        period: '${j['period'] ?? ''}',
        amountDue: _num(j['amount_due']),
        paid: _num(j['paid']),
        remaining: _num(j['remaining']),
        dueDate: '${j['due_date'] ?? ''}',
        state: '${j['state'] ?? 'due'}',
        memberName: _str(j['member_name']),
        memberNumber: _str(j['member_number']),
        typeName: _str(j['type_name']),
        label: _str(j['label']),
        daysOverdue: _int(j['days_overdue']) ?? 0,
        exemptReason: _str(j['exempt_reason']),
      );

  final int id;
  final int memberId;
  final String period;
  final double amountDue;
  final double paid;
  final double remaining;
  final String dueDate;

  /// paid | exempt | cancelled | overdue | due
  final String state;
  final String? memberName;
  final String? memberNumber;
  final String? typeName;
  final String? label;
  final int daysOverdue;
  final String? exemptReason;

  /// "JAMII · 2026-11" or "Harusi ya Juma".
  String get title => '${typeName ?? ''} · ${label ?? period}';

  bool get owing => (state == 'due' || state == 'overdue') && remaining > 0;
}

class GroupObligationPage {
  const GroupObligationPage({required this.obligations, required this.hasMore});

  factory GroupObligationPage.fromJson(final Map<String, dynamic> res) {
    final Map<String, dynamic> data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
    final Map<String, dynamic> paging = res['meta'] is Map && (res['meta'] as Map)['pagination'] is Map
        ? Map<String, dynamic>.from((res['meta'] as Map)['pagination'] as Map)
        : <String, dynamic>{};
    return GroupObligationPage(
      obligations: <GroupObligation>[
        for (final dynamic o in (data['obligations'] as List? ?? const <dynamic>[])) GroupObligation.fromJson(Map<String, dynamic>.from(o as Map)),
      ],
      hasMore: paging['has_more'] == true,
    );
  }

  final List<GroupObligation> obligations;
  final bool hasMore;
}

/// "I will pay 20,000 on the 30th." It never lowers what is owed.
class GroupPromise {
  const GroupPromise({required this.id, required this.memberId, required this.amount, required this.promisedOn, required this.state, this.memberName, this.obligationLabel, this.note});

  factory GroupPromise.fromJson(final Map<String, dynamic> j) => GroupPromise(
        id: _int(j['id']) ?? 0,
        memberId: _int(j['member_id']) ?? 0,
        amount: _num(j['amount']),
        promisedOn: '${j['promised_on'] ?? ''}',
        state: '${j['state'] ?? 'due'}',
        memberName: _str(j['member_name']),
        obligationLabel: _str(j['obligation_label']),
        note: _str(j['note']),
      );

  final int id;
  final int memberId;
  final double amount;
  final String promisedOn;

  /// due | overdue | kept | cancelled
  final String state;
  final String? memberName;
  final String? obligationLabel;
  final String? note;
}

/// A member's statement: every verified movement with the balance of its kind after it, what is owed, what waits.
class GroupStatementData {
  const GroupStatementData({
    required this.lines,
    required this.balanceAfter,
    required this.balances,
    required this.owing,
    required this.owingTotal,
    required this.waiting,
    required this.promises,
  });

  factory GroupStatementData.fromJson(final Map<String, dynamic> j) => GroupStatementData(
        lines: <GroupTransaction>[for (final dynamic t in (j['lines'] as List? ?? const <dynamic>[])) GroupTransaction.fromJson(Map<String, dynamic>.from(t as Map))],
        balanceAfter: <int, double>{
          for (final dynamic t in (j['lines'] as List? ?? const <dynamic>[]))
            if (t is Map && t['balance_after'] != null) _int(t['id']) ?? 0: _num(t['balance_after']),
        },
        balances: <String, double>{if (j['balances'] is Map) for (final MapEntry<dynamic, dynamic> e in (j['balances'] as Map).entries) '${e.key}': _num(e.value)},
        owing: <GroupObligation>[for (final dynamic o in (j['owing'] as List? ?? const <dynamic>[])) GroupObligation.fromJson(Map<String, dynamic>.from(o as Map))],
        owingTotal: _num(j['owing_total']),
        waiting: <GroupTransaction>[for (final dynamic t in (j['waiting'] as List? ?? const <dynamic>[])) GroupTransaction.fromJson(Map<String, dynamic>.from(t as Map))],
        promises: <GroupPromise>[for (final dynamic p in (j['promises'] as List? ?? const <dynamic>[])) GroupPromise.fromJson(Map<String, dynamic>.from(p as Map))],
      );

  final List<GroupTransaction> lines;

  /// The balance of its kind after each line (by transaction id).
  final Map<int, double> balanceAfter;
  final Map<String, double> balances;
  final List<GroupObligation> owing;
  final double owingTotal;
  final List<GroupTransaction> waiting;
  final List<GroupPromise> promises;
}
