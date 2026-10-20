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

  bool get isVariant => variantLabel != null && variantLabel!.isNotEmpty;
  bool get isWeighed => measure == 'weight' || measure == 'volume';

  bool get isWholesale => priceTier == 'wholesale';

  double get totalCostPrice => costPrice * quantity;
  double get totalSellingPrice => sellingPrice * quantity;
  double get totalExpectedProfit => (sellingPrice - costPrice) * quantity;
}
