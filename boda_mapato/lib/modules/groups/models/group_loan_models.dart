/// Loans and welfare of the Groups (Vikundi) service, typed once here.
library;

double _num(final Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

int? _int(final Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String? _str(final Object? v) => v == null || '$v'.isEmpty ? null : '$v';

Map<String, dynamic>? _map(final Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

/// Can a member borrow, and up to how much: savings x multiplier, less what other loans still owe.
class GroupLoanEligibility {
  const GroupLoanEligibility({
    required this.savings,
    required this.multiplier,
    required this.otherLoans,
    required this.ceiling,
    required this.sharesPaid,
    required this.sharesNeeded,
    required this.eligible,
    required this.reasons,
    this.rate,
    this.method,
    this.maxMonths = 12,
    this.guarantors = 1,
    this.repayment = 'monthly',
    this.repaymentDays,
  });

  factory GroupLoanEligibility.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> t = _map(j['terms']) ?? <String, dynamic>{};
    return GroupLoanEligibility(
      savings: _num(j['savings']),
      multiplier: _num(j['multiplier']),
      otherLoans: _num(j['other_loans']),
      ceiling: _num(j['ceiling']),
      sharesPaid: _num(j['shares_paid']),
      sharesNeeded: _num(j['shares_needed']),
      eligible: j['eligible'] == true,
      reasons: <String>[for (final dynamic r in (j['reasons'] as List? ?? const <dynamic>[])) '$r'],
      rate: t['rate'] == null ? null : _num(t['rate']),
      method: _str(t['method']),
      maxMonths: _int(t['max_months']) ?? 12,
      guarantors: _int(t['guarantors']) ?? 1,
      repayment: _str(t['repayment']) ?? 'monthly',
      repaymentDays: _int(t['repayment_days']),
    );
  }

  final double savings;
  final double multiplier;
  final double otherLoans;
  final double ceiling;
  final double sharesPaid;
  final double sharesNeeded;
  final bool eligible;
  final List<String> reasons;
  final double? rate;
  final String? method;
  final int maxMonths;
  final int guarantors;

  /// How often a loan is repaid: daily | weekly | every_2_weeks | monthly | every_2_months | quarterly | every_6_months | custom (every [repaymentDays] days).
  final String repayment;
  final int? repaymentDays;
}

/// One instalment of a loan (or of the preview before it is paid out).
class GroupInstalment {
  const GroupInstalment({required this.number, required this.dueDate, required this.principalDue, required this.interestDue, this.paid = 0, this.left, this.state});

  factory GroupInstalment.fromJson(final Map<String, dynamic> j) => GroupInstalment(
        number: _int(j['number']) ?? 0,
        dueDate: '${j['due_date'] ?? ''}',
        principalDue: _num(j['principal_due']),
        interestDue: _num(j['interest_due']),
        paid: _num(j['paid']),
        left: j['left'] == null ? null : _num(j['left']),
        state: _str(j['state']),
      );

  final int number;
  final String dueDate;
  final double principalDue;
  final double interestDue;
  final double paid;
  final double? left;

  /// paid | overdue | due (null in a preview)
  final String? state;

  double get total => principalDue + interestDue;
}

class GroupGuarantor {
  const GroupGuarantor({required this.id, required this.memberId, required this.name, required this.status, this.note});

  factory GroupGuarantor.fromJson(final Map<String, dynamic> j) =>
      GroupGuarantor(id: _int(j['id']) ?? 0, memberId: _int(j['member_id']) ?? 0, name: '${j['name'] ?? ''}', status: '${j['status'] ?? 'pending'}', note: _str(j['note']));

  final int id;
  final int memberId;
  final String name;

  /// pending | accepted | declined
  final String status;
  final String? note;
}

/// A loan from application to repaid.
class GroupLoan {
  const GroupLoan({
    required this.id,
    required this.reference,
    required this.memberId,
    required this.amountRequested,
    required this.purpose,
    required this.termMonths,
    required this.interestRate,
    required this.interestMethod,
    this.repaymentEvery = 'monthly',
    this.repaymentDays,
    required this.status,
    required this.state,
    this.memberName,
    this.amountApproved,
    this.ceiling,
    this.recommendation,
    this.rejectReason,
    this.disbursedOn,
    this.outstanding,
    this.arrears,
    this.nextDue,
    this.nextAmount,
    this.guarantors = const <GroupGuarantor>[],
    this.instalments = const <GroupInstalment>[],
    this.principalPaid = 0,
    this.interestPaid = 0,
    this.outstandingPrincipal = 0,
    this.outstandingInterest = 0,
    this.previewInterest,
    this.previewTotal,
  });

  factory GroupLoan.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic>? pos = _map(j['position']);
    final Map<String, dynamic>? preview = _map(j['preview']);
    final Map<String, dynamic>? next = _map(j['next']);
    final List<dynamic> rows = (pos?['instalments'] as List?) ?? (preview?['instalments'] as List?) ?? const <dynamic>[];
    return GroupLoan(
      id: _int(j['id']) ?? 0,
      reference: '${j['reference'] ?? ''}',
      memberId: _int(j['member_id']) ?? 0,
      memberName: _str(j['member_name']),
      amountRequested: _num(j['amount_requested']),
      amountApproved: j['amount_approved'] == null ? null : _num(j['amount_approved']),
      purpose: '${j['purpose'] ?? ''}',
      termMonths: _int(j['term_months']) ?? 1,
      interestRate: _num(j['interest_rate']),
      interestMethod: '${j['interest_method'] ?? 'flat'}',
      repaymentEvery: _str(j['repayment_every']) ?? 'monthly',
      repaymentDays: _int(j['repayment_days']),
      ceiling: j['ceiling'] == null ? null : _num(j['ceiling']),
      status: '${j['status'] ?? ''}',
      state: '${j['state'] ?? ''}',
      recommendation: _str(j['recommendation']),
      rejectReason: _str(j['reject_reason']),
      disbursedOn: _str(j['disbursed_on']),
      outstanding: j['outstanding'] == null ? null : _num(j['outstanding']),
      arrears: j['arrears'] == null ? null : _num(j['arrears']),
      nextDue: _str(next?['due_date']),
      nextAmount: next == null ? null : _num(next['amount']),
      guarantors: <GroupGuarantor>[for (final dynamic g in (j['guarantors'] as List? ?? const <dynamic>[])) GroupGuarantor.fromJson(Map<String, dynamic>.from(g as Map))],
      instalments: <GroupInstalment>[for (final dynamic r in rows) GroupInstalment.fromJson(Map<String, dynamic>.from(r as Map))],
      principalPaid: _num(pos?['principal_paid']),
      interestPaid: _num(pos?['interest_paid']),
      outstandingPrincipal: _num(pos?['outstanding_principal']),
      outstandingInterest: _num(pos?['outstanding_interest']),
      previewInterest: preview == null ? null : _num(preview['total_interest']),
      previewTotal: preview == null ? null : _num(preview['total']),
    );
  }

  final int id;
  final String reference;
  final int memberId;
  final String? memberName;
  final double amountRequested;
  final double? amountApproved;
  final String purpose;
  final int termMonths;
  final double interestRate;
  final String interestMethod;

  /// The rhythm this loan was applied under (daily, weekly ... or `custom`: every [repaymentDays] days).
  final String repaymentEvery;
  final int? repaymentDays;
  final double? ceiling;

  /// awaiting_guarantors | under_review | recommended | approved | active | rejected | cancelled
  final String status;

  /// The status, or for a running loan: active | overdue | repaid
  final String state;
  final String? recommendation;
  final String? rejectReason;
  final String? disbursedOn;
  final double? outstanding;
  final double? arrears;
  final String? nextDue;
  final double? nextAmount;
  final List<GroupGuarantor> guarantors;
  final List<GroupInstalment> instalments;
  final double principalPaid;
  final double interestPaid;
  final double outstandingPrincipal;
  final double outstandingInterest;
  final double? previewInterest;
  final double? previewTotal;

  bool get isOpen => const <String>['awaiting_guarantors', 'under_review', 'recommended', 'approved'].contains(status);
  bool get isRunning => status == 'active' && (outstanding ?? 0) > 0;
}

/// A request to guarantee someone's loan.
class GroupGuarantee {
  const GroupGuarantee({
    required this.id,
    required this.status,
    required this.loanId,
    required this.reference,
    required this.amount,
    required this.purpose,
    required this.borrower,
    required this.loanStatus,
    required this.termMonths,
  });

  factory GroupGuarantee.fromJson(final Map<String, dynamic> j) => GroupGuarantee(
        id: _int(j['id']) ?? 0,
        status: '${j['status'] ?? 'pending'}',
        loanId: _int(j['loan_id']) ?? 0,
        reference: '${j['reference'] ?? ''}',
        amount: _num(j['amount_requested']),
        purpose: '${j['purpose'] ?? ''}',
        borrower: '${j['borrower'] ?? ''}',
        loanStatus: '${j['loan_status'] ?? ''}',
        termMonths: _int(j['term_months']) ?? 0,
      );

  final int id;
  final String status;
  final int loanId;
  final String reference;
  final double amount;
  final String purpose;
  final String borrower;
  final String loanStatus;
  final int termMonths;

  bool get waitsForMe => status == 'pending' && loanStatus == 'awaiting_guarantors';
}

/// The leaders' view of all loans: a page, the portfolio and what waits at each step.
class GroupLoanPage {
  const GroupLoanPage({required this.loans, required this.portfolio, required this.waiting, required this.hasMore});

  factory GroupLoanPage.fromJson(final Map<String, dynamic> res) {
    final Map<String, dynamic> data = _map(res['data']) ?? <String, dynamic>{};
    final Map<String, dynamic> paging = _map(_map(res['meta'])?['pagination']) ?? <String, dynamic>{};
    return GroupLoanPage(
      loans: <GroupLoan>[for (final dynamic l in (data['loans'] as List? ?? const <dynamic>[])) GroupLoan.fromJson(Map<String, dynamic>.from(l as Map))],
      portfolio: <String, double>{for (final MapEntry<String, dynamic> e in (_map(data['portfolio']) ?? <String, dynamic>{}).entries) e.key: _num(e.value)},
      waiting: <String, int>{for (final MapEntry<String, dynamic> e in (_map(data['waiting']) ?? <String, dynamic>{}).entries) e.key: _int(e.value) ?? 0},
      hasMore: paging['has_more'] == true,
    );
  }

  final List<GroupLoan> loans;
  final Map<String, double> portfolio;
  final Map<String, int> waiting;
  final bool hasMore;
}

class GroupBenefitType {
  const GroupBenefitType({required this.id, required this.name, this.description, this.amount, this.active = true});

  factory GroupBenefitType.fromJson(final Map<String, dynamic> j) => GroupBenefitType(
        id: _int(j['id']) ?? 0,
        name: '${j['name'] ?? ''}',
        description: _str(j['description']),
        amount: j['amount'] == null ? null : _num(j['amount']),
        active: j['active'] != false,
      );

  final int id;
  final String name;
  final String? description;
  final double? amount;
  final bool active;
}

/// A welfare request: help asked, decided, paid.
class GroupBenefitRequest {
  const GroupBenefitRequest({
    required this.id,
    required this.reference,
    required this.memberId,
    required this.typeId,
    required this.beneficiary,
    required this.relationship,
    required this.eventDate,
    required this.state,
    this.memberName,
    this.typeName,
    this.description,
    this.amountRequested,
    this.amountApproved,
    this.decisionNote,
  });

  factory GroupBenefitRequest.fromJson(final Map<String, dynamic> j) => GroupBenefitRequest(
        id: _int(j['id']) ?? 0,
        reference: '${j['reference'] ?? ''}',
        memberId: _int(j['member_id']) ?? 0,
        memberName: _str(j['member_name']),
        typeId: _int(j['type_id']) ?? 0,
        typeName: _str(j['type_name']),
        beneficiary: '${j['beneficiary'] ?? ''}',
        relationship: '${j['relationship'] ?? 'self'}',
        eventDate: '${j['event_date'] ?? ''}',
        description: _str(j['description']),
        amountRequested: j['amount_requested'] == null ? null : _num(j['amount_requested']),
        amountApproved: j['amount_approved'] == null ? null : _num(j['amount_approved']),
        state: '${j['state'] ?? 'submitted'}',
        decisionNote: _str(j['decision_note']),
      );

  final int id;
  final String reference;
  final int memberId;
  final String? memberName;
  final int typeId;
  final String? typeName;
  final String beneficiary;
  final String relationship;
  final String eventDate;
  final String? description;
  final double? amountRequested;
  final double? amountApproved;

  /// submitted | approved | paying | paid | rejected | cancelled
  final String state;
  final String? decisionNote;
}
