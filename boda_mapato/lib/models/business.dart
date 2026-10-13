/// A business: who it is (what receipts and text messages say about it) and what plan it is on.
library;

/// The plans a super admin can choose from, in the order they are shown. The server owns the list
/// (config/billing.php) and sends it with the businesses list; this is the fallback.
const List<String> kBusinessPlans = <String>['trial', 'free', 'basic', 'standard', 'premium'];

/// A plan's name as people read it. Unknown plans (the server may add some) show as they are.
String businessPlanLabel(final String plan, {required final bool sw}) => switch (plan) {
      'trial' => sw ? 'Jaribio' : 'Trial',
      'free' => sw ? 'Bure' : 'Free',
      'basic' => sw ? 'Msingi' : 'Basic',
      'standard' => sw ? 'Kawaida' : 'Standard',
      'premium' => 'Premium',
      _ => plan,
    };

/// Plan, paid-until date and what the server does about it.
class BusinessBilling {
  const BusinessBilling({
    required this.plan,
    this.validUntil,
    this.daysLeft,
    this.isExpired = false,
    this.inGrace = false,
    this.enforced = false,
    this.blocked = false,
  });

  factory BusinessBilling.fromJson(final Map<String, dynamic> json) => BusinessBilling(
        plan: (json['plan'] ?? 'free').toString(),
        validUntil: json['valid_until'] is String ? DateTime.tryParse(json['valid_until'] as String)?.toLocal() : null,
        daysLeft: (json['days_left'] as num?)?.toInt(),
        isExpired: json['is_expired'] == true,
        inGrace: json['in_grace'] == true,
        enforced: json['enforced'] == true,
        blocked: json['blocked'] == true,
      );

  final String plan;

  /// The business works through the end of this day. Null: it never expires.
  final DateTime? validUntil;

  /// Whole days left (negative once passed); null when it never expires.
  final int? daysLeft;
  final bool isExpired;

  /// Expired, but still inside the grace period.
  final bool inGrace;

  /// Is the server actually locking expired businesses out (BILLING_ENFORCE)?
  final bool enforced;
  final bool blocked;

  bool get neverExpires => validUntil == null;

  /// Worth telling the owner about: expired, or running out within [soonDays] days.
  bool needsAttention({final int soonDays = 7}) => isExpired || (daysLeft != null && daysLeft! <= soonDays);
}

/// Who owns a business, as the super admin sees it.
class BusinessOwner {
  const BusinessOwner({required this.id, required this.name, required this.email, required this.phoneNumber, required this.isActive});

  factory BusinessOwner.fromJson(final Map<String, dynamic> json) => BusinessOwner(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        phoneNumber: (json['phone_number'] ?? '').toString(),
        isActive: json['is_active'] != false,
      );

  final String id;
  final String name;
  final String email;
  final String phoneNumber;
  final bool isActive;
}

class Business {
  const Business({
    required this.id,
    required this.name,
    required this.billing,
    this.ownerId = '',
    this.address = '',
    this.tin = '',
    this.phone = '',
    this.email = '',
    this.logoUrl,
    this.inventoryType,
    this.owner,
    this.services = const <String>[],
    this.staffCount = 0,
  });

  factory Business.fromJson(final Map<String, dynamic> json) => Business(
        id: (json['id'] ?? '').toString(),
        ownerId: (json['owner_id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        address: (json['address'] ?? '').toString(),
        tin: (json['tin'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        logoUrl: (json['logo_url'] is String && (json['logo_url'] as String).isNotEmpty) ? json['logo_url'] as String : null,
        inventoryType: (json['inventory_type'] is String && (json['inventory_type'] as String).isNotEmpty) ? json['inventory_type'] as String : null,
        billing: BusinessBilling.fromJson(
          json['billing'] is Map ? Map<String, dynamic>.from(json['billing'] as Map) : <String, dynamic>{},
        ),
        owner: json['owner'] is Map ? BusinessOwner.fromJson(Map<String, dynamic>.from(json['owner'] as Map)) : null,
        services: json['services'] is List ? (json['services'] as List).map((e) => e.toString()).toList() : const <String>[],
        staffCount: (json['staff_count'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String ownerId;
  final String name;
  final String address;
  final String tin;
  final String phone;
  final String email;
  final String? logoUrl;

  /// The kind of stock business (retail, wholesale, mixed, depot); null until one is chosen, which works like a depot.
  final String? inventoryType;
  final BusinessBilling billing;

  /// Only in the super admin's list.
  final BusinessOwner? owner;
  final List<String> services;
  final int staffCount;
}
