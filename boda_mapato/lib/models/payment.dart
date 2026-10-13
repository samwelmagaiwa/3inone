import '../services/localization_service.dart';
class Payment {
  Payment({
    required this.driverId,
    required this.driverName,
    required this.amount,
    required this.paymentChannel,
    required this.coversDays,
    required this.createdAt,
    this.id,
    this.remarks,
    this.referenceNumber,
  });

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: json['id']?.toString(),
        driverId: json['driver_id']?.toString() ?? '',
        driverName: json['driver_name']?.toString() ?? '',
        amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
        paymentChannel: PaymentChannel.fromString(
          json['payment_channel']?.toString() ?? 'cash',
        ),
        coversDays: List<String>.from(json['covers_days'] ?? []),
        remarks: json['remarks']?.toString(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
            DateTime.now(),
        referenceNumber: json['reference_number']?.toString(),
      );
  final String? id;
  final String driverId;
  final String driverName;
  final double amount;
  final PaymentChannel paymentChannel;
  final List<String> coversDays;
  final String? remarks;
  final DateTime createdAt;
  final String? referenceNumber;

  Map<String, dynamic> toJson() => {
        'id': id,
        'driver_id': driverId,
        'driver_name': driverName,
        'amount': amount,
        'payment_channel': paymentChannel.value,
        'covers_days': coversDays,
        'remarks': remarks,
        'created_at': createdAt.toIso8601String(),
        'reference_number': referenceNumber,
      };

  Payment copyWith({
    String? id,
    String? driverId,
    String? driverName,
    double? amount,
    PaymentChannel? paymentChannel,
    List<String>? coversDays,
    String? remarks,
    DateTime? createdAt,
    String? referenceNumber,
  }) =>
      Payment(
        id: id ?? this.id,
        driverId: driverId ?? this.driverId,
        driverName: driverName ?? this.driverName,
        amount: amount ?? this.amount,
        paymentChannel: paymentChannel ?? this.paymentChannel,
        coversDays: coversDays ?? this.coversDays,
        remarks: remarks ?? this.remarks,
        createdAt: createdAt ?? this.createdAt,
        referenceNumber: referenceNumber ?? this.referenceNumber,
      );
}

enum PaymentChannel {
  cash('cash'),
  bank('bank'),
  mobile('mobile'),
  other('other');

  const PaymentChannel(this.value);

  final String value;

  /// The name shown for the channel, in the language chosen in the app.
  String get displayName {
    switch (this) {
      case PaymentChannel.cash:
        return LocalizationService.instance.translate('payment_channel_cash');
      case PaymentChannel.bank:
        return LocalizationService.instance.translate('payment_channel_bank');
      case PaymentChannel.mobile:
        return LocalizationService.instance.translate('mobile_money');
      case PaymentChannel.other:
        return LocalizationService.instance.translate('other');
    }
  }

  static PaymentChannel fromString(String value) {
    return PaymentChannel.values.firstWhere(
      (channel) => channel.value == value.toLowerCase(),
      orElse: () => PaymentChannel.cash,
    );
  }
}

class DebtRecord {
  DebtRecord({
    required this.driverId,
    required this.driverName,
    required this.date,
    required this.expectedAmount,
    this.id,
    this.paidAmount = 0.0,
    this.isPaid = false,
    this.paymentId,
    this.paidAt,
    this.daysOverdue = 0,
    this.licenseNumber,
    this.promisedToPay = false,
    this.promiseToPayAt,
  });

