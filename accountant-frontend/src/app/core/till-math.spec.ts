import { baseQty, defaultUnitFor, lineKey, lineProfit, lineTax, lineTotal, totalsOf, unitPriceFor } from './till-math';
import { CartLine, Product, SellingUnit, parseProduct } from './till.models';

const unit = (over: Partial<SellingUnit> = {}): SellingUnit => ({ id: 1, name: 'Crate', factor: 24, isBase: false, active: true, prices: [], ...over });

const product = (over: Partial<Product> = {}): Product => ({
  id: 1, name: 'Soda', sku: 'S1', barcode: '', category: '', sellingPrice: 1000, costPrice: 600, quantity: 100, unit: 'pcs', taxPercent: null,
  isService: false, measure: 'count', active: true, priceOptions: [], staffIds: [], units: [], ...over,
});

const line = (over: Partial<CartLine> = {}): CartLine => ({
  key: '1:0', productId: 1, name: 'Soda', optionLabel: null, qty: 2, unitPrice: 1000, unitCost: 600, unitId: null, unitName: null, unitFactor: 1, taxPercent: null, taxAmount: 0,
  isService: false, staffId: null, staffName: null, materials: null, packageId: null, priceBeforePackage: null, ...over,
});

const retail = { tier: 'retail' as const, usesPriceLevels: true };

describe('the price of one unit', () => {
  it('a depot prices by product: its own price for its own unit', () => {
    expect(unitPriceFor(product(), null, { tier: 'retail', usesPriceLevels: false })).toBe(1000);
  });

  it('uses the level\'s price, else the other level\'s, else the base price times what the unit holds', () => {
    const crate = unit({ prices: [{ tier: 'wholesale', price: 20000, customerId: null }] });
    expect(unitPriceFor(product(), crate, { ...retail, tier: 'wholesale' })).toBe(20000);
    expect(unitPriceFor(product(), crate, retail)).toBe(20000); // no retail price: the other level's
    expect(unitPriceFor(product(), unit(), retail)).toBe(24000); // no price at all: 1000 x 24
    expect(unitPriceFor(product(), unit({ isBase: true, factor: 1 }), retail)).toBe(1000);
  });

  it('a customer\'s special price wins, for that customer only', () => {
    const crate = unit({ prices: [{ tier: 'retail', price: 24000, customerId: null }, { tier: 'special', price: 21000, customerId: 7 }] });
    expect(unitPriceFor(product(), crate, { ...retail, customerId: 7 })).toBe(21000);
    expect(unitPriceFor(product(), crate, { ...retail, customerId: 8 })).toBe(24000);
    expect(unitPriceFor(product(), crate, retail)).toBe(24000);
  });
});

describe('the unit a product starts on', () => {
  it('pieces start on the base unit; goods by weight start on the biggest unit', () => {
    expect(defaultUnitFor(product())).toBeNull();
    const kg = unit({ id: 2, name: 'kg', factor: 1000 });
    const g = unit({ id: 3, name: 'g', factor: 1, isBase: true });
    expect(defaultUnitFor(product({ measure: 'weight', units: [g, kg] }))?.name).toBe('kg');
    expect(defaultUnitFor(product({ measure: 'weight', units: [g] }))).toBeNull();
    expect(defaultUnitFor(product({ measure: 'weight', units: [g, { ...kg, active: false }] }))).toBeNull();
  });

  it('two units or two price options of one product are two lines', () => {
    expect(lineKey(1, null, null)).toBe('1:0');
    expect(lineKey(1, 5, null)).toBe('1:5');
    expect(lineKey(1, null, 'Long')).toBe('1:0:Long');
  });
});

describe('VAT and the total', () => {
  it('prices that include VAT: the share inside the price; otherwise added on top; to the cent', () => {
    expect(lineTax(line({ qty: 1, unitPrice: 11800, taxPercent: 18 }), true)).toBe(1800);
    expect(lineTax(line({ qty: 1, unitPrice: 10000, taxPercent: 18 }), false)).toBe(1800);
    expect(lineTax(line({ qty: 3, unitPrice: 999, taxPercent: 18 }), true)).toBe(457.17);
    expect(lineTax(line({ taxPercent: 0 }), true)).toBe(0);
    expect(lineTax(line({ taxPercent: null }), false)).toBe(0);
  });

  it('with VAT inside the prices the total is the lines less the discount; with VAT on top it is added', () => {
    const lines = [line({ qty: 2, unitPrice: 5000, taxPercent: 18, taxAmount: 1800 })];
    expect(totalsOf(lines, 0, true)).toMatchObject({ subtotal: 10000, tax: 1800, total: 10000 });
    expect(totalsOf(lines, 0, false)).toMatchObject({ subtotal: 10000, tax: 1800, total: 11800 });
    expect(totalsOf(lines, 1000, true).total).toBe(9000);
  });

  it('a discount is never more than the lines, and never negative', () => {
    const lines = [line({ qty: 1, unitPrice: 5000 })];
    expect(totalsOf(lines, 99999, true)).toMatchObject({ discount: 5000, total: 0 });
    expect(totalsOf(lines, -5, true)).toMatchObject({ discount: 0, total: 5000 });
  });

  it('profit is the price less the cost of the base units that leave (a crate of 24)', () => {
    const crate = line({ qty: 2, unitPrice: 24000, unitCost: 600, unitFactor: 24 });
    expect(lineTotal(crate)).toBe(48000);
    expect(baseQty(crate)).toBe(48);
    expect(lineProfit(crate)).toBe(48000 - 600 * 48);
    expect(totalsOf([crate], 0, true).profit).toBe(19200);
  });
});

describe('reading products from the server', () => {
  it('reads strings as numbers, flags as booleans, and the units with their prices', () => {
    const p = parseProduct({
      id: '5', name: 'Cola', sku: 'C-1', selling_price: '1500.00', cost_price: '900.00', quantity: '40', tax_percent: '18', is_service: 0, status: 'active', measure: 'count',
      units: [{ id: 9, name: 'Crate', factor: '24', is_base: 0, status: 'active', prices: [{ tier: 'retail', price: '34000.00', customer_id: null }] }],
      price_options: [{ label: 'Long', price: '60000' }], staff_ids: [3, 4],
    });
    expect(p).toMatchObject({ id: 5, sellingPrice: 1500, costPrice: 900, quantity: 40, taxPercent: 18, isService: false, active: true, staffIds: ['3', '4'] });
    expect(p.units[0]).toMatchObject({ id: 9, factor: 24, isBase: false, active: true });
    expect(p.units[0].prices[0]).toEqual({ tier: 'retail', price: 34000, customerId: null });
    expect(p.priceOptions).toEqual([{ label: 'Long', price: 60000 }]);
  });

  it('a product with no VAT rate of its own has none (the business default is applied by the till)', () => {
    expect(parseProduct({ id: 1, name: 'X' }).taxPercent).toBeNull();
    expect(parseProduct({ id: 1, name: 'X', tax_percent: 0 }).taxPercent).toBe(0);
  });
});
