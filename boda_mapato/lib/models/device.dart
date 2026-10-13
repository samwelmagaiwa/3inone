import "package:flutter/foundation.dart";
import '../services/localization_service.dart';

enum DeviceType {
  bajaji,
  pikipiki,
  gari,
}

extension DeviceTypeExtension on DeviceType {
  String get name {
    switch (this) {
      case DeviceType.bajaji:
        return LocalizationService.instance.translate('vehicle_type_bajaji');
      case DeviceType.pikipiki:
        return LocalizationService.instance.translate('vehicle_type_pikipiki');
      case DeviceType.gari:
        return LocalizationService.instance.translate('vehicle_type_gari');
    }
  }

  String get icon {
    switch (this) {
      case DeviceType.bajaji:
        return "🛺";
      case DeviceType.pikipiki:
        return "🏍️";
      case DeviceType.gari:
        return "🚗";
    }
  }
}

@immutable
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.type,
    required this.plateNumber,
    required this.driverId,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
    this.description,
  });

  factory Device.fromJson(final Map<String, dynamic> json) => Device(
        id: (json["id"] as String?) ?? "",
        name: (json["name"] as String?) ?? "",
        type: _parseDeviceType(json["type"] as String?),
        plateNumber: (json["plate_number"] as String?) ?? "",
        driverId: (json["driver_id"] as String?) ?? "",
        createdAt: DateTime.parse(
          (json["created_at"] as String?) ?? DateTime.now().toIso8601String(),
        ),
        updatedAt: DateTime.parse(
          (json["updated_at"] as String?) ?? DateTime.now().toIso8601String(),
        ),
        isActive: (json["is_active"] as bool?) ?? true,
        description: json["description"] as String?,
      );
  final String id;
  final String name;
  final DeviceType type;
  final String plateNumber;
  final String driverId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final String? description;

  static DeviceType _parseDeviceType(final String? type) {
    switch (type?.toLowerCase()) {
      case "bajaji":
        return DeviceType.bajaji;
      case "pikipiki":
        return DeviceType.pikipiki;
      case "gari":
        return DeviceType.gari;
      default:
        return DeviceType.pikipiki;
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        "id": id,
        "name": name,
        "type": type.name.toLowerCase(),
        "plate_number": plateNumber,
        "driver_id": driverId,
        "created_at": createdAt.toIso8601String(),
        "updated_at": updatedAt.toIso8601String(),
        "is_active": isActive,
        "description": description,
      };

  Device copyWith({
    final String? id,
    final String? name,
    final DeviceType? type,
    final String? plateNumber,
    final String? driverId,
    final DateTime? createdAt,
    final DateTime? updatedAt,
    final bool? isActive,
    final String? description,
  }) =>
      Device(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        plateNumber: plateNumber ?? this.plateNumber,
        driverId: driverId ?? this.driverId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isActive: isActive ?? this.isActive,
        description: description ?? this.description,
      );

  @override
  String toString() => "Device(id: $id, name: $name, type: ${type.name}, "
      "plateNumber: $plateNumber, driverId: $driverId, isActive: $isActive)";

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Device && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
