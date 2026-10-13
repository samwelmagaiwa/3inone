import '../services/localization_service.dart';
class PaymentReceipt {
  PaymentReceipt({
    required this.id,
    required this.receiptNumber,
    required this.paymentId,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.amount,
    required this.paymentPeriod,
    required this.coveredDays,
    required this.status,
    required this.generatedAt,
    required this.ownerName,
    required this.receiptData,
    this.driverEmail,
    this.sentAt,
    this.sentVia,
  });

  factory PaymentReceipt.fromJson(Map<String, dynamic> json) {
    return PaymentReceipt(
      id: json['id']?.toString() ?? '',
      receiptNumber: json['receipt_number'] ?? '',
      paymentId: json['payment_id']?.toString() ?? '',
      driverId: json['driver_id']?.toString() ?? '',
      driverName: json['driver_name'] ?? '',
      driverPhone: json['driver_phone'] ?? '',
      driverEmail: json['driver_email'],
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      paymentPeriod: json['payment_period'] ?? '',
      coveredDays: List<String>.from(json['covered_days'] ?? []),
      status: json['status'] ?? 'generated',
      generatedAt: DateTime.tryParse(json['generated_at']?.toString() ?? '') ??
          DateTime.now(),
      sentAt:
          json['sent_at'] != null ? DateTime.tryParse(json['sent_at']) : null,
      sentVia: json['sent_via'],
      ownerName: json['owner_name'] ?? '',
      receiptData: ReceiptData.fromJson(json['receipt_data'] ?? {}),
    );
  }
  final String id;
  final String receiptNumber;
  final String paymentId;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String? driverEmail;
  final double amount;
  final String paymentPeriod;
  final List<String> coveredDays;
  final String status;
  final DateTime generatedAt;
  final DateTime? sentAt;
  final String? sentVia;
  final String ownerName;
  final ReceiptData receiptData;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'receipt_number': receiptNumber,
      'payment_id': paymentId,
      'driver_id': driverId,
      'driver_name': driverName,
      'driver_phone': driverPhone,
      'driver_email': driverEmail,
      'amount': amount,
      'payment_period': paymentPeriod,
      'covered_days': coveredDays,
      'status': status,
      'generated_at': generatedAt.toIso8601String(),
      'sent_at': sentAt?.toIso8601String(),
      'sent_via': sentVia,
      'owner_name': ownerName,
      'receipt_data': receiptData.toJson(),
    };
  }

  bool get isSent => ['sent', 'delivered'].contains(status);

  String get formattedAmount =>
      'TSh ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';

  String get formattedGeneratedDate => _formatDate(generatedAt);

  String get formattedSentDate => sentAt != null ? _formatDate(sentAt!) : '';

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String get formattedGeneratedDateTime => _formatDateTime(generatedAt);

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class ReceiptData {
  ReceiptData({
    required this.companyName,
    required this.companyAddress,
    required this.companyPhone,
    required this.issueDate,
    required this.issueTime,
    required this.driverName,
    required this.driverPhone,
    required this.vehicleInfo,
    required this.paymentAmount,
    required this.amountInWords,
    required this.paymentChannel,
    required this.paymentDate,
    required this.coveredPeriod,
    required this.coveredDaysList,
    required this.remarks,
    required this.recordedBy,
  });

  factory ReceiptData.fromJson(Map<String, dynamic> json) {
    return ReceiptData(
      companyName: json['company_name'] ?? '',
      companyAddress: json['company_address'] ?? '',
      companyPhone: json['company_phone'] ?? '',
      issueDate: json['issue_date'] ?? '',
      issueTime: json['issue_time'] ?? '',
      driverName: json['driver_name'] ?? '',
      driverPhone: json['driver_phone'] ?? '',
      vehicleInfo: json['vehicle_info'] ?? '',
      paymentAmount: json['payment_amount'] ?? '0',
      amountInWords: json['amount_in_words'] ?? '',
      paymentChannel: json['payment_channel'] ?? '',
      paymentDate: json['payment_date'] ?? '',
      coveredPeriod: json['covered_period'] ?? '',
      coveredDaysList: List<String>.from(json['covered_days_list'] ?? []),
      remarks: json['remarks'] ?? '',
      recordedBy: json['recorded_by'] ?? '',
    );
  }
  final String companyName;
  final String companyAddress;
  final String companyPhone;
  final String issueDate;
  final String issueTime;
  final String driverName;
  final String driverPhone;
  final String vehicleInfo;
  final String paymentAmount;
  final String amountInWords;
  final String paymentChannel;
  final String paymentDate;
  final String coveredPeriod;
  final List<String> coveredDaysList;
  final String remarks;
  final String recordedBy;

  Map<String, dynamic> toJson() {
    return {
      'company_name': companyName,
      'company_address': companyAddress,
      'company_phone': companyPhone,
      'issue_date': issueDate,
      'issue_time': issueTime,
      'driver_name': driverName,
      'driver_phone': driverPhone,
      'vehicle_info': vehicleInfo,
      'payment_amount': paymentAmount,
      'amount_in_words': amountInWords,
      'payment_channel': paymentChannel,
      'payment_date': paymentDate,
      'covered_period': coveredPeriod,
      'covered_days_list': coveredDaysList,
      'remarks': remarks,
      'recorded_by': recordedBy,
    };
  }
}

