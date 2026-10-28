import "package:flutter/foundation.dart";

@immutable
class Driver {
  const Driver({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.licenseNumber,
    required this.status,
    required this.totalPayments,
    required this.joinedDate,
    required this.rating,
    required this.tripsCompleted,
    this.vehicleNumber,
    this.vehicleType,
    this.lastPayment,
    this.totalDebt = 0,
    this.unpaidDays = 0,
    this.dueDates = const <String>[],
    this.hasCompletedAgreement = false,
    this.agreementStatus,
    this.branchId,
  });

  factory Driver.fromJson(final Map<String, dynamic> json) {
    double parseDouble(final Object? v) {
      if (v == null) {
        return 0;
      }
      if (v is num) {
        return v.toDouble();
      }
      if (v is String) {
        return double.tryParse(v) ?? 0;
      }
      return 0;
    }

    int parseInt(final Object? v) {
      if (v == null) {
        return 0;
      }
      if (v is int) {
        return v;
      }
      if (v is num) {
        return v.toInt();
      }
      if (v is String) {
        return int.tryParse(v) ?? 0;
      }
      return 0;
    }

    // Fallback helpers for flexible API shapes
    String pickString(List<Object?> options) {
      for (final Object? v in options) {
        if (v == null) continue;
        final String s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
      return '';
    }

    final dynamic userMap =
        json['user'] ?? json['owner'] ?? json['created_by_user'];
    final dynamic driverMap = json['driver'];

    // Compose name from possible first/last name pairs
    String composeName(Map<String, dynamic>? m) {
      if (m == null) return '';
      final String first =
          pickString([m['first_name'], m['firstName'], m['given_name']]);
      final String last = pickString(
          [m['last_name'], m['lastName'], m['surname'], m['family_name']]);
      final String combined = '$first $last'.trim();
      if (combined.isNotEmpty) return combined;
      return pickString([m['name'], m['full_name'], m['driver_name']]);
    }

    final String name = pickString([
      json['name'],
      json['full_name'],
      json['driver_name'],
      composeName(json as Map<String, dynamic>?),
      composeName(userMap is Map<String, dynamic> ? userMap : null),
      composeName(driverMap is Map<String, dynamic> ? driverMap : null),
      if (userMap is Map<String, dynamic>) userMap['name'] else null,
      if (driverMap is Map<String, dynamic>) driverMap['name'] else null,
    ]);
    final String email = pickString([
      json['email'],
      if (userMap is Map<String, dynamic>) userMap['email'] else null,
      if (driverMap is Map<String, dynamic>) driverMap['email'] else null,
    ]);
    final String phone = pickString([
      json['phone'],
      json['phone_number'],
      json['phoneNumber'],
      ' ${pickString([])}',
      if (userMap is Map<String, dynamic>) userMap['phone_number'] else null,
      if (driverMap is Map<String, dynamic>)
        driverMap['phone_number']
      else
        null,
    ]);
    final String license = pickString([
      json['license_number'],
      json['license'],
      json['license_no'],
      if (driverMap is Map<String, dynamic>)
        driverMap['license_number']
      else
        null,
    ]);
    final String? vehicleNo = pickString([
      json['vehicle_number'],
      json['plate_number'],
      json['registration_no'],
      if (driverMap is Map<String, dynamic>)
        driverMap['vehicle_number']
      else
        null,
    ]).isNotEmpty
        ? pickString([
            json['vehicle_number'],
            json['plate_number'],
            json['registration_no'],
            if (driverMap is Map<String, dynamic>)
              driverMap['vehicle_number']
            else
              null,
          ])
        : null;
    final String? vehicleTy = pickString([
      json['vehicle_type'],
      json['type'],
      if (driverMap is Map<String, dynamic>)
        driverMap['vehicle_type']
      else
        null,
    ]).isNotEmpty
        ? pickString([
            json['vehicle_type'],
            json['type'],
            if (driverMap is Map<String, dynamic>)
              driverMap['vehicle_type']
            else
              null,
          ])
        : null;
    final String status = pickString([
      json['status'],
      if (json['is_active'] == true || json['is_active'] == 1) 'active' else '',
      if (userMap is Map<String, dynamic>)
        (userMap['is_active'] == true || userMap['is_active'] == 1)
            ? 'active'
            : ''
      else
        '',
      if (driverMap is Map<String, dynamic>)
        (driverMap['is_active'] == true || driverMap['is_active'] == 1)
            ? 'active'
            : ''
      else
        '',
    ]);

    return Driver(
      id: (json["id"] ?? "").toString(),
      name: name,
      email: email,
      phone: phone,
      licenseNumber: license,
      vehicleNumber: vehicleNo,
      vehicleType: vehicleTy,
      status: status.isNotEmpty ? status : 'inactive',
      totalPayments: parseDouble(json["total_payments"]),
      lastPayment: json["last_payment"] != null &&
              json["last_payment"].toString().isNotEmpty
          ? DateTime.tryParse(json["last_payment"].toString())
          : null,
      joinedDate: json["joined_date"] != null &&
              json["joined_date"].toString().isNotEmpty
          ? DateTime.tryParse(json["joined_date"].toString()) ?? DateTime.now()
          : DateTime.now(),
      rating: parseDouble(json["rating"]),
      tripsCompleted: parseInt(json["trips_completed"]),
      totalDebt: parseDouble(json["total_debt"]),
      unpaidDays: parseInt(json["unpaid_days"]),
      dueDates: (json["due_dates"] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      hasCompletedAgreement: json["has_completed_agreement"] == true ||
          json["agreement_status"] == "completed" ||
          json["agreement_status"] == "active",
      agreementStatus: json["agreement_status"]?.toString(),
      branchId: (json["branch_id"] as num?)?.toInt(),
    );
  }
  final String id;
  final String name;
  final String email;
  final String phone;
  final String licenseNumber;
  final String? vehicleNumber;
  final String? vehicleType;
  final String status;
  final double totalPayments;
  final DateTime? lastPayment;
  final DateTime joinedDate;
  final double rating;
  final int tripsCompleted;
  // Debt summary (optional; present on payments/debts lists)
  final double totalDebt;
  final int unpaidDays;
  final List<String> dueDates; // ordered oldest->newest when provided
  // Agreement completion status
  final bool hasCompletedAgreement;
  final String?
      agreementStatus; // null, 'pending', 'completed', 'active', 'terminated'

  /// The branch (yard, garage) this driver belongs to, or null.
  final int? branchId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        "id": id,
        "name": name,
        "email": email,
        "phone": phone,
        "license_number": licenseNumber,
        "vehicle_number": vehicleNumber,
        "vehicle_type": vehicleType,
        "status": status,
        "total_payments": totalPayments,
        "last_payment": lastPayment?.toIso8601String(),
        "joined_date": joinedDate.toIso8601String(),
        "rating": rating,
        "trips_completed": tripsCompleted,
        "total_debt": totalDebt,
        "unpaid_days": unpaidDays,
        "due_dates": dueDates,
        "has_completed_agreement": hasCompletedAgreement,
        "agreement_status": agreementStatus,
        "branch_id": branchId,
      };

  Driver copyWith({
    final String? id,
    final String? name,
    final String? email,
    final String? phone,
    final String? licenseNumber,
    final String? vehicleNumber,
    final String? vehicleType,
    final String? status,
    final double? totalPayments,
    final DateTime? lastPayment,
    final DateTime? joinedDate,
    final double? rating,
    final int? tripsCompleted,
    final double? totalDebt,
    final int? unpaidDays,
    final List<String>? dueDates,
    final bool? hasCompletedAgreement,
    final String? agreementStatus,
    final int? branchId,
  }) =>
      Driver(
        id: id ?? this.id,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        licenseNumber: licenseNumber ?? this.licenseNumber,
        vehicleNumber: vehicleNumber ?? this.vehicleNumber,
        vehicleType: vehicleType ?? this.vehicleType,
        status: status ?? this.status,
        totalPayments: totalPayments ?? this.totalPayments,
        lastPayment: lastPayment ?? this.lastPayment,
        joinedDate: joinedDate ?? this.joinedDate,
        rating: rating ?? this.rating,
        tripsCompleted: tripsCompleted ?? this.tripsCompleted,
        totalDebt: totalDebt ?? this.totalDebt,
        unpaidDays: unpaidDays ?? this.unpaidDays,
        dueDates: dueDates ?? this.dueDates,
        hasCompletedAgreement:
            hasCompletedAgreement ?? this.hasCompletedAgreement,
        agreementStatus: agreementStatus ?? this.agreementStatus,
        branchId: branchId ?? this.branchId,
      );

  @override
  String toString() =>
      "Driver(id: $id, name: $name, email: $email, status: $status)";

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Driver && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
