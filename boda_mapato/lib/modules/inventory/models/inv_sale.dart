class InvSaleItem {
  InvSaleItem({
    required this.productId,
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.unitCostSnapshot,
    this.unitId,
    this.unitName,
    this.unitFactor = 1,
    this.taxPercent,
    this.taxAmount = 0,
    this.staffId,
    this.staffName,
    this.isService = false,
  });
  final int productId;
  final String name;

  /// How many of the selling unit (a crate, a kg) -- always a whole number.
  int qty;

  /// The price of ONE selling unit.
  double unitPrice;

  /// The cost of one BASE unit (a bottle, a gram).
  double unitCostSnapshot;

  /// The selling unit this line is in (null = the product's own base unit) and how many base units it holds.
  int? unitId;
  String? unitName;
  int unitFactor;

  /// The VAT rate of this line and the VAT it carries (set by the cart, or read from a saved sale).
  double? taxPercent;
  double taxAmount;

  /// Salon: who served the client for this line (their account id, and their name as it was), and whether the
  /// line is a service (it never touches stock).
  String? staffId;
  String? staffName;
  final bool isService;

  /// A cart holds one line per product AND unit: 1 crate and 3 bottles of the same drink are two lines.
  String get key => '$productId:${unitId ?? 0}';

  /// What leaves the stock: whole base units.
  int get baseQty => qty * (unitFactor < 1 ? 1 : unitFactor);

  double get total => qty * unitPrice;
  double get profit => total - unitCostSnapshot * baseQty;
}

class InvPayment {
  InvPayment({
    required this.amount,
    required this.method, // cash / mobile / bank (for MVP we use cash)
    required this.paidAt,
    this.reference = '',
  });
  final double amount;
  final String method;
  final DateTime paidAt;
  final String reference;
}

class InvSale {
  InvSale({
    required this.id,
    required this.number,
    required this.paymentStatus, // paid / debt / partial
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.paidTotal,
    required this.createdBy,
    required this.createdAt,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.dueDate,
    this.cancelledAt,
    this.cancellationReason,
    this.payments = const [],
  });

  final int id;
  final String number;
  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  String paymentStatus;
  final List<InvSaleItem> items;
  double subtotal;
  double discount;
  double tax;
  double total;
  double paidTotal;
  DateTime? dueDate;
  DateTime? cancelledAt;
  String? cancellationReason;
  int createdBy;
  DateTime createdAt;
  List<InvPayment> payments;

  bool get isCancelled => cancelledAt != null;
  double get profit => items.fold(0, (sum, it) => sum + it.profit);
  int get totalItems => items.fold(0, (sum, it) => sum + it.qty);
}