  factory DebtRecord.fromJson(Map<String, dynamic> json) => DebtRecord(
        id: json['id']?.toString(),
        driverId: json['driver_id']?.toString() ?? '',
        driverName: json['driver_name']?.toString() ?? '',
        date: json['date']?.toString() ?? '',
        expectedAmount:
            double.tryParse(json['expected_amount']?.toString() ?? '0') ?? 0.0,
        paidAmount:
            double.tryParse(json['paid_amount']?.toString() ?? '0') ?? 0.0,
        isPaid: json['is_paid'] == true || json['is_paid'] == 1,
        paymentId: json['payment_id']?.toString(),
        paidAt: json['paid_at'] != null
            ? DateTime.tryParse(json['paid_at'].toString())
            : null,
        daysOverdue: int.tryParse(json['days_overdue']?.toString() ?? '0') ?? 0,
        licenseNumber: json['license_number']?.toString(),
        promisedToPay:
            json['promised_to_pay'] == true || json['promised_to_pay'] == 1,
        promiseToPayAt: json['promise_to_pay_at'] != null
            ? DateTime.tryParse(json['promise_to_pay_at'].toString())
            : null,
      );
  final String? id;
  final String driverId;
  final String driverName;
  final String date;
  final double expectedAmount;
  final double paidAmount;
  final bool isPaid;
  final String? paymentId;
  final DateTime? paidAt;
  final int daysOverdue;
  final String? licenseNumber;
  final bool promisedToPay;
  final DateTime? promiseToPayAt;

  double get remainingAmount => expectedAmount - paidAmount;

  bool get isOverdue => daysOverdue > 0;

  String get formattedDate {
    try {
      final parsedDate = DateTime.parse(date);
      return "${parsedDate.day}/${parsedDate.month}/${parsedDate.year}";
    } on FormatException catch (_) {
      return date;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'driver_id': driverId,
        'driver_name': driverName,
        'date': date,
        'expected_amount': expectedAmount,
        'paid_amount': paidAmount,
        'is_paid': isPaid,
        'payment_id': paymentId,
        'paid_at': paidAt?.toIso8601String(),
        'days_overdue': daysOverdue,
        'license_number': licenseNumber,
        'promised_to_pay': promisedToPay,
        'promise_to_pay_at': promiseToPayAt?.toIso8601String(),
      };

  DebtRecord copyWith({
    String? id,
    String? driverId,
    String? driverName,
    String? date,
    double? expectedAmount,
    double? paidAmount,
    bool? isPaid,
    String? paymentId,
    DateTime? paidAt,
    int? daysOverdue,
    String? licenseNumber,
    bool? promisedToPay,
    DateTime? promiseToPayAt,
  }) =>
      DebtRecord(
        id: id ?? this.id,
        driverId: driverId ?? this.driverId,
        driverName: driverName ?? this.driverName,
        date: date ?? this.date,
        expectedAmount: expectedAmount ?? this.expectedAmount,
        paidAmount: paidAmount ?? this.paidAmount,
        isPaid: isPaid ?? this.isPaid,
        paymentId: paymentId ?? this.paymentId,
        paidAt: paidAt ?? this.paidAt,
        daysOverdue: daysOverdue ?? this.daysOverdue,
        licenseNumber: licenseNumber ?? this.licenseNumber,
        promisedToPay: promisedToPay ?? this.promisedToPay,
        promiseToPayAt: promiseToPayAt ?? this.promiseToPayAt,
      );
}

class PaymentSummary {
  PaymentSummary({
    required this.driverId,
    required this.driverName,
    required this.totalDebt,
    required this.unpaidDays,
    required this.debtRecords,
    this.lastPaymentDate,
  });

  factory PaymentSummary.fromJson(Map<String, dynamic> json) => PaymentSummary(
        driverId: json['driver_id']?.toString() ?? '',
        driverName: json['driver_name']?.toString() ?? '',
        totalDebt:
            double.tryParse(json['total_debt']?.toString() ?? '0') ?? 0.0,
        unpaidDays: int.tryParse(json['unpaid_days']?.toString() ?? '0') ?? 0,
        debtRecords: (json['debt_records'] as List<dynamic>? ?? [])
            .map(
                (record) => DebtRecord.fromJson(record as Map<String, dynamic>))
            .toList(),
        lastPaymentDate: json['last_payment_date'] != null
            ? DateTime.tryParse(json['last_payment_date'].toString())
            : null,
      );
  final String driverId;
  final String driverName;
  final double totalDebt;
  final int unpaidDays;
  final List<DebtRecord> debtRecords;
  final DateTime? lastPaymentDate;

  Map<String, dynamic> toJson() => {
        'driver_id': driverId,
        'driver_name': driverName,
        'total_debt': totalDebt,
        'unpaid_days': unpaidDays,
        'debt_records': debtRecords.map((record) => record.toJson()).toList(),
        'last_payment_date': lastPaymentDate?.toIso8601String(),
      };
}
