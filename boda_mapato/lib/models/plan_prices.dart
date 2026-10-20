/// The plans that are sold, how many services each covers, and what each costs.
///
///   basic    one service
///   standard two services
///   premium  three services, of the owner's choice (there are four: Transport, Rental, Inventory, Salon)
///
/// The prices are set by the super admin (Settings -> Plans & Prices) and read by the registration form before anybody
/// has an account. `trial` and `free` are not sold: they have no price and no limit.
library;

/// The plans that can be bought, smallest first.
const List<String> kSellablePlans = <String>['basic', 'standard', 'premium'];

/// How many services each plan covers. The server sends the same numbers; this is what is used before it has answered.
const Map<String, int> kPlanServices = <String, int>{'basic': 1, 'standard': 2, 'premium': 3};

/// The lengths of time a plan can be paid for, in months.
const List<int> kPricePeriods = <int>[1, 3, 6, 12];

/// One plan: the services it covers and its price for each length of time (null: no price set yet).
class PlanOffer {
  const PlanOffer({required this.plan, required this.servicesIncluded, this.prices = const <int, double?>{}});

  factory PlanOffer.fromJson(final Map<String, dynamic> json) {
    final Map<int, double?> prices = <int, double?>{};
    final Object? list = json['prices'];
    if (list is List) {
      for (final Object? row in list) {
        if (row is Map) {
          final int? months = (row['months'] as num?)?.toInt();
          if (months != null) prices[months] = (row['amount'] as num?)?.toDouble();
        }
      }
    }
    return PlanOffer(
      plan: (json['plan'] ?? '').toString(),
      servicesIncluded: (json['services_included'] as num?)?.toInt() ?? kPlanServices[(json['plan'] ?? '').toString()] ?? 0,
      prices: prices,
    );
  }

  final String plan;
  final int servicesIncluded;
  final Map<int, double?> prices;

  double? priceFor(final int months) => prices[months];

  bool get hasPrice => prices.values.any((final double? p) => p != null);
}

/// Every plan with its prices, as the server last said.
class PlanCatalog {
  const PlanCatalog({
    required this.offers,
    this.periods = kPricePeriods,
    this.currency = 'TZS',
    this.trialDays = 30,
    this.totalServices = 4,
    this.configured = false,
    this.updatedAt,
  });

  factory PlanCatalog.fromJson(final Map<String, dynamic> json) {
    final List<PlanOffer> offers = json['plans'] is List
        ? (json['plans'] as List).whereType<Map>().map((final Map m) => PlanOffer.fromJson(Map<String, dynamic>.from(m))).toList()
        : <PlanOffer>[];
    offers.sort((final PlanOffer a, final PlanOffer b) => a.servicesIncluded.compareTo(b.servicesIncluded));
    return PlanCatalog(
      offers: offers.isEmpty ? fallback.offers : offers,
      periods: json['periods'] is List ? (json['periods'] as List).map((final Object? e) => (e as num).toInt()).toList() : kPricePeriods,
      currency: (json['currency'] ?? 'TZS').toString(),
      trialDays: (json['trial_days'] as num?)?.toInt() ?? 30,
      totalServices: (json['total_services'] as num?)?.toInt() ?? 4,
      configured: json['configured'] == true,
      updatedAt: json['updated_at'] is String ? DateTime.tryParse(json['updated_at'] as String)?.toLocal() : null,
    );
  }

  /// What is known before the server has answered (or when it cannot be reached): the plans and what they cover,
  /// with no prices.
  static const PlanCatalog fallback = PlanCatalog(offers: <PlanOffer>[
    PlanOffer(plan: 'basic', servicesIncluded: 1),
    PlanOffer(plan: 'standard', servicesIncluded: 2),
    PlanOffer(plan: 'premium', servicesIncluded: 3),
  ]);

  final List<PlanOffer> offers;
  final List<int> periods;
  final String currency;
  final int trialDays;
  final int totalServices;

  /// Has the super admin set at least one price?
  final bool configured;
  final DateTime? updatedAt;

  PlanOffer? offer(final String plan) {
    for (final PlanOffer o in offers) {
      if (o.plan == plan) return o;
    }
    return null;
  }

  /// How many services a plan covers; null for a plan that is not sold (trial, free), which has no limit.
  int? servicesIncluded(final String plan) => offer(plan)?.servicesIncluded ?? kPlanServices[plan];

  /// Is a business with [serviceCount] services within [plan]?
  bool covers(final String plan, final int serviceCount) {
    final int? included = servicesIncluded(plan);
    return included == null || serviceCount <= included;
  }

  /// The smallest plan that covers [serviceCount] services (the biggest when it is more than any covers).
  String planFor(final int serviceCount) {
    for (final PlanOffer o in offers) {
      if (serviceCount <= o.servicesIncluded) return o.plan;
    }
    return offers.isEmpty ? 'premium' : offers.last.plan;
  }

  /// What [plan] costs for [months], or null when no price is set.
  double? priceFor(final String plan, final int months) => offer(plan)?.priceFor(months);
}
