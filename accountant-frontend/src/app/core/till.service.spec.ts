import { TestBed } from '@angular/core/testing';

import { configure, user } from '../testing';
import { CapabilitiesService } from './capabilities.service';
import { Product, SellingUnit } from './till.models';
import { TillService } from './till.service';

const unit = (over: Partial<SellingUnit> = {}): SellingUnit => ({ id: 5, name: 'Crate', factor: 24, isBase: false, active: true, prices: [], ...over });
const product = (over: Partial<Product> = {}): Product => ({
  id: 1, name: 'Soda', sku: 'S1', barcode: '', category: '', sellingPrice: 1000, costPrice: 600, quantity: 100, unit: 'pcs', taxPercent: null,
  isService: false, measure: 'count', active: true, priceOptions: [], staffIds: [], units: [], ...over,
});

function setup(service: 'inventory' | 'salon' = 'inventory', settings: Record<string, string> = { sale_tier: 'product', prices_include_vat: '1' }) {
  const h = configure({ services: [service] });
  const caps = TestBed.inject(CapabilitiesService);
  caps.settings.set(settings);
  const till = TestBed.inject(TillService);
  TestBed.tick();
  h.http.match(() => true); // the settings request is not under test
  return { h, till, caps };
}

describe('the cart', () => {
  it('adding the same product again is one line with two of it', () => {
    const { till } = setup();
    till.add(product());
    till.add(product());
    expect(till.lines()).toHaveLength(1);
    expect(till.lines()[0].qty).toBe(2);
    expect(till.totals().total).toBe(2000);
  });

  it('a product in another unit is its own line, priced for that unit', () => {
    const { till } = setup();
    till.add(product());
    till.add(product(), { unit: unit() });
    expect(till.lines()).toHaveLength(2);
    expect(till.lines()[1].unitPrice).toBe(24000);
    expect(till.leaving(1)).toBe(1 + 24);
  });

  it('changing the unit merges into the line that already has that unit', () => {
    const { till } = setup();
    const crate = unit();
    const p = product({ units: [crate] });
    till.add(p, { unit: crate });
    const b = till.add(p);
    till.changeUnit(b.key, p, crate);
    expect(till.lines()).toHaveLength(1);
    expect(till.lines()[0].qty).toBe(2);
  });

  it('a quantity is a whole number of at least one', () => {
    const { till } = setup();
    const l = till.add(product());
    till.setQty(l.key, 0);
    expect(till.lines()[0].qty).toBe(1);
    till.setQty(l.key, 3.9);
    expect(till.lines()[0].qty).toBe(3);
  });

  it('VAT inside the prices does not add to the total; VAT on top does', () => {
    const inside = setup('inventory', { sale_tier: 'product', prices_include_vat: '1' });
    inside.till.add(product({ sellingPrice: 11800, taxPercent: 18 }));
    expect(inside.till.totals()).toMatchObject({ tax: 1800, total: 11800 });
    TestBed.resetTestingModule();
    const onTop = setup('inventory', { sale_tier: 'product', prices_include_vat: '0' });
    onTop.till.add(product({ sellingPrice: 10000, taxPercent: 18 }));
    expect(onTop.till.totals()).toMatchObject({ tax: 1800, total: 11800 });
  });

  it('a price option is its own line at its own price', () => {
    const { till } = setup();
    till.add(product({ priceOptions: [{ label: 'Long', price: 60000 }] }), { option: { label: 'Long', price: 60000 } });
    expect(till.lines()[0]).toMatchObject({ name: 'Soda (Long)', unitPrice: 60000 });
  });
});

describe('the sale the server is sent', () => {
  it('an empty cart is refused', () => {
    expect(setup().till.buildSale().error).toBe('empty');
  });

  it('paid in full: one payment for the whole total, status paid', () => {
    const { till } = setup();
    till.add(product());
    till.setQty(till.lines()[0].key, 3);
    const { payload } = till.buildSale();
    expect(payload).toMatchObject({ payment_status: 'paid', total: 3000, paid_total: 3000, due_date: null });
    expect((payload!['payments'] as { amount: number; method: string }[])[0]).toMatchObject({ amount: 3000, method: 'cash' });
    expect((payload!['items'] as Record<string, unknown>[])[0]).toMatchObject({ product_id: 1, quantity: 3, unit_price: 1000, unit_cost_snapshot: 600 });
  });

  it('on credit or part paid needs a customer', () => {
    const { till } = setup();
    till.add(product());
    till.mode.set('debt');
    expect(till.buildSale().error).toBe('customer_required');
    till.mode.set('partial');
    expect(till.buildSale().error).toBe('customer_required');
  });

  it('part paid: the part is the payment, the rest is owed, and a due date is set', () => {
    const { till } = setup();
    till.add(product());
    till.setQty(till.lines()[0].key, 5);
    till.customer.set({ id: 7, name: 'Neema', phone: '0712' });
    till.mode.set('partial');
    till.paid.set(2000);
    const { payload } = till.buildSale();
    expect(payload).toMatchObject({ customer_id: 7, payment_status: 'partial', paid_total: 2000, total: 5000 });
    expect(payload!['due_date']).not.toBeNull();
  });

  it('part paid with nothing paid is a debt; paying everything is paid; more than the total is capped', () => {
    const { till } = setup();
    till.add(product());
    till.customer.set({ id: 7, name: 'Neema', phone: '' });
    till.mode.set('partial');
    till.paid.set(0);
    expect(till.buildSale().payload).toMatchObject({ payment_status: 'debt', paid_total: 0 });
    till.paid.set(99999);
    expect(till.buildSale().payload).toMatchObject({ payment_status: 'paid', paid_total: 1000 });
  });

  it('a walk-in who is named sends the name, not a customer', () => {
    const { till } = setup();
    till.add(product());
    till.manualName.set('Mzee Juma');
    expect(till.buildSale().payload).toMatchObject({ customer_id: null, customer_name_override: 'Mzee Juma' });
  });

  it('crates ride along when chosen', () => {
    const { till } = setup();
    till.add(product());
    till.crate.set({ typeId: 3, qty: 2, direction: 'issued' });
    expect(till.buildSale().payload).toMatchObject({ crate_type_id: 3, crate_qty: 2, crate_direction: 'issued' });
  });
});

