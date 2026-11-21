/// The group's assets and hiring them out, typed once here.
library;

double _num(final Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

int? _int(final Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String? _str(final Object? v) => v == null || '$v'.isEmpty ? null : '$v';

/// Something the group owns. [cost] and [location] come only to whoever manages assets or keeps this one.
class GroupAsset {
  const GroupAsset({
    required this.id,
    required this.code,
    required this.name,
    required this.quantity,
    required this.freeToday,
    required this.condition,
    required this.status,
    this.category,
    this.description,
    this.hireRate,
    this.lateRate,
    this.visible = true,
    this.custodianId,
    this.custodianName,
    this.acquiredOn,
    this.cost,
    this.location,
  });

  factory GroupAsset.fromJson(final Map<String, dynamic> j) => GroupAsset(
        id: _int(j['id']) ?? 0,
        code: '${j['code'] ?? ''}',
        name: '${j['name'] ?? ''}',
        quantity: _int(j['quantity']) ?? 0,
        freeToday: _int(j['free_today']) ?? 0,
        condition: '${j['condition'] ?? 'good'}',
        status: '${j['status'] ?? 'active'}',
        category: _str(j['category']),
        description: _str(j['description']),
        hireRate: j['hire_rate'] == null ? null : _num(j['hire_rate']),
        lateRate: j['late_rate'] == null ? null : _num(j['late_rate']),
        visible: j['visible'] != false,
        custodianId: _int(j['custodian_id']),
        custodianName: _str(j['custodian_name']),
        acquiredOn: _str(j['acquired_on']),
        cost: j['cost'] == null ? null : _num(j['cost']),
        location: _str(j['location']),
      );

  final int id;
  final String code;
  final String name;
  final int quantity;
  final int freeToday;

  /// good | fair | poor
  final String condition;

  /// active | retired
  final String status;
  final String? category;
  final String? description;
  final double? hireRate;
  final double? lateRate;
  final bool visible;
  final int? custodianId;
  final String? custodianName;
  final String? acquiredOn;
  final double? cost;
  final String? location;

  bool get forHire => hireRate != null && status == 'active';
}

/// A change to an asset (handed to a new keeper, maintenance, damage, loss, repair, a recount, retired).
class GroupAssetEvent {
  const GroupAssetEvent({required this.kind, this.quantity, this.cost, this.note, this.byName, this.at});

  factory GroupAssetEvent.fromJson(final Map<String, dynamic> j) => GroupAssetEvent(
        kind: '${j['kind'] ?? ''}',
        quantity: _int(j['quantity']),
        cost: j['cost'] == null ? null : _num(j['cost']),
        note: _str(j['note']),
        byName: _str(j['by_name']),
        at: _str(j['created_at']),
      );

  final String kind;
  final int? quantity;
  final double? cost;
  final String? note;
  final String? byName;
  final String? at;
}

/// One hire, from request to closed.
class GroupHire {
  const GroupHire({
    required this.id,
    required this.reference,
    required this.assetId,
    required this.quantity,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.rate,
    required this.amount,
    required this.total,
    required this.paid,
    required this.balance,
    required this.status,
    required this.state,
    this.assetName,
    this.memberId,
    this.who,
    this.phone,
    this.purpose,
    this.lateCharge = 0,
    this.damageCharge = 0,
    this.damageNote,
    this.decisionNote,
    this.issuedQuantity,
    this.issuedCondition,
    this.returnedQuantity,
    this.damagedQuantity,
    this.missingQuantity,
    this.returnNote,
    this.returnedOn,
  });

  factory GroupHire.fromJson(final Map<String, dynamic> j) => GroupHire(
        id: _int(j['id']) ?? 0,
        reference: '${j['reference'] ?? ''}',
        assetId: _int(j['asset_id']) ?? 0,
        assetName: _str(j['asset_name']),
        memberId: _int(j['member_id']),
        who: _str(j['who']),
        phone: _str(j['phone']),
        purpose: _str(j['purpose']),
        quantity: _int(j['quantity']) ?? 0,
        startDate: '${j['start_date'] ?? ''}',
        endDate: '${j['end_date'] ?? ''}',
        days: _int(j['days']) ?? 1,
        rate: _num(j['rate']),
        amount: _num(j['amount']),
        lateCharge: _num(j['late_charge']),
        damageCharge: _num(j['damage_charge']),
        damageNote: _str(j['damage_note']),
        total: _num(j['total']),
        paid: _num(j['paid']),
        balance: _num(j['balance']),
        status: '${j['status'] ?? 'requested'}',
        state: '${j['state'] ?? 'requested'}',
        decisionNote: _str(j['decision_note']),
        issuedQuantity: _int(j['issued_quantity']),
        issuedCondition: _str(j['issued_condition']),
        returnedQuantity: _int(j['returned_quantity']),
        damagedQuantity: _int(j['damaged_quantity']),
        missingQuantity: _int(j['missing_quantity']),
        returnNote: _str(j['return_note']),
        returnedOn: _str(j['returned_on']),
      );

  final int id;
  final String reference;
  final int assetId;
  final String? assetName;
  final int? memberId;

  /// The member's name, or the person outside the group.
  final String? who;
  final String? phone;
  final String? purpose;
  final int quantity;
  final String startDate;
  final String endDate;
  final int days;
  final double rate;
  final double amount;
  final double lateCharge;
  final double damageCharge;
  final String? damageNote;
  final double total;
  final double paid;
  final double balance;

  /// requested | approved | declined | issued | returned | closed | cancelled
  final String status;

  /// requested | waiting_payment | confirmed | out | overdue | damage_pending | balance_due | settled | closed | declined | cancelled
  final String state;
  final String? decisionNote;
  final int? issuedQuantity;
  final String? issuedCondition;
  final int? returnedQuantity;
  final int? damagedQuantity;
  final int? missingQuantity;
  final String? returnNote;
  final String? returnedOn;
}
