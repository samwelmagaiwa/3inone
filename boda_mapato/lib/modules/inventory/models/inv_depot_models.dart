import 'package:flutter/foundation.dart';

/// Models for Areas 4–13. All are immutable value types parsed defensively:
/// the API is the source of truth, and a missing field must never crash a screen.

// MySQL DECIMAL columns come back through PDO as strings (e.g. "15000.00"),
// so `as num?` throws instead of falling through to `??` — the cast itself
// fails before the fallback ever runs. Check the runtime type instead.
double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

String _toStr(dynamic v) => (v ?? '').toString();

// --------------------------------------------------------------- Area 4

@immutable
class InvSupplier {
  const InvSupplier({
    required this.id,
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.contactPerson = '',
    this.paymentTermsDays = 0,
    this.status = 'active',
    this.balance = 0,
  });

  factory InvSupplier.fromJson(Map<String, dynamic> j) => InvSupplier(
        id: _toInt(j['id']),
        name: _toStr(j['name']),
        phone: _toStr(j['phone']),
        email: _toStr(j['email']),
        address: _toStr(j['address']),
        contactPerson: _toStr(j['contact_person']),
        paymentTermsDays: _toInt(j['payment_terms_days']),
        status: _toStr(j['status']).isEmpty ? 'active' : _toStr(j['status']),
        balance: _toDouble(j['balance']),
      );

  final int id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final String contactPerson;
  final int paymentTermsDays;
  final String status;
  final double balance;

  bool get owesMoney => balance > 0;
}

@immutable
class InvPurchaseOrder {
  const InvPurchaseOrder({
    required this.id,
    required this.number,
    required this.supplierId,
    required this.status,
    required this.total,
    this.supplierName = '',
    this.expectedAt,
    this.note = '',
    this.lines = const <InvPurchaseOrderLine>[],
  });

