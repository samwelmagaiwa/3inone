import 'package:flutter/foundation.dart';

/// The kinds of stock business an owner can say they run, in the order they are offered.
/// (The same keys as config/inventory_types.php on the server.)
const List<String> kInventoryTypes = <String>['retail', 'wholesale', 'mixed', 'depot'];

/// A kind of business as people read it.
String inventoryTypeLabel(String type, {required bool sw}) => switch (type) {
      'retail' => sw ? 'Rejareja (Retail)' : 'Retail',
      'wholesale' => sw ? 'Jumla (Wholesale)' : 'Wholesale',
      'mixed' => sw ? 'Jumla na Rejareja' : 'Wholesale and retail',
      'depot' => sw ? 'Ghala / Depo ya vinywaji' : 'Depot (drinks, crates)',
      _ => type,
    };

/// One line saying what a kind of business is for, shown under the choice.
String inventoryTypeHint(String type, {required bool sw}) => switch (type) {
      'retail' => sw ? 'Unauza kipande kimoja kimoja: duka, famasi, nguo.' : 'You sell single items: a shop, pharmacy, clothes.',
      'wholesale' => sw ? 'Unauza kwa katoni, magunia au bei ya jumla.' : 'You sell by the carton, sack or at a wholesale price.',
      'mixed' => sw ? 'Unauza kwa jumla na kwa rejareja.' : 'You sell both wholesale and retail.',
      'depot' => sw ? 'Unauza vinywaji kwa makreti na kufuatilia makreti matupu.' : 'You sell drinks by the crate and track empty crates.',
      _ => '',
    };

/// What the business's inventory is set up to do. Read from the inventory settings the server sends, with
/// the depot's behaviour as the fallback for anything missing: that is what inventory was before kinds
/// existed, so a business that has not chosen one -- or an older server -- behaves exactly as it always did.
@immutable
class InvCapabilities {
  const InvCapabilities({
    this.inventoryType = 'depot',
    this.useCrates = true,
    this.saleTier = 'product',
    this.pricesIncludeVat = true,
    this.defaultTaxPercent = 0,
  });

  factory InvCapabilities.fromSettings(Map<String, String> s) => InvCapabilities(
        inventoryType: kInventoryTypes.contains(s['inventory_type']) ? s['inventory_type']! : 'depot',
        useCrates: (s['use_crates'] ?? '1') != '0',
        saleTier: const <String>['retail', 'wholesale'].contains(s['sale_tier']) ? s['sale_tier']! : 'product',
        pricesIncludeVat: (s['prices_include_vat'] ?? '1') != '0',
        defaultTaxPercent: double.tryParse(s['tax_percent'] ?? '') ?? 0,
      );

  /// retail | wholesale | mixed | depot
  final String inventoryType;

  /// Returnable packaging: the crates tab, deposits and the "empties" step at checkout.
  final bool useCrates;

  /// Which price the till uses: `product` (the product's own price, the depot way), `retail` or `wholesale`.
  final String saleTier;

  /// Do the prices already contain VAT? (Only matters for products that carry a VAT rate.)
  final bool pricesIncludeVat;

  /// The VAT rate of a product that has none of its own.
  final double defaultTaxPercent;

  bool get isDepot => inventoryType == 'depot';
  bool get isRetail => inventoryType == 'retail';
  bool get isWholesale => inventoryType == 'wholesale';
  bool get isMixed => inventoryType == 'mixed';

  /// Does the till pick a unit's retail / wholesale price (everyone but the depot)?
  bool get usesPriceLevels => saleTier != 'product';

  /// Should the product page offer a wholesale price next to the retail one?
  bool get offersWholesalePrice => isWholesale || isMixed;

  /// The tier the till starts on: the business's own, or retail for a depot (which prices by product).
  String get startingTier => saleTier == 'wholesale' ? 'wholesale' : 'retail';

  @override
  bool operator ==(Object other) =>
      other is InvCapabilities &&
      other.inventoryType == inventoryType &&
      other.useCrates == useCrates &&
      other.saleTier == saleTier &&
      other.pricesIncludeVat == pricesIncludeVat &&
      other.defaultTaxPercent == defaultTaxPercent;

  @override
  int get hashCode => Object.hash(inventoryType, useCrates, saleTier, pricesIncludeVat, defaultTaxPercent);
}
