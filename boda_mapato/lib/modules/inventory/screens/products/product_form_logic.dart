import '../../models/inv_capabilities.dart';

/// Everything the product page has to turn into numbers the server accepts, kept free of widgets so it can
/// be tested on its own.
///
/// The rules it keeps:
///   * stock and every quantity are WHOLE numbers of the smallest unit -- pieces, grams, millilitres. Goods by
///     weight or volume are stocked in grams / millilitres and sold in grams, kilograms, millilitres or litres,
///     so nothing is ever a fraction;
///   * a price is entered per the unit the owner thinks in (a kg, a litre) and stored per base unit as well, to
///     two decimals, with the bigger unit's own price kept exactly.

/// What the base unit counts.
enum ProductMeasure {
  count,
  weight,
  volume;

  String get wire => name;

  static ProductMeasure parse(String? v) => ProductMeasure.values.firstWhere(
        (ProductMeasure m) => m.name == v,
        orElse: () => ProductMeasure.count,
      );

  /// The smallest unit of this kind of goods ('' for counted goods: the owner picks pcs / pack / box ...).
  String get baseUnit => switch (this) {
        ProductMeasure.count => '',
        ProductMeasure.weight => 'g',
        ProductMeasure.volume => 'ml',
      };

  /// The bigger unit people actually quote prices in ('' for counted goods).
  String get bigUnit => switch (this) {
        ProductMeasure.count => '',
        ProductMeasure.weight => 'kg',
        ProductMeasure.volume => 'litre',
      };

  /// How many base units the big unit holds.
  int get bigFactor => this == ProductMeasure.count ? 1 : 1000;
}

/// A price per base unit, from a price per bigger unit (2,200 per kg -> 2.2 per g), to two decimals.
double perBaseUnit(double pricePerBigUnit, int factor) =>
    factor <= 1 ? pricePerBigUnit : (pricePerBigUnit / factor * 100).round() / 100;

/// One extra way to sell a product, as typed.
class UnitInput {
  const UnitInput({required this.name, required this.factor, this.retail, this.wholesale});

  final String name;

  /// How many base units one of it holds (a crate of 24 -> 24).
  final int factor;
  final double? retail;
  final double? wholesale;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name.trim(),
        'factor': factor,
        if (retail != null) 'retail_price': retail,
        if (wholesale != null) 'wholesale_price': wholesale,
      };
}

/// One size / colour, as typed.
class VariantInput {
  const VariantInput({required this.label, this.quantity = 0, this.price, this.barcode});

  final String label;

  /// Whole base units, already converted.
  final int quantity;
  final double? price;
  final String? barcode;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label.trim(),
        'quantity': quantity,
        if (price != null) 'selling_price': price,
        if (barcode != null && barcode!.trim().isNotEmpty) 'barcode': barcode!.trim(),
      };
}

/// What the page sends to create a product: already in the units and tiers the server stores.
class ProductRequest {
  const ProductRequest({
    required this.unit,
    required this.unitFactor,
    required this.measure,
    required this.priceTier,
    required this.costPrice,
    required this.sellingPrice,
    required this.quantity,
    required this.minStock,
    this.otherPrice,
    this.units = const <UnitInput>[],
    this.variants = const <VariantInput>[],
  });

  final String unit;
  final int unitFactor;
  final ProductMeasure measure;

  /// The level (`retail` | `wholesale`) the entered selling price is stored at.
  final String priceTier;
  final double costPrice;
  final double sellingPrice;

  /// The same unit's price at the other level, if one was given.
  final double? otherPrice;
  final int quantity;
  final int minStock;
  final List<UnitInput> units;
  final List<VariantInput> variants;

  List<Map<String, dynamic>> get unitsJson => units.map((UnitInput u) => u.toJson()).toList();
  List<Map<String, dynamic>> get variantsJson => variants.map((VariantInput v) => v.toJson()).toList();
}

/// Turn what was typed into what the server stores.
///
/// [extraUnits] are the "also sold as ..." rows; for goods by weight or volume the bigger unit (kg, litre) is
/// added for you with the prices that were entered per kg / litre.
ProductRequest buildProductRequest({
  required InvCapabilities caps,
  required ProductMeasure measure,
  required bool depotWholesaleMode,
  required String unit,
  required int unitFactor,
  required double cost,
  required double price,
  required int quantity,
  required int minStock,
  double? otherPrice,
  int stockUnitFactor = 1,
  List<UnitInput> extraUnits = const <UnitInput>[],
  List<VariantInput> variants = const <VariantInput>[],
}) {
  // The level the price typed here belongs to. A depot prices by product (its Jumla / Rejareja switch);
  // every other kind of business has a level of its own.
  final String tier = caps.isDepot
      ? (depotWholesaleMode ? 'wholesale' : 'retail')
      : (caps.saleTier == 'wholesale' ? 'wholesale' : 'retail');

  if (measure == ProductMeasure.count) {
    return ProductRequest(
      unit: unit,
      unitFactor: caps.isDepot ? (unitFactor < 1 ? 1 : unitFactor) : 1,
      measure: measure,
      priceTier: tier,
      costPrice: cost,
      sellingPrice: price,
      otherPrice: otherPrice,
      quantity: quantity * stockUnitFactor,
      minStock: minStock * stockUnitFactor,
      units: extraUnits,
      variants: variants,
    );
  }

  // By weight or volume: prices are quoted per kg / litre, stock is counted in g / ml.
  final int big = measure.bigFactor;
  final double? retailPerBig = tier == 'retail' ? price : otherPrice;
  final double? wholesalePerBig = tier == 'wholesale' ? price : otherPrice;

  return ProductRequest(
    unit: measure.baseUnit,
    unitFactor: 1,
    measure: measure,
    priceTier: tier,
    costPrice: perBaseUnit(cost, big),
    sellingPrice: perBaseUnit(price, big),
    otherPrice: otherPrice == null ? null : perBaseUnit(otherPrice, big),
    quantity: quantity * stockUnitFactor,
    minStock: minStock * stockUnitFactor,
    units: <UnitInput>[
      UnitInput(name: measure.bigUnit, factor: big, retail: retailPerBig, wholesale: wholesalePerBig),
      ...extraUnits.where((UnitInput u) => u.name.trim().toLowerCase() != measure.bigUnit),
    ],
    variants: variants,
  );
}

/// Parse a typed whole number ("1,200" is 1200). Anything that is not a whole number -- "2.5", "abc", a
/// negative -- is 0: a quantity is never a fraction, and "2.5" must not quietly become 25.
int wholeNumber(String? text) {
  final int? n = int.tryParse((text ?? '').replaceAll(RegExp(r'[,\s]'), ''));
  return (n == null || n < 0) ? 0 : n;
}

/// Parse a typed price that may carry thousands separators ("22,000" -> 22000).
double? optionalAmount(String? text) {
  final String t = (text ?? '').replaceAll(',', '').trim();
  if (t.isEmpty) return null;
  return double.tryParse(t);
}
