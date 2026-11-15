import { CartLine, PriceTier, Product, SellingUnit, activeUnits, isWeighed } from './till.models';

/**
 * The till's arithmetic, kept apart from the screen so it can be tested to the shilling. It follows the mobile app's
 * InventoryProvider exactly (unitPriceFor, _lineTax, cartTotal), so a sale rung up here and on the phone is the same sale.
 */

export interface PriceContext {
  /** The price level in use: what the cashier picked, else the business's own. */
  tier: 'retail' | 'wholesale';
  /** False for a depot, which prices by product: the product's own price for its own unit. */
  usesPriceLevels: boolean;
  customerId?: number | null;
}

const isBase = (u: SellingUnit | null | undefined): boolean => !u || u.isBase;

/**
 * The price of ONE [unit] of [product]: a customer's special price, else the level's price, else the other level's, else (a unit with
 * no price yet) the base price times what the unit holds.
 */
export function unitPriceFor(product: Product, unit: SellingUnit | null, ctx: PriceContext): number {
  if (!ctx.usesPriceLevels && isBase(unit)) return product.sellingPrice;

  if (unit) {
    const other: PriceTier = ctx.tier === 'wholesale' ? 'retail' : 'wholesale';
    const find = (tier: PriceTier, customerId?: number) =>
      unit.prices.find((p) => p.tier === tier && (customerId === undefined ? true : p.customerId === customerId))?.price;
    const own =
      (ctx.customerId != null ? find('special', ctx.customerId) : undefined) ?? find(ctx.tier) ?? find(other);
    if (own !== undefined) return own;
  }
  return product.sellingPrice * (isBase(unit) ? 1 : (unit as SellingUnit).factor);
}

/** The unit a product is rung up in when the cashier has not chosen: its own base unit, except goods by weight or volume, which start on the biggest unit. */
export function defaultUnitFor(product: Product): SellingUnit | null {
  if (!isWeighed(product)) return null;
  const biggest = [...activeUnits(product)].sort((a, b) => b.factor - a.factor)[0];
  return !biggest || biggest.isBase ? null : biggest;
}

export function lineKey(productId: number, unitId: number | null, option: string | null): string {
  return `${productId}:${unitId ?? 0}${option ? ':' + option : ''}`;
}

export const lineTotal = (l: CartLine): number => l.qty * l.unitPrice;

/** The VAT on one line (prices include VAT: the share inside the price; otherwise: added on top), to the cent. */
export function lineTax(l: CartLine, pricesIncludeVat: boolean): number {
  const rate = l.taxPercent ?? 0;
  if (rate <= 0) return 0;
  const base = lineTotal(l);
  const tax = pricesIncludeVat ? (base * rate) / (100 + rate) : (base * rate) / 100;
  return Math.round(tax * 100) / 100;
}

/** What leaves the stock for a line: whole base units. */
export const baseQty = (l: CartLine): number => l.qty * (l.unitFactor < 1 ? 1 : l.unitFactor);

/** What the line earns: its price less the cost of the base units that leave. */
export const lineProfit = (l: CartLine): number => lineTotal(l) - l.unitCost * baseQty(l);

export interface Totals {
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
  profit: number;
}

/** The sale's figures. A discount is never more than the lines; when prices already include VAT the total is just the lines less the discount. */
export function totalsOf(lines: CartLine[], discount: number, pricesIncludeVat: boolean): Totals {
  const subtotal = lines.reduce((s, l) => s + lineTotal(l), 0);
  const off = Math.min(Math.max(discount, 0), subtotal);
  const tax = lines.reduce((s, l) => s + l.taxAmount, 0);
  return { subtotal, discount: off, tax, total: subtotal - off + (pricesIncludeVat ? 0 : tax), profit: lines.reduce((s, l) => s + lineProfit(l), 0) };
}
