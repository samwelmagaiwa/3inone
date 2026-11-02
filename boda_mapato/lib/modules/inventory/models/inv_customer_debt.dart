import 'package:flutter/foundation.dart';

double _num(final Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

/// One old debt (from before the app) of a customer: what it was, what was paid on it, what is left.
@immutable
class OldDebtEntry {
  const OldDebtEntry({required this.id, required this.amount, required this.paid, required this.left, this.startedOn = '', this.note});

  factory OldDebtEntry.fromJson(final Map<String, dynamic> j) => OldDebtEntry(
        id: _num(j['id']).toInt(),
        amount: _num(j['amount']),
        paid: _num(j['paid']),
        left: _num(j['left']),
        startedOn: (j['started_on'] ?? '').toString(),
        note: j['note']?.toString(),
      );

  final int id;
  final double amount;
  final double paid;
  final double left;
  final String startedOn;
  final String? note;
}

/// A sale on credit that still has something to pay.
@immutable
class NewDebtSale {
  const NewDebtSale({required this.id, required this.number, required this.total, required this.paid, required this.left, this.paymentStatus = 'debt', this.dueDate, this.createdAt});

  factory NewDebtSale.fromJson(final Map<String, dynamic> j) => NewDebtSale(
        id: _num(j['id']).toInt(),
        number: (j['number'] ?? '').toString(),
        total: _num(j['total']),
        paid: _num(j['paid']),
        left: _num(j['left']),
        paymentStatus: (j['payment_status'] ?? 'debt').toString(),
        dueDate: j['due_date']?.toString(),
        createdAt: j['created_at']?.toString(),
      );

  final int id;
  final String number;
  final double total;
  final double paid;
  final double left;
  final String paymentStatus;
  final String? dueDate;
  final String? createdAt;
}

/// What a customer owes, in three parts: the OLD debt (before the app), the NEW debt (credit sales since), and the TOTAL of both, each
/// with what was owed, what was paid and what is left. The server works it out; every screen shows these same figures.
@immutable
class CustomerDebtSummary {
  const CustomerDebtSummary({
    this.oldOriginal = 0,
    this.oldPaid = 0,
    this.oldLeft = 0,
    this.oldEntries = const <OldDebtEntry>[],
    this.newBilled = 0,
    this.newPaid = 0,
    this.newLeft = 0,
    this.newSales = const <NewDebtSale>[],
    this.totalOwed = 0,
    this.totalPaid = 0,
    this.totalLeft = 0,
  });

  factory CustomerDebtSummary.fromJson(final Map<String, dynamic> j) {
    Map<String, dynamic> part(final String k) => j[k] is Map ? Map<String, dynamic>.from(j[k] as Map) : <String, dynamic>{};
    final Map<String, dynamic> old = part('old');
    final Map<String, dynamic> neu = part('new');
    final Map<String, dynamic> tot = part('total');
    return CustomerDebtSummary(
      oldOriginal: _num(old['original']),
      oldPaid: _num(old['paid']),
      oldLeft: _num(old['left']),
      oldEntries: <OldDebtEntry>[
        for (final Object? e in (old['entries'] is List ? old['entries'] as List : const <Object?>[])) if (e is Map) OldDebtEntry.fromJson(Map<String, dynamic>.from(e)),
      ],
      newBilled: _num(neu['billed']),
      newPaid: _num(neu['paid']),
      newLeft: _num(neu['left']),
      newSales: <NewDebtSale>[
        for (final Object? e in (neu['sales'] is List ? neu['sales'] as List : const <Object?>[])) if (e is Map) NewDebtSale.fromJson(Map<String, dynamic>.from(e)),
      ],
      totalOwed: _num(tot['owed']),
      totalPaid: _num(tot['paid']),
      totalLeft: _num(tot['left']),
    );
  }

  final double oldOriginal;
  final double oldPaid;
  final double oldLeft;
  final List<OldDebtEntry> oldEntries;
  final double newBilled;
  final double newPaid;
  final double newLeft;
  final List<NewDebtSale> newSales;
  final double totalOwed;
  final double totalPaid;
  final double totalLeft;

  /// Did this customer owe anything from before the app?
  bool get hasOld => oldOriginal > 0;

  /// Is there any debt (old or new) on record, paid or not?
  bool get hasAny => totalOwed > 0;

  /// The same account after a sale of [credit] more is put on credit: the new debt and the total grow by it, nothing else changes.
  CustomerDebtSummary withSale(final double credit) => credit <= 0
      ? this
      : CustomerDebtSummary(
          oldOriginal: oldOriginal,
          oldPaid: oldPaid,
          oldLeft: oldLeft,
          oldEntries: oldEntries,
          newBilled: newBilled + credit,
          newPaid: newPaid,
          newLeft: newLeft + credit,
          newSales: newSales,
          totalOwed: totalOwed + credit,
          totalPaid: totalPaid,
          totalLeft: totalLeft + credit,
        );
}

/// One payment on a customer's debt: made on an old debt (from before the app) or on a credit sale.
@immutable
class AccountPayment {
  const AccountPayment({required this.id, required this.amount, required this.paidOn, this.method, this.reference, this.isOld = false, this.label = ''});

  factory AccountPayment.fromJson(final Map<String, dynamic> j) => AccountPayment(
        id: _num(j['id']).toInt(),
        amount: _num(j['amount']),
        method: j['method']?.toString(),
        reference: j['reference']?.toString(),
        paidOn: (j['paid_on'] ?? '').toString(),
        isOld: j['kind'] == 'old',
        label: (j['label'] ?? '').toString(),
      );

  final int id;
  final double amount;
  final String paidOn;
  final String? method;
  final String? reference;

  /// Made on an old debt (true) or on a credit sale (false).
  final bool isOld;

  /// What it was paid on: the old debt's note, or the sale's number (only in the one list of all payments).
  final String label;
}

/// An old debt with the payments made on it.
@immutable
class OldDebtRecord {
  const OldDebtRecord({required this.id, required this.amount, required this.paid, required this.left, this.startedOn = '', this.dueOn, this.note, this.payments = const <AccountPayment>[]});

  factory OldDebtRecord.fromJson(final Map<String, dynamic> j) => OldDebtRecord(
        id: _num(j['id']).toInt(),
        amount: _num(j['amount']),
        paid: _num(j['paid']),
        left: _num(j['left']),
        startedOn: (j['started_on'] ?? '').toString(),
        dueOn: j['due_on']?.toString(),
        note: j['note']?.toString(),
        payments: _payments(j['payments']),
      );

  final int id;
  final double amount;
  final double paid;
  final double left;
  final String startedOn;
  final String? dueOn;
  final String? note;
  final List<AccountPayment> payments;
}

/// A credit sale with the payments made on it.
@immutable
class CreditSaleRecord {
  const CreditSaleRecord({required this.id, required this.number, required this.total, required this.paid, required this.left, this.paymentStatus = 'debt', this.dueDate, this.createdAt = '', this.payments = const <AccountPayment>[]});

  factory CreditSaleRecord.fromJson(final Map<String, dynamic> j) => CreditSaleRecord(
        id: _num(j['id']).toInt(),
        number: (j['number'] ?? '').toString(),
        total: _num(j['total']),
        paid: _num(j['paid']),
        left: _num(j['left']),
        paymentStatus: (j['payment_status'] ?? 'debt').toString(),
        dueDate: j['due_date']?.toString(),
        createdAt: (j['created_at'] ?? '').toString(),
        payments: _payments(j['payments']),
      );

  final int id;
  final String number;
  final double total;
  final double paid;
  final double left;
  final String paymentStatus;
  final String? dueDate;
  final String createdAt;
  final List<AccountPayment> payments;

  bool get isPaidOff => left <= 0;
}

List<AccountPayment> _payments(final Object? raw) => <AccountPayment>[
      for (final Object? e in (raw is List ? raw : const <Object?>[])) if (e is Map) AccountPayment.fromJson(Map<String, dynamic>.from(e)),
    ];

/// One customer's whole account: the three-part summary, every old debt and every credit sale with its payments, and all the payments
/// together, newest first.
@immutable
class CustomerAccount {
  const CustomerAccount({
    required this.name,
    required this.debt,
    this.phone = '',
    this.oldDebts = const <OldDebtRecord>[],
    this.creditSales = const <CreditSaleRecord>[],
    this.payments = const <AccountPayment>[],
    this.paidOld = 0,
    this.paidNew = 0,
    this.paidAll = 0,
  });

  factory CustomerAccount.fromJson(final Map<String, dynamic> j) {
    final Map<String, dynamic> customer = j['customer'] is Map ? Map<String, dynamic>.from(j['customer'] as Map) : <String, dynamic>{};
    final Map<String, dynamic> paid = j['paid_by_payments'] is Map ? Map<String, dynamic>.from(j['paid_by_payments'] as Map) : <String, dynamic>{};
    return CustomerAccount(
      name: (customer['name'] ?? '').toString(),
      phone: (customer['phone'] ?? '').toString(),
      debt: CustomerDebtSummary.fromJson(j['debt'] is Map ? Map<String, dynamic>.from(j['debt'] as Map) : <String, dynamic>{}),
      oldDebts: <OldDebtRecord>[
        for (final Object? e in (j['old_debts'] is List ? j['old_debts'] as List : const <Object?>[])) if (e is Map) OldDebtRecord.fromJson(Map<String, dynamic>.from(e)),
      ],
      creditSales: <CreditSaleRecord>[
        for (final Object? e in (j['credit_sales'] is List ? j['credit_sales'] as List : const <Object?>[])) if (e is Map) CreditSaleRecord.fromJson(Map<String, dynamic>.from(e)),
      ],
      payments: _payments(j['payments']),
      paidOld: _num(paid['old']),
      paidNew: _num(paid['new']),
      paidAll: _num(paid['all']),
    );
  }

  final String name;
  final String phone;
  final CustomerDebtSummary debt;
  final List<OldDebtRecord> oldDebts;
  final List<CreditSaleRecord> creditSales;
  final List<AccountPayment> payments;
  final double paidOld;
  final double paidNew;
  final double paidAll;
}
