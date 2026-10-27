import { TestBed } from '@angular/core/testing';

import { byTestId, configure, settle, text, toasts, type } from '../../testing';
import { TillPage } from './till';

const soda = { id: 1, name: 'Soda', selling_price: 1000, cost_price: 600, quantity: 10, status: 'active', is_service: 0 };
const cut = { id: 9, name: 'Haircut', selling_price: 10000, cost_price: 0, quantity: 0, status: 'active', is_service: 1 };

async function open(who = {}, goods: unknown[] = [soda], salon = false, settings: Record<string, string> = {}) {
  const h = configure(salon ? { services: ['salon'], ...who } : who);
  const fixture = TestBed.createComponent(TillPage);
  fixture.detectChanges();
  h.http.match((r) => r.url.endsWith('/inventory/settings')).forEach((r) => r.flush({ data: { sale_tier: 'product', prices_include_vat: '1', ...settings } }));
  h.http.expectOne((r) => r.url.endsWith('/inventory/products')).flush({ data: goods, meta: { last_page: 1 } });
  h.http.match((r) => r.url.endsWith('/crate-types')).forEach((r) => r.flush({ data: [] }));
  if (salon) {
    h.http.match((r) => r.url.endsWith('/salon/staff')).forEach((r) => r.flush({ data: [{ id: '4', name: 'Rehema', role: 'stylist' }, { id: '5', name: 'Zawadi', role: 'stylist' }] }));
    h.http.match((r) => r.url.endsWith('/loyalty/settings')).forEach((r) => r.flush({ data: { on: false, per: 0, value: 0 } }));
  }
  await settle(fixture);
  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

describe('the till', () => {
  it('lists the goods with their stock, and a click puts one in the sale', async () => {
    const { fixture, el } = await open();
    expect(text(byTestId(el, 'good-1')!)).toContain('10 in stock');

    byTestId(el, 'good-1')!.click();
    await settle(fixture);

    expect(byTestId(el, 'line-1')).not.toBeNull();
    expect(text(byTestId(el, 'till-total')!)).toBe('TSH 1,000');
  });

  it('goods can be narrowed by category and brand, and in a salon by services or goods', async () => {
    const { h, fixture, el } = await open({}, [soda], true);
    byTestId(el, 'till-filters-toggle')!.click();
    await settle(fixture);
    h.http.expectOne((r) => r.url.endsWith('/inventory/categories')).flush({ data: [{ id: 3, name: 'Kusuka / Braiding', description: null, status: 'active' }] });
    h.http.expectOne((r) => r.url.endsWith('/inventory/brands')).flush({ data: [{ id: 5, name: 'Darling', description: null, status: 'active' }] });
    await settle(fixture);
    const category = byTestId(el, 'till-filter-category') as HTMLSelectElement;
    expect(Array.from(category.options).map((o) => o.text.trim())).toContain('Braiding');

    category.value = '3';
    category.dispatchEvent(new Event('change', { bubbles: true }));
    await settle(fixture);
    const asked = h.http.expectOne((r) => r.url.endsWith('/inventory/products'));
    expect(asked.request.params.get('category_id')).toBe('3');
    asked.flush({ data: [], meta: { last_page: 1 } });
    await settle(fixture);

    const kind = byTestId(el, 'till-filter-kind') as HTMLSelectElement;
    kind.value = 'service';
    kind.dispatchEvent(new Event('change', { bubbles: true }));
    await settle(fixture);
    const next = h.http.expectOne((r) => r.url.endsWith('/inventory/products'));
    expect(next.request.params.get('is_service')).toBe('1');
    next.flush({ data: [], meta: { last_page: 1 } });
  });

  it('will not sell more than is in stock', async () => {
    const { fixture, el } = await open();
    for (let i = 0; i < 11; i++) byTestId(el, 'good-1')!.click();
    await settle(fixture);
    expect(text(byTestId(el, 'till-total')!)).toBe('TSH 10,000');
    expect(toasts().join(' ')).toContain('Only 10 of Soda left in stock.');
  });

  it('pressing Enter on a code that matches goes straight into the sale', async () => {
    const { h, fixture, el } = await open({}, [{ ...soda, barcode: '12345' }]);
    type(el, '[data-testid=till-search]', '12345');
    (el.querySelector('[data-testid=till-search]') as HTMLInputElement).dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
    await settle(fixture);
    h.http.match((r) => r.url.endsWith('/inventory/products')).forEach((r) => r.flush({ data: [soda], meta: { last_page: 1 } }));
    expect(byTestId(el, 'line-1')).not.toBeNull();
  });

  it('saves a cash sale, asks first, and shows the receipt choices', async () => {
    const { h, fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    await settle(fixture);

    byTestId(el, 'till-charge')!.click();
    await settle(fixture);
    const post = h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && r.method === 'POST');
    expect(post.request.body).toMatchObject({ payment_status: 'paid', total: 1000, paid_total: 1000, items: [{ product_id: 1, quantity: 1, unit_price: 1000 }] });
    post.flush({ data: { id: 55, number: 'S-55' } }, { status: 201, statusText: 'Created' });
    await settle(fixture);
    h.http.expectOne((r) => r.url.endsWith('/inventory/sales/55')).flush({ data: { id: 55, number: 'S-55', total: 1000, paid_total: 1000, items: [], payments: [] } });
    await settle(fixture);
    h.http.match((r) => r.url.endsWith('/inventory/products')).forEach((r) => r.flush({ data: [soda], meta: { last_page: 1 } }));

    expect(text(byTestId(el, 'till-done-total')!)).toBe('TSH 1,000');
    expect(byTestId(el, 'till-print')).not.toBeNull();
    byTestId(el, 'till-new')!.click();
    await settle(fixture);
    expect(byTestId(el, 'till-empty')).not.toBeNull();
  });

  describe('as on the mobile till', () => {
    it('offers no price level when the business sells at one price', async () => {
      const { el } = await open();
      expect(byTestId(el, 'till-level')).toBeNull();
    });

    it('does not offer a price level in a salon, whose services have one price (or price options)', async () => {
      const { el } = await open({}, [cut], true, { sale_tier: 'retail' });
      expect(byTestId(el, 'till-level')).toBeNull();
    });

    it('lets a business with retail and wholesale prices switch between them, starting on its usual one', async () => {
      const { fixture, el } = await open({}, [soda], false, { sale_tier: 'wholesale' });
      const retail = byTestId(el, 'till-level-retail') as HTMLButtonElement;
      const wholesale = byTestId(el, 'till-level-wholesale') as HTMLButtonElement;
      expect(wholesale.getAttribute('aria-pressed')).toBe('true');

      retail.click();
      await settle(fixture);

      expect(retail.getAttribute('aria-pressed')).toBe('true');
      expect(wholesale.getAttribute('aria-pressed')).toBe('false');
    });

    it('clears the cart only after asking', async () => {
      const { h, fixture, el } = await open();
      byTestId(el, 'good-1')!.click();
      await settle(fixture);

      h.confirmAnswer.value = false;
      byTestId(el, 'till-clear')!.click();
      await settle(fixture);
      expect(byTestId(el, 'line-1')).not.toBeNull();

      h.confirmAnswer.value = true;
      byTestId(el, 'till-clear')!.click();
      await settle(fixture);
      expect(byTestId(el, 'line-1')).toBeNull();
      expect(byTestId(el, 'till-empty')).not.toBeNull();
    });

    it('the cashier can write the price instead of the list price, and the sale uses it', async () => {
      const { h, fixture, el } = await open();
      byTestId(el, 'good-1')!.click();
      await settle(fixture);
      expect((byTestId(el, 'price-1') as HTMLInputElement).value).toBe('1,000');
      expect(byTestId(el, 'price-changed-1')).toBeNull();

      const box = byTestId(el, 'price-1') as HTMLInputElement;
      box.value = '850';
      box.dispatchEvent(new Event('change', { bubbles: true }));
      await settle(fixture);

      expect(text(byTestId(el, 'till-total')!)).toBe('TSH 850');
      expect(byTestId(el, 'price-changed-1')).not.toBeNull();

      byTestId(el, 'till-charge')!.click();
      await settle(fixture);
      const post = h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && r.method === 'POST');
      expect(post.request.body).toMatchObject({ total: 850, items: [{ product_id: 1, quantity: 1, unit_price: 850 }] });
    });

    it('a written price is kept when the price level changes, and the usual price can be taken back', async () => {
      const { fixture, el } = await open({}, [soda], false, { sale_tier: 'retail' });
      byTestId(el, 'good-1')!.click();
      await settle(fixture);
      const box = byTestId(el, 'price-1') as HTMLInputElement;
      box.value = '700';
      box.dispatchEvent(new Event('change', { bubbles: true }));
      await settle(fixture);

      byTestId(el, 'till-level-wholesale')!.click();
      await settle(fixture);
      expect(text(byTestId(el, 'till-total')!)).toBe('TSH 700');

      byTestId(el, 'price-usual-1')!.click();
      await settle(fixture);
      expect(text(byTestId(el, 'till-total')!)).toBe('TSH 1,000');
      expect(byTestId(el, 'price-changed-1')).toBeNull();
    });

    it('a price that is not a number leaves the price as it was', async () => {
      const { fixture, el } = await open();
      byTestId(el, 'good-1')!.click();
      await settle(fixture);
      const box = byTestId(el, 'price-1') as HTMLInputElement;
      box.value = 'abc';
      box.dispatchEvent(new Event('change', { bubbles: true }));
      await settle(fixture);

      expect(text(byTestId(el, 'till-total')!)).toBe('TSH 1,000');
    });

    it('sends the name and phone of a walk-in customer with the sale', async () => {
      const { h, fixture, el } = await open();
      byTestId(el, 'good-1')!.click();
      await settle(fixture);
      type(el, '[data-testid=till-walkin]', 'Mama Zawadi');
      type(el, '[data-testid=till-walkin-phone]', '0712345678');
      await settle(fixture);

      byTestId(el, 'till-charge')!.click();
      await settle(fixture);
      const post = h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && r.method === 'POST');

      expect(post.request.body).toMatchObject({ customer_name_override: 'Mama Zawadi', customer_phone: '0712345678' });
    });
  });

  it('does not send anything when the person answers No to the question', async () => {
    const { h, fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    await settle(fixture);
    h.confirmAnswer.value = false;
    byTestId(el, 'till-charge')!.click();
    await settle(fixture);
    h.http.expectNone((r) => r.url.endsWith('/inventory/sales') && r.method === 'POST');
  });

  it('a sale paid later needs a customer, and says so in plain words', async () => {
    const { fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    byTestId(el, 'mode-debt')!.click();
    await settle(fixture);
    expect(byTestId(el, 'till-needcustomer')).not.toBeNull();

    byTestId(el, 'till-charge')!.click();
    await settle(fixture);
    expect(text(byTestId(el, 'till-error')!)).toContain('Choose a customer first');
  });

  it('a customer who is over the credit limit cannot be sold to on credit', async () => {
    const { h, fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    type(el, '[data-testid=till-customer-search]', 'nee');
    await settle(fixture);
    h.http.expectOne((r) => r.url.endsWith('/inventory/customers') && r.method === 'GET').flush({ data: [{ id: 7, name: 'Neema', phone: '0712' }] });
    await settle(fixture);
    byTestId(el, 'hit-7')!.click();
    await settle(fixture);
    byTestId(el, 'mode-debt')!.click();
    await settle(fixture);
    h.http.match((r) => r.url.includes('/credit/customers/7/check')).forEach((r) => r.flush({ data: { customer_id: 7, balance: 90000, credit_limit: 100000, available: 10000, is_blocked: false, over_limit: true, near_limit: false } }));
    await settle(fixture);

    byTestId(el, 'till-charge')!.click();
    await settle(fixture);
    expect(text(byTestId(el, 'till-error')!)).toContain('over the credit limit of TSH 100,000');
    h.http.expectNone((r) => r.url.endsWith('/inventory/sales') && r.method === 'POST');
  });

  it('puts a sale aside', async () => {
    const { h, fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    await settle(fixture);
    byTestId(el, 'till-park')!.click();
    const post = h.http.expectOne((r) => r.url.endsWith('/inventory/parked-sales') && r.method === 'POST');
    expect(post.request.body).toMatchObject({ total: 1000 });
    post.flush({});
    await settle(fixture);
    expect(byTestId(el, 'till-empty')).not.toBeNull();
  });
});

describe('the till in a salon', () => {
  it('will not save a service until the stylist who served is chosen, then sends who it was', async () => {
    const { h, fixture, el } = await open({}, [cut], true);
    byTestId(el, 'good-9')!.click();
    await settle(fixture);

    byTestId(el, 'till-charge')!.click();
    await settle(fixture);
    expect(text(byTestId(el, 'till-error')!)).toContain('Choose who served the client for "Haircut"');

    const pick = byTestId(el, 'stylist-9') as HTMLSelectElement;
    pick.value = pick.querySelector('option[value="5"]') ? '5' : pick.value;
    pick.dispatchEvent(new Event('change', { bubbles: true }));
    await settle(fixture);
    byTestId(el, 'till-charge')!.click();
    await settle(fixture);
    const post = h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && r.method === 'POST');
    expect((post.request.body as { items: Record<string, unknown>[] }).items[0]).toMatchObject({ product_id: 9, staff_id: '5' });
  });

  it('a service line offers the goods used', async () => {
    const { h, fixture, el } = await open({}, [cut], true);
    byTestId(el, 'good-9')!.click();
    await settle(fixture);
    byTestId(el, 'goods-9')!.click();
    h.http.expectOne((r) => r.url.endsWith('/salon/services/9/usual-goods')).flush({ data: [{ product_id: 2, name: 'Gel', quantity: 2 }] });
    await settle(fixture);
    expect(text(el)).toContain('Gel');
  });
});

describe('the till and crates', () => {
  async function crateRequests(who: object, salon = false): Promise<number> {
    const h = configure(salon ? { services: ['salon'], ...who } : who);
    const fixture = TestBed.createComponent(TillPage);
    fixture.detectChanges();
    await settle(fixture);
    const asked = h.http.match((r) => r.url.endsWith('/crate-types'));
    asked.forEach((r) => r.flush({ data: [] }));
    h.http.match(() => true).forEach((r) => r.flush({ data: [], meta: { last_page: 1 } }));
    return asked.length;
  }

  it('does not ask for crates when the person may not see them (the server would answer 403)', async () => {
    expect(await crateRequests({})).toBe(0);
  });

  it('asks for crates when the person has the right, but never in a salon', async () => {
    const rights = ['inv_create_sales', 'inv_view_crates'];
    expect(await crateRequests({ permissions: rights })).toBe(1);
    TestBed.resetTestingModule();
    expect(await crateRequests({ permissions: rights }, true)).toBe(0);
  });
});