describe('the salon', () => {
  const cut = () => product({ id: 9, name: 'Haircut', isService: true, sellingPrice: 10000 });

  it('every service needs the stylist who served the client', () => {
    const { till } = setup('salon');
    const l = till.add(cut());
    expect(till.buildSale().error).toBe('stylist_required');
    till.setStaff(l.key, { id: '4', name: 'Rehema' });
    expect((till.buildSale().payload!['items'] as Record<string, unknown>[])[0]).toMatchObject({ staff_id: '4' });
  });

  it('the stylist chosen once is offered again for the next service', () => {
    const { till } = setup('salon');
    const a = till.add(cut());
    till.setStaff(a.key, { id: '4', name: 'Rehema' });
    const b = till.add(product({ id: 10, name: 'Braids', isService: true }));
    expect(b.staffId).toBe('4');
  });

  it('a discount needs a reason, and never takes off more than the lines', () => {
    const { till } = setup('salon');
    const l = till.add(cut());
    till.setStaff(l.key, { id: '4', name: 'Rehema' });
    till.discount.set(2000);
    expect(till.buildSale().error).toBe('reason_required');
    till.discountReason.set('Regular client');
    expect(till.buildSale().payload).toMatchObject({ discount: 2000, total: 8000, discount_reason: 'Regular client' });
    till.discount.set(99999);
    expect(till.totals().total).toBe(0);
  });

  it('a voucher and points count as the reason; points never exceed what is left', () => {
    const { till } = setup('salon');
    const l = till.add(cut());
    till.setStaff(l.key, { id: '4', name: 'Rehema' });
    till.voucher.set({ code: 'WELCOME', off: 3000 });
    till.pointValue.set(100);
    till.pointsUsed.set(50);
    expect(till.pointsOff()).toBe(5000);
    expect(till.buildSale().payload).toMatchObject({ discount: 8000, voucher_code: 'WELCOME', redeem_points: 50, total: 2000 });
  });

  it('a shop has no discount at all', () => {
    const { till } = setup('inventory');
    till.add(product());
    till.discount.set(500);
    expect(till.totals().total).toBe(1000);
  });

  it('the goods used by a service go with its line', () => {
    const { till } = setup('salon');
    const l = till.add(cut());
    till.setStaff(l.key, { id: '4', name: 'Rehema' });
    till.setMaterials(l.key, [{ productId: 2, name: 'Gel', qty: 2 }, { productId: 3, name: 'Oil', qty: 0 }]);
    expect((till.buildSale().payload!['items'] as Record<string, unknown>[])[0]['materials']).toEqual([{ product_id: 2, quantity: 2 }]);
  });
});

describe('putting a sale aside and bringing it back', () => {
  it('a cart kept by this app comes back as it was', () => {
    const { till } = setup();
    till.add(product());
    const kept = till.snapshot();
    till.clear();
    till.restore(kept as unknown[], { id: 3, name: 'Neema', phone: '' });
    expect(till.lines()).toHaveLength(1);
    expect(till.customer()?.id).toBe(3);
  });

  it('a cart kept by the phone is rebuilt from what it says', () => {
    const { till } = setup();
    till.restore([{ product_id: 4, name: 'Rice', qty: 2, unit_price: 3000, unit_cost_snapshot: 2000 }, { name: 'broken' }], null);
    expect(till.lines()).toHaveLength(1);
    expect(till.lines()[0]).toMatchObject({ productId: 4, qty: 2, unitPrice: 3000 });
  });
});

it('a different person starts with an empty cart', () => {
  const { h, till } = setup();
  till.add(product());
  h.auth.user.set(user({ id: '2' }));
  TestBed.tick();
  expect(till.lines()).toHaveLength(0);
});
