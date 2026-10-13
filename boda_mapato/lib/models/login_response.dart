import '../config/navigation_config.dart';
import 'business.dart';

class LoginResponse {
  LoginResponse({
    required this.status,
    required this.message,
    this.data,
  });

  factory LoginResponse.fromJson(final Map<String, dynamic> json) =>
      LoginResponse(
        status: (json["status"] as String?) ?? "",
        message: (json["message"] as String?) ?? "",
        data: json["data"] != null
            ? LoginData.fromJson(
                json["data"] as Map<String, dynamic>,
              )
            : null,
      );
  final String status;
  final String message;
  final LoginData? data;

  bool get isSuccess => status == "success";
}

class LoginData {
  LoginData({
    this.userId,
    this.token,
    this.user,
    this.role,
    this.dashboardRoute,
    this.expiresInMinutes,
  });

  factory LoginData.fromJson(final Map<String, dynamic> json) => LoginData(
        userId: json["user_id"] as String?,
        token: json["token"] as String?,
        user: json["user"] != null
            ? UserData.fromJson(
                json["user"] as Map<String, dynamic>,
              )
            : null,
        role: json["role"] as String?,
        dashboardRoute: json["dashboard_route"] as String?,
        expiresInMinutes: json["expires_in_minutes"] as int?,
      );
  final String? userId;
  final String? token;
  final UserData? user;
  final String? role;
  final String? dashboardRoute;
  final int? expiresInMinutes;
}

class UserData {
  UserData({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    this.phoneNumber,
    this.deviceId,
    this.lastLoginAt,
    this.driver,
    this.assignedDevice,
    this.avatarUrl,
    this.permissions,
    this.fullAccess = false,
    this.mustChangePassword = false,
    this.serviceTypes = const <String>[],
    this.business,
  });

  factory UserData.fromJson(final Map<String, dynamic> json) => UserData(
        id: (json["id"] as String?) ?? "",
        name: (json["name"] as String?) ?? "",
        email: (json["email"] as String?) ?? "",
        phoneNumber: json["phone_number"] as String?,
        role: (json["role"] as String?) ?? "driver",
        isActive: (json["is_active"] as bool?) ?? true,
        deviceId: json["device_id"] as String?,
        lastLoginAt: json["last_login_at"] != null
            ? DateTime.parse(json["last_login_at"] as String)
            : null,
        driver: json["driver"] != null
            ? DriverData.fromJson(
                json["driver"] as Map<String, dynamic>,
              )
            : null,
        assignedDevice: json["assigned_device"] != null
            ? DeviceData.fromJson(
                json["assigned_device"] as Map<String, dynamic>,
              )
            : null,
        // Flexible avatar/profile image keys from backend
        avatarUrl: _pickAvatarUrl(json),
        permissions: _pickPermissions(json),
        fullAccess: (json["full_access"] as bool?) ?? false,
        mustChangePassword: (json["must_change_password"] as bool?) ?? false,
        serviceTypes: _pickServiceTypes(json),
        business: json["business"] is Map
            ? Business.fromJson(Map<String, dynamic>.from(json["business"] as Map))
            : null,
      );
  final String id;
  final String name;
  final String email;
  final String? phoneNumber;
  final String role;
  final bool isActive;
  final String? deviceId;
  final DateTime? lastLoginAt;
  final DriverData? driver;
  final DeviceData? assignedDevice;
  final String? avatarUrl;
  /// Per-user explicit grants stored in users.permissions (DB column).
  /// May be null when admin hasn't assigned any extras yet.
  final List<String>? permissions;
  final bool fullAccess;
  /// True while the account still uses an admin-issued default password.
  final bool mustChangePassword;
  /// Services (rental/transport/inventory) this account is bound to.
  /// Empty means an admin hasn't assigned one yet.
  final List<String> serviceTypes;

  /// The business this person works for (name, address, TIN, logo) and its plan.
  /// Null for a super admin, who belongs to no business.
  final Business? business;

  /// Owners head a business: they edit its profile; everyone else only reads it.
  bool get isBusinessOwner => role == "admin" || role == "administrator" || role == "landlord";

