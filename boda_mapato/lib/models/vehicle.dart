import "package:flutter/foundation.dart";

@immutable
class Vehicle {
  const Vehicle({
    required this.id,
    required this.name,
    required this.type,
    required this.plateNumber,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.driverId,
    this.driverName,
    this.driverEmail,
    this.driverPhone,
    this.branchId,
  });

  factory Vehicle.fromJson(final Map<String, dynamic> json) => Vehicle(
        id: json["id"] as String,
        name: json["name"] as String,
        type: json["type"] as String,
        plateNumber: json["plate_number"] as String,
        description: json["description"] as String?,
        isActive: json["is_active"] as bool? ?? true,
        branchId: (json["branch_id"] as num?)?.toInt(),
        driverId: (json["driver"] as Map<String, dynamic>?)?["id"] as String?,
        driverName:
            (json["driver"] as Map<String, dynamic>?)?["name"] as String?,
        driverEmail:
            (json["driver"] as Map<String, dynamic>?)?["email"] as String?,
        driverPhone:
            (json["driver"] as Map<String, dynamic>?)?["phone"] as String?,
        createdAt: DateTime.parse(json["created_at"] as String),
        updatedAt: DateTime.parse(json["updated_at"] as String),
      );
  final String id;
  final String name;
  final String type;
  final String plateNumber;
  final String? description;
  final bool isActive;
  final String? driverId;
  final String? driverName;
  final String? driverEmail;
  final String? driverPhone;

  /// The branch (yard, garage) this vehicle belongs to, or null.
  final int? branchId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        "id": id,
        "name": name,
        "type": type,
        "plate_number": plateNumber,
        "description": description,
        "is_active": isActive,
        "driver_id": driverId,
        "driver_name": driverName,
        "driver_email": driverEmail,
        "driver_phone": driverPhone,
        "branch_id": branchId,
        "created_at": createdAt.toIso8601String(),
        "updated_at": updatedAt.toIso8601String(),
      };

  Vehicle copyWith({
    final String? id,
    final String? name,
    final String? type,
    final String? plateNumber,
    final String? description,
    final bool? isActive,
    final String? driverId,
    final String? driverName,
    final String? driverEmail,
    final String? driverPhone,
    final int? branchId,
    final DateTime? createdAt,
    final DateTime? updatedAt,
  }) =>
      Vehicle(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        plateNumber: plateNumber ?? this.plateNumber,
        description: description ?? this.description,
        isActive: isActive ?? this.isActive,
        driverId: driverId ?? this.driverId,
        driverName: driverName ?? this.driverName,
        driverEmail: driverEmail ?? this.driverEmail,
        driverPhone: driverPhone ?? this.driverPhone,
        branchId: branchId ?? this.branchId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  String toString() => "Vehicle(id: $id, name: $name, type: $type, "
      "plateNumber: $plateNumber, isActive: $isActive, "
      "driverName: $driverName)";

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Vehicle && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
