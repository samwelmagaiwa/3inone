import { Injectable, computed, effect, inject, signal, untracked } from '@angular/core';

import { AuthService } from './auth.service';
import { CapabilitiesService } from './capabilities.service';
import { baseQty, defaultUnitFor, lineKey, lineTax, totalsOf, unitPriceFor } from './till-math';
import { CartLine, Customer, PriceOption, Product, SellingUnit } from './till.models';

export type PayMode = 'cash' | 'partial' | 'debt';

/** The ways a client may pay: cash, the mobile money networks, the bank (the same list as the mobile app). */
export const PAYMENT_CHANNELS = ['cash', 'mpesa', 'mixx', 'airtel_money', 'halopesa', 'bank_transfer'] as const;

export interface SalePayloadResult {
  payload?: Record<string, unknown>;
  /** What is missing, as a key the screen turns into words. */
  error?: 'empty' | 'customer_required' | 'stylist_required' | 'reason_required';
}

/**
 * The sale being rung up: the cart, the customer, how it is paid, and the sale the server is sent. It lives for the whole sign-in, so
 * moving to another page and back does not lose the cart. All arithmetic is in till-math.ts (the mobile app's rules).
 */
@Injectable({ providedIn: 'root' })
export class TillService {
  private readonly auth = inject(AuthService);
  private readonly caps = inject(CapabilitiesService);

  readonly lines = signal<CartLine[]>([]);
  readonly customer = signal<Customer | null>(null);
  readonly manualName = signal('');
  readonly manualPhone = signal('');
  readonly mode = signal<PayMode>('cash');
  readonly channel = signal<string>('cash'); // how a full payment is made
  readonly partialChannel = signal<string>('cash');
  readonly paid = signal(0); // a part payment
  readonly dueDays = signal(7);
  readonly tierOverride = signal<'retail' | 'wholesale' | null>(null);

  // salon
  readonly discount = signal(0);
  readonly discountReason = signal('');
  readonly voucher = signal<{ code: string; off: number }>({ code: '', off: 0 });
  readonly pointsUsed = signal(0);
  readonly pointValue = signal(0);
  /** The stylist chosen for the line before is offered again: a client is usually served by one person. */
  readonly defaultStaff = signal<{ id: string; name: string } | null>(null);

  // depot crates
  readonly crate = signal<{ typeId: number | null; qty: number; direction: 'issued' | 'returned' } | null>(null);

  readonly salon = computed(() => this.auth.service() === 'salon');
  readonly tier = computed(() => this.tierOverride() ?? this.caps.startingTier());

  readonly subtotal = computed(() => this.lines().reduce((s, l) => s + l.qty * l.unitPrice, 0));
  readonly voucherOff = computed(() => (this.salon() ? Math.min(this.voucher().off, this.subtotal()) : 0));
  readonly pointsOff = computed(() => {
    if (!this.salon() || this.pointsUsed() <= 0) return 0;
    const room = Math.max(0, this.subtotal() - this.voucherOff());
    return Math.min(this.pointsUsed() * this.pointValue(), room);
  });
  /** Everything taken off the sale: the typed discount, the voucher and the points (never more than the lines). The shop has only none. */
  readonly totalDiscount = computed(() => {
    if (!this.salon()) return 0;
    const typed = Math.min(this.discount(), this.subtotal());
    return Math.min(typed + this.voucherOff() + this.pointsOff(), this.subtotal());
  });
  readonly totals = computed(() => totalsOf(this.lines(), this.totalDiscount(), this.caps.pricesIncludeVat()));
  readonly count = computed(() => this.lines().reduce((s, l) => s + l.qty, 0));

  constructor() {
    // a different business or service has different goods and prices: start from an empty cart
    effect(() => {
      this.auth.user();
      this.auth.service();
      untracked(() => this.clear());
    });
  }

  private priceCtx() {
    return { tier: this.tier(), usesPriceLevels: this.caps.usesPriceLevels(), customerId: this.customer()?.id ?? null };
  }

  private retax(l: CartLine): CartLine {
    return { ...l, taxAmount: lineTax(l, this.caps.pricesIncludeVat()) };
  }

