/**
 * What the till works with: products and the ways they are sold, customers, and the lines of the cart. Parsed from the same JSON
 * the mobile app reads (InvProduct / InvProductUnit), with its rules: a value may arrive as a string ("15000.00"), a flag as 1/true.
 */
export type PriceTier = 'retail' | 'wholesale' | 'special';

export interface UnitPrice {
  tier: PriceTier;
  price: number;
  customerId: number | null;
}

/** A way a product is sold: bottle, pack, crate. `factor` is how many base units it holds, so stock stays in one unit. */
export interface SellingUnit {
  id: number;
  name: string;
  factor: number;
  isBase: boolean;
  active: boolean;
  prices: UnitPrice[];
}

export interface PriceOption {
  label: string;
  price: number;
}

export interface Product {
  id: number;
  name: string;
  sku: string;
  barcode: string;
  category: string;
  sellingPrice: number;
  costPrice: number;
  quantity: number;
  unit: string;
  taxPercent: number | null;
  isService: boolean;
  measure: 'count' | 'weight' | 'volume' | string;
  active: boolean;
  priceOptions: PriceOption[];
  staffIds: string[];
  units: SellingUnit[];
}

export interface Customer {
  id: number;
  name: string;
  phone: string;
}

/** One line of the cart. `qty` counts the selling unit; `unitCost` is the cost of ONE BASE unit. */
export interface CartLine {
  key: string;
  productId: number;
  name: string;
  optionLabel: string | null;
  qty: number;
  unitPrice: number;
  unitCost: number;
  unitId: number | null;
  unitName: string | null;
  unitFactor: number;
  taxPercent: number | null;
  taxAmount: number;
  isService: boolean;
  staffId: string | null;
  staffName: string | null;
  /** Salon: the goods this visit used. null = the service's usual goods. */
  materials: { productId: number; name: string; qty: number }[] | null;
  /** Salon: the client's package this line is taken from (the line is then free), and the price it had. */
  packageId: number | null;
  priceBeforePackage: number | null;
}

const num = (v: unknown, fallback = 0): number => {
  if (typeof v === 'number') return Number.isFinite(v) ? v : fallback;
  const n = Number.parseFloat(String(v ?? ''));
  return Number.isFinite(n) ? n : fallback;
};
const flag = (v: unknown): boolean => v === true || v === 1 || v === '1';

export function parseUnit(j: Record<string, unknown>): SellingUnit {
  const prices = Array.isArray(j['prices']) ? (j['prices'] as Record<string, unknown>[]) : [];
  return {
    id: num(j['id']),
    name: String(j['name'] ?? ''),
    factor: Math.max(1, Math.round(num(j['factor'], 1))),
    isBase: flag(j['is_base']),
    active: String(j['status'] ?? 'active') === 'active',
    prices: prices.map((p) => ({
      tier: (['retail', 'wholesale', 'special'].includes(String(p['tier'])) ? String(p['tier']) : 'retail') as PriceTier,
      price: num(p['price']),
      customerId: p['customer_id'] == null ? null : num(p['customer_id']),
    })),
  };
}

export function parseProduct(j: Record<string, unknown>): Product {
  const options = Array.isArray(j['price_options']) ? (j['price_options'] as Record<string, unknown>[]) : [];
  const units = Array.isArray(j['units']) ? (j['units'] as Record<string, unknown>[]) : [];
  return {
    id: num(j['id'] ?? j['product_id']),
    name: String(j['name'] ?? j['product_name'] ?? ''),
    sku: String(j['SKU'] ?? j['sku'] ?? j['code'] ?? ''),
    barcode: String(j['barcode'] ?? j['bar_code'] ?? ''),
    category: String(j['category_name'] ?? j['category'] ?? ''),
    sellingPrice: num(j['selling_price'] ?? j['price']),
    costPrice: num(j['cost_price'] ?? j['cost']),
    quantity: Math.round(num(j['quantity'] ?? j['qty'])),
    unit: String(j['unit'] ?? 'pcs'),
    taxPercent: j['tax_percent'] == null || j['tax_percent'] === '' ? null : num(j['tax_percent']),
    isService: flag(j['is_service']),
    measure: String(j['measure'] ?? 'count'),
    active: String(j['status'] ?? 'active') !== 'inactive',
    priceOptions: options.map((o) => ({ label: String(o['label'] ?? ''), price: num(o['price']) })),
    staffIds: Array.isArray(j['staff_ids']) ? (j['staff_ids'] as unknown[]).map(String) : [],
    units: units.map(parseUnit),
  };
}

export function parseCustomer(j: Record<string, unknown>): Customer {
  return { id: num(j['id'] ?? j['customer_id']), name: String(j['name'] ?? j['customer_name'] ?? ''), phone: String(j['phone'] ?? j['phone_number'] ?? '') };
}

/** The units of a product that can be sold now (the base unit is always among them). */
export function activeUnits(p: Product): SellingUnit[] {
  return p.units.filter((u) => u.active);
}

export function isWeighed(p: Product): boolean {
  return p.measure === 'weight' || p.measure === 'volume';
}
