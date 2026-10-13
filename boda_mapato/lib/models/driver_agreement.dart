import '../services/localization_service.dart';

class DriverAgreement {
  DriverAgreement({
    required this.driverId,
    required this.agreementType,
    required this.startDate,
    required this.kiasiChaMakubaliano,
    required this.wikendiZinahesabika,
    required this.jumamosi,
    required this.jumapili,
    required this.paymentFrequencies,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.id,
    this.endDate,
    this.mwakaAtamaliza,
    this.faidaJumla,
  });

  // Convert from JSON
  factory DriverAgreement.fromJson(Map<String, dynamic> json) {
    return DriverAgreement(
      id: json['id']?.toString(),
      driverId: json['driver_id']?.toString() ?? '',
      agreementType:
          AgreementType.fromString(json['agreement_type']?.toString() ?? ''),
      startDate: DateTime.tryParse(json['start_date']?.toString() ?? '') ??
          DateTime.now(),
      endDate: json['end_date'] != null
          ? DateTime.tryParse(json['end_date'].toString())
          : null,
      mwakaAtamaliza: json['mwaka_atamaliza']?.toString(),
      kiasiChaMakubaliano:
          double.tryParse(json['kiasi_cha_makubaliano']?.toString() ?? '0') ??
              0.0,
      faidaJumla: json['faida_jumla'] != null
          ? double.tryParse(json['faida_jumla'].toString())
          : null,
      wikendiZinahesabika: json['wikendi_zinahesabika'] == true ||
          json['wikendi_zinahesabika'] == 1,
      jumamosi: json['jumamosi'] == true || json['jumamosi'] == 1,
      jumapili: json['jumapili'] == true || json['jumapili'] == 1,
      paymentFrequencies: _parsePaymentFrequencies(json['payment_frequencies']),
      status:
          AgreementStatus.fromString(json['status']?.toString() ?? 'active'),
      createdBy: json['created_by']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
  final String? id;
  final String driverId;
  final AgreementType agreementType;
  final DateTime startDate;
  final DateTime? endDate;
  final String? mwakaAtamaliza;
  final double kiasiChaMakubaliano;
  final double? faidaJumla;
  final bool wikendiZinahesabika;
  final bool jumamosi;
  final bool jumapili;
  final List<PaymentFrequency> paymentFrequencies;
  final AgreementStatus status;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driver_id': driverId,
      'agreement_type': agreementType.value,
      'start_date': startDate.toIso8601String().split('T')[0], // Date only
      'end_date': endDate?.toIso8601String().split('T')[0],
      'mwaka_atamaliza': mwakaAtamaliza,
      'kiasi_cha_makubaliano': kiasiChaMakubaliano,
      'faida_jumla': faidaJumla,
      'wikendi_zinahesabika': wikendiZinahesabika,
      'jumamosi': jumamosi,
      'jumapili': jumapili,
      'payment_frequencies': paymentFrequencies.map((f) => f.value).toList(),
      'status': status.value,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Create a copy with modifications
  DriverAgreement copyWith({
    String? id,
    String? driverId,
    AgreementType? agreementType,
    DateTime? startDate,
    DateTime? endDate,
    String? mwakaAtamaliza,
    double? kiasiChaMakubaliano,
    double? faidaJumla,
    bool? wikendiZinahesabika,
    bool? jumamosi,
    bool? jumapili,
    List<PaymentFrequency>? paymentFrequencies,
    AgreementStatus? status,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DriverAgreement(
      id: id ?? this.id,
      driverId: driverId ?? this.driverId,
      agreementType: agreementType ?? this.agreementType,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      mwakaAtamaliza: mwakaAtamaliza ?? this.mwakaAtamaliza,
      kiasiChaMakubaliano: kiasiChaMakubaliano ?? this.kiasiChaMakubaliano,
      faidaJumla: faidaJumla ?? this.faidaJumla,
      wikendiZinahesabika: wikendiZinahesabika ?? this.wikendiZinahesabika,
      jumamosi: jumamosi ?? this.jumamosi,
      jumapili: jumapili ?? this.jumapili,
      paymentFrequencies: paymentFrequencies ?? this.paymentFrequencies,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper method to parse payment frequencies from JSON
  static List<PaymentFrequency> _parsePaymentFrequencies(data) {
    if (data == null) return [];

    if (data is List) {
      return data
          .map((item) => PaymentFrequency.fromString(item.toString()))
          .toList();
    }

    return [];
  }

  @override
  String toString() {
    return 'DriverAgreement(id: $id, driverId: $driverId, agreementType: $agreementType, startDate: $startDate)';
  }
}

// Agreement Type Enum
enum AgreementType {
  kwaMkataba('kwa_mkataba'),
  deiWaka('dei_waka');

  const AgreementType(this.value);

  final String value;

  /// The name shown for the agreement type, in the language chosen in the app.
  String get displayName => LocalizationService.instance.translate(
      this == AgreementType.kwaMkataba ? 'agreement_type_contract' : 'agreement_type_day_worker');

  static AgreementType fromString(String value) {
    return AgreementType.values.firstWhere(
      (type) => type.value == value.toLowerCase(),
      orElse: () => AgreementType.kwaMkataba,
    );
  }
}

// Payment Frequency Enum
enum PaymentFrequency {
  kilaSiku('kila_siku'),
  kilaWiki('kila_wiki'),
  kilaMwezi('kila_mwezi');

  const PaymentFrequency(this.value);

  final String value;

  /// The name shown for the payment frequency, in the language chosen in the app.
  String get displayName {
    switch (this) {
      case PaymentFrequency.kilaSiku:
        return LocalizationService.instance.translate('every_day');
      case PaymentFrequency.kilaWiki:
        return LocalizationService.instance.translate('every_week');
      case PaymentFrequency.kilaMwezi:
        return LocalizationService.instance.translate('every_month');
    }
  }

  static PaymentFrequency fromString(String value) {
    return PaymentFrequency.values.firstWhere(
      (freq) => freq.value == value.toLowerCase(),
      orElse: () => PaymentFrequency.kilaSiku,
    );
  }
}

// Agreement Status Enum
enum AgreementStatus {
  active('active'),
  inactive('inactive'),
  completed('completed'),
  terminated('terminated');

  const AgreementStatus(this.value);

  final String value;

  /// The name shown for the status, in the language chosen in the app.
  String get displayName {
    switch (this) {
      case AgreementStatus.active:
        return LocalizationService.instance.translate('active');
      case AgreementStatus.inactive:
        return LocalizationService.instance.translate('inactive_driver');
      case AgreementStatus.completed:
        return LocalizationService.instance.translate('status_completed');
      case AgreementStatus.terminated:
        return LocalizationService.instance.translate('deleted');
    }
  }

  static AgreementStatus fromString(String value) {
    return AgreementStatus.values.firstWhere(
      (status) => status.value == value.toLowerCase(),
      orElse: () => AgreementStatus.active,
    );
  }
}

// Response wrapper for API calls
class DriverAgreementResponse {
  DriverAgreementResponse({
    required this.success,
    required this.message,
    this.data,
    this.errors,
  });

  factory DriverAgreementResponse.fromJson(Map<String, dynamic> json) {
    return DriverAgreementResponse(
      success: json['success'] == true,
      message: json['message']?.toString() ?? '',
      data:
          json['data'] != null ? DriverAgreement.fromJson(json['data']) : null,
      errors: json['errors'] as Map<String, dynamic>?,
    );
  }
  final bool success;
  final String message;
  final DriverAgreement? data;
  final Map<String, dynamic>? errors;
}