  factory InvPurchaseOrder.fromJson(Map<String, dynamic> j) {
    final List<dynamic> raw =
        (j['lines'] is List) ? j['lines'] as List<dynamic> : const [];

    return InvPurchaseOrder(
      id: _toInt(j['id']),
      number: _toStr(j['number']),
      supplierId: _toInt(j['supplier_id']),
      supplierName: _toStr(j['supplier_name']),
      status: _toStr(j['status']).isEmpty ? 'draft' : _toStr(j['status']),
      total: _toDouble(j['total']),
      expectedAt: DateTime.tryParse('${j['expected_at']}'),
      note: _toStr(j['note']),
      lines: raw
          .map((l) => InvPurchaseOrderLine.fromJson(l as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final int id;
  final String number;
  final int supplierId;
  final String supplierName;
  final String status;
  final double total;
  final DateTime? expectedAt;
  final String note;
  final List<InvPurchaseOrderLine> lines;

  bool get isOpen =>
      status == 'draft' || status == 'sent' || status == 'partial';
}

@immutable
class InvPurchaseOrderLine {
  const InvPurchaseOrderLine({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.receivedQuantity,
    required this.unitCost,
    this.productName = '',
    this.productUnit = '',
  });

  factory InvPurchaseOrderLine.fromJson(Map<String, dynamic> j) =>
      InvPurchaseOrderLine(
        id: _toInt(j['id']),
        productId: _toInt(j['product_id']),
        quantity: _toInt(j['quantity']),
        receivedQuantity: _toInt(j['received_quantity']),
        unitCost: _toDouble(j['unit_cost']),
        productName: _toStr(j['product_name']),
        productUnit: _toStr(j['product_unit']),
      );

  final int id;
  final int productId;
  final int quantity;
  final int receivedQuantity;
  final double unitCost;
  final String productName;
  final String productUnit;

  int get outstanding => (quantity - receivedQuantity).clamp(0, quantity);
  double get total => quantity * unitCost;
}

@immutable
class InvSupplierInvoice {
  const InvSupplierInvoice({
    required this.id,
    required this.number,
    required this.supplierId,
    required this.amount,
    required this.paidAmount,
    required this.status,
    this.supplierName = '',
    this.dueDate,
  });

  factory InvSupplierInvoice.fromJson(Map<String, dynamic> j) =>
      InvSupplierInvoice(
        id: _toInt(j['id']),
        number: _toStr(j['number']),
        supplierId: _toInt(j['supplier_id']),
        supplierName: _toStr(j['supplier_name']),
        amount: _toDouble(j['amount']),
        paidAmount: _toDouble(j['paid_amount']),
        status: _toStr(j['status']).isEmpty ? 'open' : _toStr(j['status']),
        dueDate: DateTime.tryParse('${j['due_date']}'),
      );

  final int id;
  final String number;
  final int supplierId;
  final String supplierName;
  final double amount;
  final double paidAmount;
  final String status;
  final DateTime? dueDate;

  double get balance => amount - paidAmount;
}

// --------------------------------------------------------------- Area 6

@immutable
class InvCreditCustomer {
  const InvCreditCustomer({
    required this.id,
    required this.name,
    required this.balance,
    required this.creditLimit,
    this.phone = '',
    this.paymentTermsDays = 0,
    this.isBlocked = false,
    this.blockReason = '',
    this.oldBalance = 0,
  });

  factory InvCreditCustomer.fromJson(Map<String, dynamic> j) =>
      InvCreditCustomer(
        id: _toInt(j['id']),
        name: _toStr(j['name']),
        phone: _toStr(j['phone']),
        balance: _toDouble(j['balance']),
        creditLimit: _toDouble(j['credit_limit']),
        paymentTermsDays: _toInt(j['payment_terms_days']),
        isBlocked: j['is_blocked'] == true || j['is_blocked'] == 1,
        blockReason: _toStr(j['block_reason']),
        oldBalance: _toDouble(j['old_balance']),
      );

  final int id;
  final String name;
  final String phone;
  final double balance;

  /// The part of [balance] that is an old debt (from before the app): paid under Money & debts, not against a sale.
  final double oldBalance;
  final double creditLimit;
  final int paymentTermsDays;
  final bool isBlocked;
  final String blockReason;

  bool get hasLimit => creditLimit > 0;
  bool get isOverLimit => hasLimit && balance > creditLimit;
  bool get isNearLimit =>
      hasLimit && !isOverLimit && balance >= creditLimit * 0.9;
  double get available =>
      hasLimit ? (creditLimit - balance).clamp(0, creditLimit) : 0;
  double get usedFraction =>
      hasLimit ? (balance / creditLimit).clamp(0, 1).toDouble() : 0;
}

@immutable
class InvDebtorAgeing {
  const InvDebtorAgeing({
    required this.customerId,
    required this.customerName,
    required this.current,
    required this.days31to60,
    required this.days61to90,
    required this.days90Plus,
    required this.total,
    this.customerPhone = '',
    this.oldestDays = 0,
  });

  factory InvDebtorAgeing.fromJson(Map<String, dynamic> j) => InvDebtorAgeing(
        customerId: _toInt(j['customer_id']),
        customerName: _toStr(j['customer_name']),
        customerPhone: _toStr(j['customer_phone']),
        current: _toDouble(j['current']),
        days31to60: _toDouble(j['days_31_60']),
        days61to90: _toDouble(j['days_61_90']),
        days90Plus: _toDouble(j['days_90_plus']),
        total: _toDouble(j['total']),
        oldestDays: _toInt(j['oldest_days']),
      );

  final int customerId;
  final String customerName;
  final String customerPhone;
  final double current;
  final double days31to60;
  final double days61to90;
  final double days90Plus;
  final double total;
  final int oldestDays;
}

@immutable
class InvStatement {
  const InvStatement({
    required this.openingBalance,
    required this.periodCharges,
    required this.periodPayments,
    required this.closingBalance,
    required this.lines,
    this.customerName = '',
    this.from = '',
    this.to = '',
  });

  factory InvStatement.fromJson(Map<String, dynamic> j) {
    final List<InvStatementLine> lines = <InvStatementLine>[];

    for (final dynamic s in (j['sales'] as List<dynamic>? ?? const [])) {
      final Map<String, dynamic> m = s as Map<String, dynamic>;
      lines.add(InvStatementLine(
        date: DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
        description: 'Sale ${_toStr(m['number'])}',
        charge: _toDouble(m['total']),
        payment: 0,
      ));
    }
    for (final dynamic p in (j['payments'] as List<dynamic>? ?? const [])) {
      final Map<String, dynamic> m = p as Map<String, dynamic>;
      lines.add(InvStatementLine(
        date: DateTime.tryParse('${m['paid_at']}') ?? DateTime.now(),
        description: 'Payment ${_toStr(m['sale_number'])}',
        charge: 0,
        payment: _toDouble(m['amount']),
      ));
    }
    lines.sort(
        (InvStatementLine a, InvStatementLine b) => a.date.compareTo(b.date));

    final Map<String, dynamic> customer = (j['customer'] is Map)
        ? Map<String, dynamic>.from(j['customer'] as Map)
        : const {};

    return InvStatement(
      customerName: _toStr(customer['name']),
      from: _toStr(j['from']),
      to: _toStr(j['to']),
      openingBalance: _toDouble(j['opening_balance']),
      periodCharges: _toDouble(j['period_charges']),
      periodPayments: _toDouble(j['period_payments']),
      closingBalance: _toDouble(j['closing_balance']),
      lines: lines,
    );
  }

  final String customerName;
  final String from;
  final String to;
  final double openingBalance;
  final double periodCharges;
  final double periodPayments;
  final double closingBalance;
  final List<InvStatementLine> lines;
}

@immutable
class InvStatementLine {
  const InvStatementLine({
    required this.date,
    required this.description,
    required this.charge,
    required this.payment,
  });

  final DateTime date;
  final String description;
  final double charge;
  final double payment;
}

// --------------------------------------------------------------- Area 7

@immutable
class InvCashSession {
  const InvCashSession({
    required this.id,
    required this.reference,
    required this.status,
    required this.openingFloat,
    required this.expectedCash,
    required this.countedCash,
    required this.expensesTotal,
    required this.difference,
    this.userName = '',
    this.businessDate = '',
    this.differenceReason = '',
    this.expenses = const <InvCashExpense>[],
  });

  factory InvCashSession.fromJson(Map<String, dynamic> j) {
    final List<dynamic> raw =
        (j['expenses'] is List) ? j['expenses'] as List<dynamic> : const [];

    return InvCashSession(
      id: _toInt(j['id']),
      reference: _toStr(j['reference']),
      status: _toStr(j['status']).isEmpty ? 'open' : _toStr(j['status']),
      userName: _toStr(j['user_name']),
      businessDate: _toStr(j['business_date']).split('T').first,
      openingFloat: _toDouble(j['opening_float']),
      // While open the server computes what the drawer should hold.
      expectedCash: j['computed_expected_cash'] != null
          ? _toDouble(j['computed_expected_cash'])
          : _toDouble(j['expected_cash']),
      countedCash: _toDouble(j['counted_cash']),
      expensesTotal: _toDouble(j['expenses_total']),
      difference: _toDouble(j['difference']),
      differenceReason: _toStr(j['difference_reason']),
      expenses: raw
          .map((e) => InvCashExpense.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final int id;
  final String reference;
  final String status;
  final String userName;
  final String businessDate;
  final double openingFloat;
  final double expectedCash;
  final double countedCash;
  final double expensesTotal;
  final double difference;
  final String differenceReason;
  final List<InvCashExpense> expenses;

  bool get isOpen => status == 'open';
  bool get isShort => difference < 0;
  bool get balances => difference.abs() < 0.01;
}

@immutable
class InvCashExpense {
  const InvCashExpense({
    required this.id,
    required this.description,
    required this.amount,
  });

  factory InvCashExpense.fromJson(Map<String, dynamic> j) => InvCashExpense(
        id: _toInt(j['id']),
        description: _toStr(j['description']),
        amount: _toDouble(j['amount']),
      );

  final int id;
  final String description;
  final double amount;
}

// --------------------------------------------------------------- Area 8

@immutable
class InvCrateType {
  const InvCrateType({
    required this.id,
    required this.name,
    required this.depositValue,
    this.status = 'active',
  });

  factory InvCrateType.fromJson(Map<String, dynamic> j) => InvCrateType(
        id: _toInt(j['id']),
        name: _toStr(j['name']),
        depositValue: _toDouble(j['deposit_value']),
        status: _toStr(j['status']).isEmpty ? 'active' : _toStr(j['status']),
      );

  final int id;
  final String name;
  final double depositValue;
  final String status;

  /// Switched-off types stay in the records but are not offered for new sales.
  bool get isActive => status == 'active';
}

@immutable
class InvCrateBalance {
  const InvCrateBalance({
    required this.crateTypeId,
    required this.crateTypeName,
    required this.held,
    required this.depositAtRisk,
    this.customerId,
    this.customerName = '',
    this.issued = 0,
    this.returned = 0,
    this.broken = 0,
    this.outWithCustomers = 0,
  });

  factory InvCrateBalance.fromJson(Map<String, dynamic> j) => InvCrateBalance(
        customerId: (j['customer_id'] as num?)?.toInt(),
        customerName: _toStr(j['customer_name']),
        crateTypeId: _toInt(j['crate_type_id']),
        crateTypeName: _toStr(j['crate_type_name']),
        held: _toInt(j['held']),
        issued: _toInt(j['issued']),
        returned: _toInt(j['returned']),
        broken: _toInt(j['broken']),
        outWithCustomers: _toInt(j['out_with_customers']),
        depositAtRisk: _toDouble(j['deposit_at_risk']),
      );

  final int? customerId;
  final String customerName;
  final int crateTypeId;
  final String crateTypeName;
  final int held;
  final int issued;
  final int returned;
  final int broken;
  final int outWithCustomers;
  final double depositAtRisk;
}

// --------------------------------------------------------------- Area 5

@immutable
class InvParkedSale {
  const InvParkedSale({
    required this.id,
    required this.reference,
    required this.total,
    required this.createdAt,
    this.customerId,
    this.customerName = '',
    this.note = '',
    this.parkedByName = '',
  });

  factory InvParkedSale.fromJson(Map<String, dynamic> j) => InvParkedSale(
        id: _toInt(j['id']),
        reference: _toStr(j['reference']),
        customerId: (j['customer_id'] as num?)?.toInt(),
        customerName: _toStr(j['customer_name']),
        total: _toDouble(j['total']),
        note: _toStr(j['note']),
        parkedByName: _toStr(j['parked_by_name']),
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
      );

  final int id;
  final String reference;
  final int? customerId;
  final String customerName;
  final double total;
  final String note;
  final String parkedByName;
  final DateTime createdAt;
}

@immutable
class InvSaleReturn {
  const InvSaleReturn({
    required this.id,
    required this.reference,
    required this.saleId,
    required this.type,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.saleNumber = '',
    this.reason = '',
    this.requestedByName = '',
  });

  factory InvSaleReturn.fromJson(Map<String, dynamic> j) => InvSaleReturn(
        id: _toInt(j['id']),
        reference: _toStr(j['reference']),
        saleId: _toInt(j['sale_id']),
        saleNumber: _toStr(j['sale_number']),
        type: _toStr(j['type']).isEmpty ? 'return' : _toStr(j['type']),
        amount: _toDouble(j['amount']),
        reason: _toStr(j['reason']),
        status: _toStr(j['status']).isEmpty ? 'pending' : _toStr(j['status']),
        requestedByName: _toStr(j['requested_by_name']),
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
      );

  final int id;
  final String reference;
  final int saleId;
  final String saleNumber;
  final String type;
  final double amount;
  final String reason;
  final String status;
  final String requestedByName;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
}

// --------------------------------------------------------------- Area 9

@immutable
class InvDispatch {
  const InvDispatch({
    required this.id,
    required this.reference,
    required this.status,
    required this.dispatchDate,
    this.vehicle = '',
    this.agentName = '',
    this.route = '',
    this.cashExpected = 0,
    this.cashReturned = 0,
    this.linesCount = 0,
    this.totalLoaded = 0,
    this.lines = const <InvDispatchLine>[],
  });

  factory InvDispatch.fromJson(Map<String, dynamic> j) {
    final List<dynamic> raw =
        (j['lines'] is List) ? j['lines'] as List<dynamic> : const [];

    return InvDispatch(
      id: _toInt(j['id']),
      reference: _toStr(j['reference']),
      status: _toStr(j['status']).isEmpty ? 'loading' : _toStr(j['status']),
      vehicle: _toStr(j['vehicle']),
      agentName: _toStr(j['agent_name']),
      route: _toStr(j['route']),
      dispatchDate: _toStr(j['dispatch_date']).split('T').first,
      cashExpected: _toDouble(j['cash_expected']),
      cashReturned: _toDouble(j['cash_returned']),
      linesCount: _toInt(j['lines_count']),
      totalLoaded: _toInt(j['total_loaded']),
      lines: raw
          .map((l) => InvDispatchLine.fromJson(l as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final int id;
  final String reference;
  final String status;
  final String vehicle;
  final String agentName;
  final String route;
  final String dispatchDate;
  final double cashExpected;
  final double cashReturned;
  final int linesCount;
  final int totalLoaded;
  final List<InvDispatchLine> lines;

  bool get isOnRoute => status == 'on_route';
  bool get isReconciled => status == 'reconciled';
  double get cashDifference => cashReturned - cashExpected;
}

@immutable
class InvDispatchLine {
  const InvDispatchLine({
    required this.id,
    required this.productId,
    required this.loadedQuantity,
    required this.returnedQuantity,
    required this.soldQuantity,
    required this.unitPrice,
    this.productName = '',
    this.productUnit = '',
    this.batchNumber = '',
  });

  factory InvDispatchLine.fromJson(Map<String, dynamic> j) => InvDispatchLine(
        id: _toInt(j['id']),
        productId: _toInt(j['product_id']),
        loadedQuantity: _toInt(j['loaded_quantity']),
        returnedQuantity: _toInt(j['returned_quantity']),
        soldQuantity: _toInt(j['sold_quantity']),
        unitPrice: _toDouble(j['unit_price']),
        productName: _toStr(j['product_name']),
        productUnit: _toStr(j['product_unit']),
        batchNumber: _toStr(j['batch_number']),
      );

  final int id;
  final int productId;
  final int loadedQuantity;
  final int returnedQuantity;
  final int soldQuantity;
  final double unitPrice;
  final String productName;
  final String productUnit;
  final String batchNumber;
}

// -------------------------------------------------------- Areas 11, 12, 13

@immutable
class InvReportMeta {
  const InvReportMeta({required this.key, required this.title});

  factory InvReportMeta.fromJson(Map<String, dynamic> j) => InvReportMeta(
        key: _toStr(j['key']),
        title: _toStr(j['title']),
      );

  final String key;
  final String title;
}

/// A rendered report: ordered columns, rows keyed by column, and totals.
@immutable
class InvReport {
  const InvReport({
    required this.key,
    required this.title,
    required this.columns,
    required this.rows,
    required this.meta,
    this.from = '',
    this.to = '',
  });

  factory InvReport.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> cols = (j['columns'] is Map)
        ? Map<String, dynamic>.from(j['columns'] as Map)
        : <String, dynamic>{};

    return InvReport(
      key: _toStr(j['key']),
      title: _toStr(j['title']),
      from: _toStr(j['from']),
      to: _toStr(j['to']),
      columns: cols.entries
          .map((MapEntry<String, dynamic> e) =>
              InvReportColumn(field: e.key, label: _toStr(e.value)))
          .toList(growable: false),
      rows: (j['rows'] as List<dynamic>? ?? const [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList(growable: false),
      meta: (j['meta'] is Map)
          ? Map<String, dynamic>.from(j['meta'] as Map)
          : <String, dynamic>{},
    );
  }

  final String key;
  final String title;
  final String from;
  final String to;
  final List<InvReportColumn> columns;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> meta;

  bool get isEmpty => rows.isEmpty;
}

@immutable
class InvReportColumn {
  const InvReportColumn({required this.field, required this.label});

  final String field;
  final String label;
}

@immutable
class InvAlert {
  const InvAlert({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.status,
    required this.createdAt,
    this.body = '',
    this.entityType = '',
    this.entityId,
  });

  factory InvAlert.fromJson(Map<String, dynamic> j) => InvAlert(
        id: _toInt(j['id']),
        type: _toStr(j['type']),
        severity:
            _toStr(j['severity']).isEmpty ? 'info' : _toStr(j['severity']),
        title: _toStr(j['title']),
        body: _toStr(j['body']),
        entityType: _toStr(j['entity_type']),
        entityId: (j['entity_id'] as num?)?.toInt(),
        status: _toStr(j['status']).isEmpty ? 'open' : _toStr(j['status']),
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
      );

  final int id;
  final String type;
  final String severity;
  final String title;
  final String body;
  final String entityType;
  final int? entityId;
  final String status;
  final DateTime createdAt;

  bool get isCritical => severity == 'critical';
  bool get isOpen => status == 'open';
}

@immutable
class InvAuditEntry {
  const InvAuditEntry({
    required this.id,
    required this.entityType,
    required this.action,
    required this.createdAt,
    this.entityId,
    this.summary = '',
    this.userName = '',
  });

  factory InvAuditEntry.fromJson(Map<String, dynamic> j) => InvAuditEntry(
        id: _toInt(j['id']),
        entityType: _toStr(j['entity_type']),
        entityId: (j['entity_id'] as num?)?.toInt(),
        action: _toStr(j['action']),
        summary: _toStr(j['summary']),
        userName: _toStr(j['user_name']),
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
      );

  final int id;
  final String entityType;
  final int? entityId;
  final String action;
  final String summary;
  final String userName;
  final DateTime createdAt;
}

/// A scanned barcode resolved to what it identifies.
@immutable
class InvScanResult {
  const InvScanResult({
    required this.entityType,
    required this.entityId,
    this.productId,
    this.productName = '',
    this.label = '',
  });

  factory InvScanResult.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> detail = (j['detail'] is Map)
        ? Map<String, dynamic>.from(j['detail'] as Map)
        : <String, dynamic>{};

    return InvScanResult(
      entityType: _toStr(j['entity_type']),
      entityId: _toInt(j['entity_id']),
      productId: (detail['product_id'] as num?)?.toInt(),
      productName: _toStr(detail['product_name']).isNotEmpty
          ? _toStr(detail['product_name'])
          : _toStr(detail['name']),
      label: _toStr(detail['batch_number']).isNotEmpty
          ? _toStr(detail['batch_number'])
          : _toStr(detail['name']),
    );
  }

  final String entityType;
  final int entityId;
  final int? productId;
  final String productName;
  final String label;
}