  private replace(key: string, fn: (l: CartLine) => CartLine): void {
    this.lines.update((ls) => ls.map((l) => (l.key === key ? fn(l) : l)));
  }

  // ------------------------------------------------------------------ the cart
  /** Put one of a product in the cart, in [unit] (null = the product's own base unit). The same product in another unit or at another price option is its own line. */
  add(product: Product, opts: { unit?: SellingUnit | null; option?: PriceOption | null } = {}): CartLine {
    const chosen = opts.unit ?? defaultUnitFor(product);
    const unit = chosen && !chosen.isBase ? chosen : null;
    const option = opts.option ?? null;
    const key = lineKey(product.id, unit?.id ?? null, option?.label ?? null);

    const existing = this.lines().find((l) => l.key === key);
    if (existing) {
      this.replace(key, (l) => this.retax({ ...l, qty: l.qty + 1 }));
      return this.lines().find((l) => l.key === key)!;
    }
    const staff = product.isService ? this.defaultStaff() : null;
    const line = this.retax({
      key,
      productId: product.id,
      name: option ? `${product.name} (${option.label})` : product.name,
      optionLabel: option?.label ?? null,
      qty: 1,
      unitPrice: option ? option.price : unitPriceFor(product, unit, this.priceCtx()),
      unitCost: product.isService ? 0 : product.costPrice,
      unitId: unit?.id ?? null,
      unitName: unit?.name ?? null,
      unitFactor: unit?.factor ?? 1,
      taxPercent: product.taxPercent ?? (this.caps.defaultTaxPercent() || null),
      taxAmount: 0,
      isService: product.isService,
      staffId: staff?.id ?? null,
      staffName: staff?.name ?? null,
      materials: null,
      packageId: null,
      priceBeforePackage: null,
    });
    this.lines.update((ls) => [...ls, line]);
    return line;
  }

  /** Write the price of one unit of this line (business prices are not always fixed). A free package visit keeps its price. */
  setPrice(key: string, price: number): void {
    this.replace(key, (l) => (l.packageId !== null ? l : this.retax({ ...l, unitPrice: Math.max(0, price), priceWritten: true })));
  }

  /** What the catalogue says one unit of this line costs now, or null when the goods are not in the list any more. */
  listPriceOf(l: CartLine, products: Product[]): number | null {
    const p = products.find((x) => x.id === l.productId);
    if (!p) return null;
    const option = l.optionLabel ? p.priceOptions.find((o) => o.label === l.optionLabel) : null;
    if (option) return option.price;
    const unit = p.units.find((u) => u.id === l.unitId) ?? null;

    return unitPriceFor(p, unit, this.priceCtx());
  }

  /** Take the catalogue price back for a line whose price was written. */
  useListPrice(key: string, products: Product[]): void {
    const l = this.lines().find((x) => x.key === key);
    const list = l ? this.listPriceOf(l, products) : null;
    if (list === null) return;
    this.replace(key, (x) => this.retax({ ...x, unitPrice: list, priceWritten: false }));
  }

  setQty(key: string, qty: number): void {
    this.replace(key, (l) => this.retax({ ...l, qty: Math.max(1, Math.floor(qty) || 1) }));
  }

  remove(key: string): void {
    this.lines.update((ls) => ls.filter((l) => l.key !== key));
  }

  setStaff(key: string, staff: { id: string; name: string } | null): void {
    this.replace(key, (l) => ({ ...l, staffId: staff?.id ?? null, staffName: staff?.name ?? null }));
    if (staff) this.defaultStaff.set(staff);
  }

  setMaterials(key: string, materials: CartLine['materials']): void {
    this.replace(key, (l) => ({ ...l, materials }));
  }

  /** Take this line from one of the client's packages (it becomes free), or put it back to its price. */
  setPackage(key: string, packageId: number | null): void {
    this.replace(key, (l) => {
      if (packageId !== null && l.packageId === null) return this.retax({ ...l, priceBeforePackage: l.unitPrice, unitPrice: 0, packageId });
      if (packageId === null && l.packageId !== null) return this.retax({ ...l, unitPrice: l.priceBeforePackage ?? l.unitPrice, priceBeforePackage: null, packageId: null });
      return { ...l, packageId };
    });
  }

