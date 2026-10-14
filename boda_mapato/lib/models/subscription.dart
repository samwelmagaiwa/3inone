/// What a business paid for its plan, and where its subscription stands: when it started, when it ends.
library;

/// One payment, as the super admin recorded it. [periodStart]..[periodEnd] is the time it bought.
class SubscriptionPayment {
  const SubscriptionPayment({
    required this.amount,
    required this.currency,
    required this.plan,
    this.method,
    this.reference,
    this.periodStart,
    this.periodEnd,
    this.paidAt,
    this.note,
  });

  factory SubscriptionPayment.fromJson(final Map<String, dynamic> json) => SubscriptionPayment(
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        currency: (json['currency'] ?? 'TZS').toString(),
        plan: (json['plan'] ?? '').toString(),
        method: json['method']?.toString(),
        reference: json['reference']?.toString(),
        periodStart: _date(json['period_start']),
        periodEnd: _date(json['period_end']),
        paidAt: _date(json['paid_at']),
        note: json['note']?.toString(),
      );

  final double amount;
  final String currency;
  final String plan;
  final String? method;
  final String? reference;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? paidAt;
  final String? note;
}

/// The subscription of the signed-in business (or, for the super admin, of one business).
///
/// [status] is one of: never (no end date), active, expiring (a week or less left), grace (ended but still
/// working for a few days), expired (ended, and held back when [blocked]).
class SubscriptionInfo {
  const SubscriptionInfo({
    required this.status,
    required this.plan,
    this.businessName = '',
    this.isOwner = false,
    this.startedAt,
    this.validUntil,
    this.daysLeft,
    this.graceEndsAt,
    this.graceDays = 7,
    this.enforced = false,
    this.blocked = false,
    this.contactPhone = '',
    this.lastPayment,
    this.payments = const <SubscriptionPayment>[],
  });

  factory SubscriptionInfo.fromJson(final Map<String, dynamic> json) => SubscriptionInfo(
        status: (json['status'] ?? 'never').toString(),
        plan: (json['plan'] ?? '').toString(),
        businessName: (json['business_name'] ?? '').toString(),
        isOwner: json['is_owner'] == true,
        startedAt: _date(json['started_at']),
        validUntil: _date(json['valid_until']),
        daysLeft: (json['days_left'] as num?)?.toInt(),
        graceEndsAt: _date(json['grace_ends_at']),
        graceDays: (json['grace_days'] as num?)?.toInt() ?? 7,
        enforced: json['enforced'] == true,
        blocked: json['blocked'] == true,
        contactPhone: (json['contact_phone'] ?? '').toString(),
        lastPayment: json['last_payment'] is Map ? SubscriptionPayment.fromJson(Map<String, dynamic>.from(json['last_payment'] as Map)) : null,
        payments: json['payments'] is List
            ? (json['payments'] as List).whereType<Map>().map((final Map m) => SubscriptionPayment.fromJson(Map<String, dynamic>.from(m))).toList()
            : const <SubscriptionPayment>[],
      );

  final String status;
  final String plan;
  final String businessName;
  final bool isOwner;

  /// When the current period began (the newest payment's start, else the day the business was created).
  final DateTime? startedAt;

  /// The business works through the end of this day. Null: it never expires.
  final DateTime? validUntil;
  final int? daysLeft;
  final DateTime? graceEndsAt;
  final int graceDays;

  /// Is the server really holding expired businesses back? When false, an ended plan only reminds.
  final bool enforced;
  final bool blocked;

  /// Where to pay (set on the server); empty says nothing.
  final String contactPhone;
  final SubscriptionPayment? lastPayment;

  /// The payments with their amounts: the owner's list. Staff get none.
  final List<SubscriptionPayment> payments;

  bool get neverExpires => validUntil == null;
}

DateTime? _date(final Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
