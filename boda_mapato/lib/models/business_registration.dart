/// A business owner's self-registration, as the super admin sees it, plus the
/// request the owner sends when registering.
library;

/// The services a business can be given. Same keys the backend uses.
const List<String> kBusinessServices = <String>['inventory', 'rental', 'transport', 'salon'];

/// What the owner fills in on the registration form.
class BusinessRegistrationRequest {
  const BusinessRegistrationRequest({
    required this.name,
    required this.businessName,
    required this.email,
    required this.phoneNumber,
    required this.password,
    required this.passwordConfirmation,
    required this.requestedServices,
    this.requestedPlan,
    this.requestedMonths,
    this.inventoryType,
    this.region,
    this.district,
    this.address,
    this.notes,
  });

  final String name;
  final String businessName;
  final String email;
  final String phoneNumber;
  final String password;
  final String passwordConfirmation;
  final List<String> requestedServices;

  /// The package they chose (basic = one service, standard = two, premium = up to three, of the owner's choice) and for how many months.
  final String? requestedPlan;
  final int? requestedMonths;

  /// What kind of stock business this is (retail, wholesale, mixed, depot): asked when `inventory` is among
  /// the requested services, because it decides how the product page and the till behave.
  final String? inventoryType;
  final String? region;
  final String? district;
  final String? address;
  final String? notes;

  Map<String, dynamic> toJson() {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    return <String, dynamic>{
      'name': name.trim(),
      'business_name': businessName.trim(),
      'email': email.trim(),
      'phone_number': phoneNumber.trim(),
      'password': password,
      'password_confirmation': passwordConfirmation,
      'requested_services': requestedServices,
      if (requestedPlan != null) 'requested_plan': requestedPlan,
      if (requestedMonths != null) 'requested_months': requestedMonths,
      if (requestedServices.contains('inventory') && clean(inventoryType) != null) 'inventory_type': clean(inventoryType),
      if (clean(region) != null) 'region': clean(region),
      if (clean(district) != null) 'district': clean(district),
      if (clean(address) != null) 'address': clean(address),
      if (clean(notes) != null) 'notes': clean(notes),
    };
  }
}

/// One registration waiting for (or already given) a super admin's decision.
class BusinessRegistration {
  const BusinessRegistration({
    required this.id,
    required this.status,
    required this.businessName,
    required this.requestedServices,
    required this.assignedServices,
    required this.ownerName,
    required this.ownerEmail,
    required this.ownerPhone,
    this.ownerPhoneVerified = false,
    this.requestedPlan,
    this.requestedMonths,
    this.requestedPrice,
    this.inventoryType,
    this.region,
    this.district,
    this.address,
    this.idNumber,
    this.notes,
    this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
  });

  factory BusinessRegistration.fromJson(final Map<String, dynamic> json) {
    final Map<String, dynamic> user = json['user'] is Map
        ? Map<String, dynamic>.from(json['user'] as Map)
        : <String, dynamic>{};
    return BusinessRegistration(
      id: (json['id'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString(),
      businessName: (json['business_name'] ?? '').toString(),
      requestedServices: _strings(json['requested_services']),
      assignedServices: _strings(json['assigned_services']),
      ownerName: (user['name'] ?? '').toString(),
      ownerEmail: (user['email'] ?? '').toString(),
      ownerPhone: (user['phone_number'] ?? '').toString(),
      ownerPhoneVerified: user['phone_verified'] == true,
      requestedPlan: json['requested_plan'] as String?,
      requestedMonths: (json['requested_months'] as num?)?.toInt(),
      requestedPrice: (json['requested_price'] as num?)?.toDouble(),
      inventoryType: json['inventory_type'] as String?,
      region: json['region'] as String?,
      district: json['district'] as String?,
      address: json['address'] as String?,
      idNumber: json['id_number'] as String?,
      notes: json['notes'] as String?,
      submittedAt: _date(json['submitted_at']),
      reviewedAt: _date(json['reviewed_at']),
      reviewedBy: json['reviewed_by'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
    );
  }

  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';

  final String id;
  final String status;
  final String businessName;
  final List<String> requestedServices;
  final List<String> assignedServices;
  final String ownerName;
  final String ownerEmail;
  final String ownerPhone;

  /// Did the applicant confirm this number with the code that was texted to it?
  final bool ownerPhoneVerified;

  /// The package the applicant chose, for how many months, and what the super admin has priced it at (null: no price set).
  final String? requestedPlan;
  final int? requestedMonths;
  final double? requestedPrice;

  /// The kind of stock business the applicant said they run (null when they did not ask for inventory).
  final String? inventoryType;
  final String? region;
  final String? district;
  final String? address;
  final String? idNumber;
  final String? notes;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectionReason;

  bool get isPending => status == pending;

  /// "Kinondoni, Dar es Salaam" -- whatever location parts were given.
  String get location => <String?>[address, district, region]
      .where((String? p) => p != null && p.trim().isNotEmpty)
      .join(', ');

  static List<String> _strings(final Object? v) =>
      v is List ? v.map((e) => e.toString()).toList() : <String>[];

  static DateTime? _date(final Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}