  /** Sell this line in another unit (a kg instead of a g, a bottle instead of a crate), repriced; it merges into the line that already has that unit. */
  changeUnit(key: string, product: Product, unit: SellingUnit | null): void {
    const target = unit && !unit.isBase ? unit : null;
    const old = this.lines().find((l) => l.key === key);
    if (!old) return;
    const newKey = lineKey(old.productId, target?.id ?? null, old.optionLabel);
    if (newKey === key) return;
    const moved = this.retax({ ...old, key: newKey, unitId: target?.id ?? null, unitName: target?.name ?? null, unitFactor: target?.factor ?? 1, unitPrice: unitPriceFor(product, target, this.priceCtx()), priceWritten: false });
    const twin = this.lines().find((l) => l.key === newKey);
    this.lines.update((ls) => {
      const rest = ls.filter((l) => l.key !== key && l.key !== newKey);
      return [...rest, twin ? this.retax({ ...twin, qty: twin.qty + old.qty }) : moved];
    });
  }

  /** Prices follow who is buying (a customer's special price) and the price level, for lines that are not a chosen option or a package. */
  reprice(products: Product[]): void {
    this.lines.update((ls) =>
      ls.map((l) => {
        if (l.optionLabel || l.packageId !== null || l.priceWritten) return l;
        const p = products.find((x) => x.id === l.productId);
        if (!p) return l;
        const unit = p.units.find((u) => u.id === l.unitId) ?? null;
        return this.retax({ ...l, unitPrice: unitPriceFor(p, unit, this.priceCtx()) });
      }),
    );
  }

  clear(): void {
    this.lines.set([]);
    this.customer.set(null);
    this.manualName.set('');
    this.manualPhone.set('');
    this.mode.set('cash');
    this.channel.set('cash');
    this.partialChannel.set('cash');
    this.paid.set(0);
    this.dueDays.set(7);
    this.discount.set(0);
    this.discountReason.set('');
    this.voucher.set({ code: '', off: 0 });
    this.pointsUsed.set(0);
    this.crate.set(null);
  }

  // ------------------------------------------------------------------ the sale
  /** Does a service line still need its stylist? A salon names who served the client on every service. */
  missingStylist(): CartLine | null {
    return this.salon() ? (this.lines().find((l) => l.isService && !l.staffId) ?? null) : null;
  }