  bool hasPermission(String permission) {
    if (isSuperAdmin || fullAccess) return true;
    if (role == 'tenant' && (permission == 'view_maintenance' || permission == 'view_vendors' || permission == 'tenant_self_service')) return true;
    if (role == 'vendor' && (permission == 'vendor_access' || permission == 'view_maintenance')) return true;
    if (permissions != null && permissions!.contains(permission)) return true;
    // Most accounts are never given an explicit permissions array (it's
    // null in the DB by default), so without this fallback every
    // permission-gated nav item silently disappears for a plain admin --
    // fall back to the role's default set instead of treating "no array"
    // as "no permissions at all".
    return DefaultPermissions.getPermissionsForRole(role).contains(permission);
  }

  bool get isSuperAdmin => role == "super_admin";
  bool get isAdmin => role == "admin";
  bool get isDriver => role == "driver";
  bool get isVendor => role == "vendor";
  bool get canManageDrivers => isSuperAdmin || isAdmin;

  /// Prefer server-resolved effective_permissions (role defaults ∪ explicit
  /// grants) when present; fall back to the raw explicit-only permissions list.
  static List<String>? _pickPermissions(Map<String, dynamic> json) {
    for (final String key in ['effective_permissions', 'permissions']) {
      final dynamic raw = json[key];
      if (raw is List && raw.isNotEmpty) {
        final List<String> list =
            raw.map((e) => e.toString()).where((s) => s != '__all__').toList();
        if (list.isNotEmpty) return list;
      }
    }
    return null;
  }

  static List<String> _pickServiceTypes(Map<String, dynamic> json) {
    // `services` is the eager-loaded relation (login / /auth/user);
    // `service_types` is the flat list some admin endpoints return.
    final dynamic services =
        json['services'] ?? json['service_types'] ?? json['serviceTypes'];
    if (services is List) {
      return services
          .map((dynamic e) =>
              e is Map ? (e['service_type']?.toString() ?? '') : e.toString())
          .where((String s) => s.isNotEmpty)
          .toSet()
          .toList();
    }
    // Legacy single-value fallback.
    final String? single = json['service_type'] as String?;
    return single != null && single.isNotEmpty ? <String>[single] : <String>[];
  }

  static String? _pickAvatarUrl(Map<String, dynamic> json) {
    final List<String> keys = <String>[
      'avatar_url',
      'avatar',
      'profile_image_url',
      'profile_image',
      'profile_photo_url',
      'photo_url',
      'image_url',
    ];
    for (final String k in keys) {
      final dynamic v = json[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}

class DriverData {
  DriverData({
    required this.id,
    required this.userId,
    required this.licenseNumber,
    required this.licenseExpiry,
    required this.isActive,
    required this.rating,
    required this.totalTrips,
    required this.totalEarnings,
    this.address,
    this.emergencyContact,
  });

  factory DriverData.fromJson(final Map<String, dynamic> json) => DriverData(
        id: (json["id"] as String?) ?? "",
        userId: (json["user_id"] as String?) ?? "",
        licenseNumber: (json["license_number"] as String?) ?? "",
        licenseExpiry: DateTime.parse(
          (json["license_expiry"] as String?) ??
              DateTime.now().toIso8601String(),
        ),
        address: json["address"] as String?,
        emergencyContact: json["emergency_contact"] as String?,
        isActive: (json["is_active"] as bool?) ?? true,
        rating: _toDouble(json["rating"]),
        totalTrips: _toInt(json["total_trips"]),
        totalEarnings: _toDouble(json["total_earnings"]),
      );

  static double _toDouble(v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final String cleaned = v.replaceAll(RegExp(r'[^0-9\.-]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0;
  }

  static int _toInt(v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  final String id;
  final String userId;
  final String licenseNumber;
  final DateTime licenseExpiry;
  final String? address;
  final String? emergencyContact;
  final bool isActive;
  final double rating;
  final int totalTrips;
  final double totalEarnings;
}

class DeviceData {
  DeviceData({
    required this.id,
    required this.name,
    required this.type,
    required this.plateNumber,
    required this.isActive,
    this.description,
  });

  factory DeviceData.fromJson(final Map<String, dynamic> json) => DeviceData(
        id: (json["id"] as String?) ?? "",
        name: (json["name"] as String?) ?? "",
        type: (json["type"] as String?) ?? "",
        plateNumber: (json["plate_number"] as String?) ?? "",
        description: json["description"] as String?,
        isActive: (json["is_active"] as bool?) ?? true,
      );
  final String id;
  final String name;
  final String type;
  final String plateNumber;
  final String? description;
  final bool isActive;
}
