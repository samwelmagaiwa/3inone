/// Expense requests (matumizi) of the Groups (Vikundi) service, typed once here.
library;

double _num(final Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

int? _int(final Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String? _str(final Object? v) => v == null || '$v'.isEmpty ? null : '$v';

/// What the group may be asked to spend money on.
const List<String> groupExpenseCategories = <String>['project', 'office', 'meeting', 'transport', 'event', 'other'];

/// One request for money to be spent: asked, decided, paid out, verified.
class GroupExpense {
  const GroupExpense({
    required this.id,
    required this.reference,
    required this.purpose,
    required this.category,
    required this.payee,
    required this.amount,
    required this.state,
    required this.mine,
    required this.createdAt,
    this.amountApproved,
    this.projectId,
    this.projectTitle,
    this.requestedByName,
    this.decisionNote,
  });

  factory GroupExpense.fromJson(final Map<String, dynamic> j) => GroupExpense(
        id: _int(j['id']) ?? 0,
        reference: '${j['reference'] ?? ''}',
        purpose: '${j['purpose'] ?? ''}',
        category: '${j['category'] ?? 'other'}',
        payee: '${j['payee'] ?? ''}',
        amount: _num(j['amount']),
        amountApproved: j['amount_approved'] == null ? null : _num(j['amount_approved']),
        projectId: _int(j['project_id']),
        projectTitle: _str(j['project_title']),
        requestedByName: _str(j['requested_by_name']),
        state: '${j['state'] ?? 'requested'}',
        decisionNote: _str(j['decision_note']),
        mine: j['mine'] == true,
        createdAt: '${j['created_at'] ?? ''}',
      );

  final int id;
  final String reference;
  final String purpose;
  final String category;
  final String payee;
  final double amount;
  final double? amountApproved;
  final int? projectId;
  final String? projectTitle;
  final String? requestedByName;

  /// requested | approved | paying | paid | rejected | cancelled
  final String state;
  final String? decisionNote;

  /// Asked by the signed-in person: they may take it back, but never decide or pay it.
  final bool mine;
  final String createdAt;
}