  /** The sale as the server takes it (the same fields as the mobile app sends), or what is missing. */
  buildSale(): SalePayloadResult {
    const lines = this.lines();
    if (!lines.length) return { error: 'empty' };
    const customer = this.customer();
    if ((this.mode() === 'debt' || this.mode() === 'partial') && !customer) return { error: 'customer_required' };
    if (this.missingStylist()) return { error: 'stylist_required' };
    const t = this.totals();
    if (this.salon() && t.discount > 0 && !this.discountReason().trim() && !this.voucher().code && this.pointsOff() <= 0) return { error: 'reason_required' };

    const now = new Date().toISOString();
    let paidTotal = 0;
    let status: 'paid' | 'partial' | 'debt' = 'paid';
    let payments: { amount: number; method: string; reference: null; paid_at: string }[] = [];
    if (this.mode() === 'cash') {
      paidTotal = t.total;
      payments = [{ amount: t.total, method: this.salon() ? this.channel() : this.channel(), reference: null, paid_at: now }];
    } else if (this.mode() === 'partial') {
      paidTotal = Math.min(Math.max(this.paid(), 0), t.total);
      status = paidTotal <= 0 ? 'debt' : paidTotal < t.total ? 'partial' : 'paid';
      if (paidTotal > 0) payments = [{ amount: paidTotal, method: this.partialChannel(), reference: null, paid_at: now }];
    } else {
      status = 'debt';
    }

    const reasonParts = [this.voucher().code ? `Voucher ${this.voucher().code}` : '', this.pointsOff() > 0 ? 'Loyalty points' : ''].filter(Boolean);
    const crate = this.crate();
    const payload: Record<string, unknown> = {
      customer_id: customer?.id ?? null,
      ...(!customer && this.manualName().trim() ? { customer_name_override: this.manualName().trim() } : {}),
      customer_phone: customer ? customer.phone || null : this.manualPhone().trim() || null,
      payment_status: status,
      subtotal: t.subtotal,
      discount: t.discount,
      ...(t.discount > 0 ? { discount_reason: this.discountReason().trim() || reasonParts.join(' + ') } : {}),
      ...(this.voucher().code ? { voucher_code: this.voucher().code } : {}),
      ...(this.pointsUsed() > 0 ? { redeem_points: this.pointsUsed() } : {}),
      tax: t.tax,
      total: t.total,
      paid_total: paidTotal,
      due_date: status === 'paid' ? null : new Date(Date.now() + this.dueDays() * 86_400_000).toISOString(),
      items: lines.map((l) => ({
        product_id: l.productId,
        quantity: l.qty,
        ...(l.unitId !== null ? { unit_id: l.unitId } : {}),
        unit_price: l.unitPrice,
        unit_cost_snapshot: l.unitCost,
        ...(l.taxPercent !== null ? { tax_percent: l.taxPercent } : {}),
        ...(l.staffId ? { staff_id: l.staffId } : {}),
        ...(l.packageId !== null ? { package_id: l.packageId } : {}),
        ...(l.isService && l.materials !== null ? { materials: l.materials.filter((m) => m.qty > 0).map((m) => ({ product_id: m.productId, quantity: m.qty })) } : {}),
      })),
      ...(payments.length ? { payments } : {}),
      ...(crate?.typeId && crate.qty > 0 ? { crate_type_id: crate.typeId, crate_qty: crate.qty, crate_direction: crate.direction } : {}),
    };
    return { payload };
  }

  // ------------------------------------------------------------------ parking
  /** The cart as it is kept while parked: everything needed to bring it back without asking the server for the products again. */
  snapshot(): CartLine[] {
    return this.lines();
  }

  /** Bring a parked cart back. Lines kept by this app are read as they are; lines kept by the phone are rebuilt from what they say. */
  restore(raw: unknown[], customer: Customer | null): void {
    const lines: CartLine[] = [];
    for (const r of raw) {
      const j = r as Record<string, unknown>;
      const l = 'unitPrice' in j ? (j as unknown as CartLine) : this.fromPhone(j);
      if (l) lines.push(this.retax(l));
    }
    this.lines.set(lines);
    this.customer.set(customer);
  }

  private fromPhone(j: Record<string, unknown>): CartLine | null {
    const productId = Number(j['product_id'] ?? j['productId'] ?? 0);
    if (!productId) return null;
    const unitId = j['unit_id'] == null ? null : Number(j['unit_id']);
    return {
      key: lineKey(productId, unitId, null),
      productId,
      name: String(j['name'] ?? j['product_name'] ?? `#${productId}`),
      optionLabel: null,
      qty: Math.max(1, Math.round(Number(j['qty'] ?? j['quantity'] ?? 1))),
      unitPrice: Number(j['unit_price'] ?? j['unitPrice'] ?? 0),
      unitCost: Number(j['unit_cost_snapshot'] ?? j['unit_cost'] ?? 0),
      unitId,
      unitName: j['unit_name'] == null ? null : String(j['unit_name']),
      unitFactor: Number(j['unit_factor'] ?? 1) || 1,
      taxPercent: j['tax_percent'] == null ? null : Number(j['tax_percent']),
      taxAmount: 0,
      isService: j['is_service'] === true || j['is_service'] === 1,
      staffId: j['staff_id'] == null ? null : String(j['staff_id']),
      staffName: j['staff_name'] == null ? null : String(j['staff_name']),
      materials: null,
      packageId: null,
      priceBeforePackage: null,
    };
  }

  /** How many base units leave the shelf for a product across the cart (a product may be in several lines). */
  leaving(productId: number): number {
    return this.lines()
      .filter((l) => l.productId === productId && !l.isService)
      .reduce((s, l) => s + baseQty(l), 0);
  }
}
