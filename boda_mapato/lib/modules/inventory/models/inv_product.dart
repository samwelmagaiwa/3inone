/// One price of a service that comes at several: "Long" for 60,000.
class PriceOption {
  const PriceOption({required this.label, required this.price});

  final String label;
  final double price;

  Map<String, dynamic> toJson() => <String, dynamic>{'label': label, 'price': price};
}

class InvProduct {
  InvProduct({
    required this.id,
    required this.name,
    required this.sku,
    required this.category,
    required this.costPrice,
    required this.sellingPrice,
    required this.unit,
    required this.quantity,
    required this.minStock,
    required this.status,
    required this.barcode,
    required this.createdBy,
    this.description,
    this.categoryId,
    this.brandId,
    this.categoryName,
    this.brandName,
    this.priceTier = 'retail',
    this.unitFactor = 1,
    this.taxPercent,
    this.familyId,
    this.variantLabel,
    this.measure = 'count',
    this.isService = false,
    this.durationMinutes,
    this.rebookAfterWeeks,
    this.commissionPercent,
    this.commissionFixed,
    this.packageSessions,
    this.packageServiceId,
    this.packageValidDays,
    this.staffIds = const <String>[],
    this.priceOptions = const <PriceOption>[],
  });

  final int id;
  String name;
  String sku;
  String category;
  double costPrice;
  double sellingPrice;
  String unit;
  // How many of `unit` the cost/selling price cover, e.g. 5 for "per 5 KG".
  int unitFactor;
  int quantity;
  int minStock;
  String status; // active/inactive
  String barcode;
  final int createdBy;
  String? description;
  int? categoryId;
  int? brandId;
  String? categoryName;
  String? brandName;
  String priceTier; // 'retail' or 'wholesale'

  /// This product's VAT rate. Null = the business's default; 0 = exempt.
  double? taxPercent;

  /// Sizes / colours of one product share the id of the first one.
  int? familyId;

  /// "M / Red": what tells a size or colour apart (null for a plain product).
  String? variantLabel;

  /// What the base unit counts: 'count' (pieces), 'weight' (grams) or 'volume' (millilitres).
  String measure;

  /// Salon: a SERVICE (a braiding, a manicure) has no shelf: no stock to count, to run out of or to be low on.
  bool isService;

  /// How long a service takes, in minutes (null = not said).
  int? durationMinutes;

  /// After how many weeks the client is reminded to come back for this service (null = the salon's own number).
  int? rebookAfterWeeks;

  /// Salon: the percent of a service's price the stylist who did it earns (null = none).
  double? commissionPercent;

  /// Salon: a fixed amount the stylist earns each time it is done (wins over the percent when both are given).
  double? commissionFixed;

  /// Salon: a package is a service that, once bought, gives the client [packageSessions] visits of [packageServiceId]
  /// (valid for [packageValidDays] days, or for ever when null).
  int? packageSessions;
  int? packageServiceId;
  int? packageValidDays;

  bool get isPackage => isService && (packageSessions ?? 0) > 0;

  /// Salon: who may do this service (account ids); empty = anyone.
  List<String> staffIds;

  /// Salon: the same service at other prices (short, medium or long hair); empty = one price.
  List<PriceOption> priceOptions;

  bool get isVariant => variantLabel != null && variantLabel!.isNotEmpty;
  bool get isWeighed => measure == 'weight' || measure == 'volume';

  bool get isWholesale => priceTier == 'wholesale';

  double get totalCostPrice => costPrice * quantity;
  double get totalSellingPrice => sellingPrice * quantity;
  double get totalExpectedProfit => (sellingPrice - costPrice) * quantity;
}