class PendingReceiptItem {
  PendingReceiptItem({
    required this.paymentId,
    required this.referenceNumber,
    required this.driver,
    required this.amount,
    required this.paymentDate,
    required this.paymentTime,
    required this.formattedDate,
    required this.paymentChannel,
    required this.formattedPaymentChannel,
    required this.coveredDays,
    required this.coveredDaysCount,
    required this.paymentPeriod,
    required this.recordedBy,
    required this.hasRemainingDebt,
    required this.remainingDebtTotal,
    required this.unpaidDaysCount,
    required this.unpaidDates,
    this.remarks,
  });

  factory PendingReceiptItem.fromJson(Map<String, dynamic> json) {
    return PendingReceiptItem(
      paymentId: json['payment_id']?.toString() ?? '',
      referenceNumber: json['reference_number'] ?? '',
      driver: DriverInfo.fromJson(json['driver'] ?? {}),
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      paymentDate: json['payment_date'] ?? '',
      paymentTime: json['payment_time'] ?? '',
      formattedDate: json['formatted_date'] ?? '',
      paymentChannel: json['payment_channel'] ?? '',
      formattedPaymentChannel: json['formatted_payment_channel'] ?? '',
      coveredDays: List<String>.from(json['covered_days'] ?? []),
      coveredDaysCount: json['covered_days_count'] ?? 0,
      paymentPeriod: json['payment_period'] ?? '',
      remarks: json['remarks'],
      recordedBy: json['recorded_by'] ?? '',
      hasRemainingDebt: json['has_remaining_debt'] ?? false,
      remainingDebtTotal:
          double.tryParse(json['remaining_debt_total']?.toString() ?? '0') ??
              0.0,
      unpaidDaysCount: json['unpaid_days_count'] ?? 0,
      unpaidDates: List<String>.from(json['unpaid_dates'] ?? const []),
    );
  }
  final String paymentId;
  final String referenceNumber;
  final DriverInfo driver;
  final double amount;
  final String paymentDate;
  final String paymentTime;
  final String formattedDate;
  final String paymentChannel;
  final String formattedPaymentChannel;
  final List<String> coveredDays;
  final int coveredDaysCount;
  final String paymentPeriod;
  final String? remarks;
  final String recordedBy;
  // New: outstanding debt info
  final bool hasRemainingDebt;
  final double remainingDebtTotal;
  final int unpaidDaysCount;
  final List<String> unpaidDates;

  String get formattedAmount =>
      'TSh ${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
}

class DriverInfo {
  DriverInfo({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
  });

  factory DriverInfo.fromJson(Map<String, dynamic> json) {
    return DriverInfo(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'],
    );
  }
  final String id;
  final String name;
  final String phone;
  final String? email;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
    };
  }
}

enum ReceiptSendMethod {
  whatsapp,
  email,
  system;

  String get displayName {
    switch (this) {
      case ReceiptSendMethod.whatsapp:
        return 'WhatsApp';
      case ReceiptSendMethod.email:
        return LocalizationService.instance.translate('email_message');
      case ReceiptSendMethod.system:
        return LocalizationService.instance.translate('system_message');
    }
  }

  String get value {
    switch (this) {
      case ReceiptSendMethod.whatsapp:
        return 'whatsapp';
      case ReceiptSendMethod.email:
        return 'email';
      case ReceiptSendMethod.system:
        return 'system';
    }
  }

  static ReceiptSendMethod fromString(String value) {
    switch (value.toLowerCase()) {
      case 'whatsapp':
        return ReceiptSendMethod.whatsapp;
      case 'email':
        return ReceiptSendMethod.email;
      case 'system':
        return ReceiptSendMethod.system;
      default:
        return ReceiptSendMethod.system;
    }
  }
}
