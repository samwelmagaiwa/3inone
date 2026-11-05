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

  describe('the popup with its five steps', () => {
    const shown = (el: HTMLElement, id: string) => !!byTestId(el, id) && !byTestId(el, id)!.closest('.hidden');

    it('starts on step 1, and Next waits for something to be in the sale', async () => {
      const { fixture, el } = await open();

      expect(text(byTestId(el, 'till-step-title')!)).toContain('1.');
      byTestId(el, 'till-next')!.click(); // nothing to sell yet: it says so and stays on step 1
      await settle(fixture);
      expect(text(byTestId(el, 'till-error')!)).toContain('Add at least one item');
      expect(text(byTestId(el, 'till-step-title')!)).toContain('1.');
      byTestId(el, 'good-1')!.click();
      await settle(fixture);
      byTestId(el, 'till-next')!.click();
      await settle(fixture);
      expect(byTestId(el, 'till-error')).toBeNull();
      expect(text(byTestId(el, 'till-step-title')!)).toContain('2.');
      byTestId(el, 'till-back')!.click();
      await settle(fixture);
      expect(text(byTestId(el, 'till-running')!)).toContain('TSH 1,000');
    });

    it('walks the steps one at a time: goods, the cart, who buys, how they pay, and then the preview', async () => {
      const { fixture, el } = await open();
      byTestId(el, 'good-1')!.click();
      await settle(fixture);
      expect(shown(el, 'good-1')).toBe(true);
      expect(shown(el, 'line-1')).toBe(false);

      for (const [step, visible] of [[2, 'line-1'], [3, 'till-customer'], [4, 'mode-cash']] as const) {
        byTestId(el, 'till-next')!.click();
        await settle(fixture);
        expect(text(byTestId(el, 'till-step-title')!)).toContain(`${step}.`);
        expect(shown(el, visible) || visible === 'till-customer').toBe(true);
        expect(shown(el, 'good-1')).toBe(false);
      }
      expect(text(byTestId(el, 'till-next')!)).toBe('Check the sale');

      byTestId(el, 'till-next')!.click();
      await settle(fixture);
      expect(text(byTestId(el, 'till-step-title')!)).toContain('5.');
      expect(shown(el, 'till-preview')).toBe(true);
      expect(byTestId(el, 'till-next')).toBeNull(); // the preview ends with Save
      byTestId(el, 'till-back')!.click();
      await settle(fixture);
      expect(text(byTestId(el, 'till-step-title')!)).toContain('4.');
    });

    it('the preview lists what was filled in: the goods, the customer, the payment and the total', async () => {
      const { fixture, el } = await open();
      byTestId(el, 'good-1')!.click();
      await settle(fixture);
      for (let i = 0; i < 4; i++) {
        byTestId(el, 'till-next')!.click();
        await settle(fixture);
      }
      const preview = text(byTestId(el, 'till-preview')!);

      expect(preview).toContain('Soda');
      expect(preview).toContain('1 × TSH 1,000');
      expect(text(byTestId(el, 'pv-customer')!)).toContain('Walk-in customer');
      expect(text(byTestId(el, 'pv-payment')!)).toContain('Cash');
      expect(text(byTestId(el, 'till-total')!)).toBe('TSH 1,000');
    });

    it('a sale on credit without a customer is stopped at step 4 and taken to step 3', async () => {
      const { fixture, el } = await open();
      byTestId(el, 'good-1')!.click();
      await settle(fixture);
      for (let i = 0; i < 3; i++) {
        byTestId(el, 'till-next')!.click();
        await settle(fixture);
      }
      byTestId(el, 'mode-debt')!.click();
      await settle(fixture);
      byTestId(el, 'till-next')!.click();
      await settle(fixture);

      expect(text(byTestId(el, 'till-step-title')!)).toContain('3.');
      expect(text(byTestId(el, 'till-error')!)).toContain('customer');
    });

    it('what is required is marked with a red asterisk, and goes red when the step is tried without it', async () => {
      const { fixture, el } = await open();
      const note = byTestId(el, 'till-need-items')!;
      expect(note.querySelector('.req-star')).not.toBeNull();
      expect(note.classList.contains('is-bad')).toBe(false);

      byTestId(el, 'till-next')!.click(); // nothing chosen
      await settle(fixture);
      expect(note.classList.contains('is-bad')).toBe(true);

      byTestId(el, 'good-1')!.click();
      await settle(fixture);
      byTestId(el, 'till-next')!.click();
      await settle(fixture);
      expect(el.querySelector('label.req-star[for="price-1"]')).not.toBeNull(); // the price of each line is required
    });

    it('a part payment needs an amount above zero and below the total, and a new customer needs a phone number', async () => {
      const { fixture, el } = await open();
      byTestId(el, 'good-1')!.click();
      await settle(fixture);
      for (let i = 0; i < 3; i++) {
        byTestId(el, 'till-next')!.click();
        await settle(fixture);
      }
      byTestId(el, 'mode-partial')!.click();
      await settle(fixture);
      byTestId(el, 'till-next')!.click();
      await settle(fixture);
      expect(text(byTestId(el, 'till-error')!)).toContain('how much is paid now'); // the customer comes first on a sale paid later?
    });

    it('Save sale on the preview saves at once, with no second question', async () => {
      const { h, fixture, el } = await open();
      byTestId(el, 'good-1')!.click();
      await settle(fixture);
      for (let i = 0; i < 4; i++) {
        byTestId(el, 'till-next')!.click();
        await settle(fixture);
      }
      h.confirmAnswer.value = false; // a question would be answered "no": the sale must still go

      byTestId(el, 'till-charge')!.click();
      await settle(fixture);

      expect(h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && r.method === 'POST').request.body).toMatchObject({ total: 1000 });
    });
  });

  it('a price of zero is stopped at step 2, and a salon has All / Services / Goods tabs in plain sight', async () => {
    const { h, fixture, el } = await open({}, [soda], true);
    expect(byTestId(el, 'till-kind-service')).not.toBeNull();
    byTestId(el, 'till-kind-service')!.click();
    await settle(fixture);
    expect(h.http.expectOne((r) => r.url.endsWith('/inventory/products')).request.params.get('is_service')).toBe('1');
    h.http.match((r) => r.url.endsWith('/inventory/products')).forEach((r) => r.flush({ data: [], meta: { last_page: 1 } }));
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
      byTestId(el, 'till-tab-walkin')!.click();
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

  it('shows the account of the customer on a credit sale: old debt, new debt, what this sale adds and the total', async () => {
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
    h.http.match((r) => r.url.includes('/credit/customers/7/check')).forEach((r) => r.flush({
      data: {
        customer_id: 7, balance: 280000, credit_limit: 0, available: null, is_blocked: false, over_limit: false, near_limit: false,
        debt: {
          old: { entries: [], original: 350000, paid: 100000, left: 250000 },
          new: { billed: 80000, paid: 50000, left: 30000 },
          total: { owed: 430000, paid: 150000, left: 280000 },
        },
      },
    }));
    await settle(fixture);

    const account = text(byTestId(el, 'till-account')!);
    expect(account).toContain('Old debt (before the app): Left to pay TSH 250,000');
    expect(account).toContain('New debt (credit sales): Left to pay TSH 30,000');
    expect(text(byTestId(el, 'till-acct-thissale')!)).toBe('This sale, on credit: TSH 1,000');
    expect(text(byTestId(el, 'till-acct-paid')!)).toContain('TSH 150,000');
    expect(text(byTestId(el, 'till-acct-after')!)).toBe('Balance after this sale: TSH 281,000');
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

    expect(byTestId(el, 'stylist-menu-9')).toBeNull(); // the list stays closed until asked for
    byTestId(el, 'stylist-btn-9')!.click();
    await settle(fixture);
    byTestId(el, 'stylist-9-5')!.click();
    await settle(fixture);
    expect(byTestId(el, 'stylist-menu-9')).toBeNull(); // and closes once one is chosen
    expect(text(byTestId(el, 'stylist-btn-9')!)).toContain('Zawadi');
    byTestId(el, 'till-charge')!.click();
    await settle(fixture);
    const post = h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && r.method === 'POST');
    expect((post.request.body as { items: Record<string, unknown>[] }).items[0]).toMatchObject({ product_id: 9, staff_id: '5' });
  });

  it('choosing a service asks at once which goods the visit used, with the usual ones filled in', async () => {
    const { h, fixture, el } = await open({}, [cut], true);
    byTestId(el, 'good-9')!.click();
    await settle(fixture);

    // the card opens by itself: the usual goods of the service, and the whole list of goods to add from
    h.http.expectOne((r) => r.url.endsWith('/salon/services/9/usual-goods')).flush({ data: [{ product_id: 2, name: 'Gel', quantity: 2 }] });
    const goods = h.http.expectOne((r) => r.url.endsWith('/inventory/products') && r.params.get('is_service') === '0');
    goods.flush({ data: [{ id: 2, name: 'Gel', selling_price: 5000, cost_price: 2500, quantity: 20, status: 'active', is_service: 0 }, { id: 3, name: 'Oil', selling_price: 9000, cost_price: 4000, quantity: 5, status: 'active', is_service: 0 }], meta: { last_page: 1 } });
    await settle(fixture);
    expect(text(el)).toContain('Gel');

    const pick = el.querySelector('select[aria-label="goods"]') as HTMLSelectElement;
    expect(Array.from(pick.options).map((o) => o.text.trim())).toContain('Oil'); // goods can be added although the list shows services
    pick.value = '3';
    pick.dispatchEvent(new Event('change', { bubbles: true }));
    (Array.from(el.querySelectorAll('button')).find((b) => b.textContent?.trim() === 'Add') as HTMLButtonElement | undefined)?.click();
    await settle(fixture);
    (Array.from(el.querySelectorAll('button')).find((b) => b.textContent?.trim() === 'Save') as HTMLButtonElement).click();
    await settle(fixture);

    expect(text(byTestId(el, 'used-9')!)).toContain('Gel ×2');
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

describe('the till: other prices, payment codes and customers', () => {
  const conrow = { id: 3, name: 'conrow', selling_price: 55000, cost_price: 0, quantity: 0, status: 'active', is_service: 1, price_options: [{ label: 'small size', price: 40000 }] };

  it('a product with other prices still offers its usual price, first', async () => {
    const { fixture, el } = await open({}, [conrow]);
    byTestId(el, 'good-3')!.click();
    await settle(fixture);
    expect(byTestId(el, 'option-usual')).not.toBeNull();
    expect(text(byTestId(el, 'option-usual')!)).toContain('55,000');

    byTestId(el, 'option-usual')!.click();
    await settle(fixture);
    expect(text(byTestId(el, 'till-total')!)).toBe('TSH 55,000');
    expect(text(byTestId(el, 'line-3')!)).toContain('conrow');
    expect(text(byTestId(el, 'line-3')!)).not.toContain('small size');
  });

  it('the other price is still there to choose', async () => {
    const { fixture, el } = await open({}, [conrow]);
    byTestId(el, 'good-3')!.click();
    await settle(fixture);
    const small = Array.from(el.ownerDocument.querySelectorAll('button')).find((b) => (b.textContent ?? '').includes('small size')) as HTMLButtonElement;
    small.click();
    await settle(fixture);
    expect(text(byTestId(el, 'till-total')!)).toBe('TSH 40,000');
  });

  it('the reference number of a mobile money payment is optional: sent when written, left out when not', async () => {
    const { h, fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    await settle(fixture);
    expect(byTestId(el, 'till-ref')).toBeNull(); // cash: no code

    const chan = el.querySelector('#chan') as HTMLSelectElement;
    chan.value = 'mpesa';
    chan.dispatchEvent(new Event('change', { bubbles: true }));
    await settle(fixture);
    expect(byTestId(el, 'till-ref')).not.toBeNull();
    expect(el.querySelector('label[for="ref"].req')).toBeNull(); // no red asterisk: it is not required

    type(el, '[data-testid=till-ref]', '  8K3J2L9X ');
    await settle(fixture);
    byTestId(el, 'till-charge')!.click();
    await settle(fixture);
    const post = h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && r.method === 'POST');
    expect((post.request.body as { payments: Record<string, unknown>[] }).payments[0]).toMatchObject({ method: 'mpesa', reference: '8K3J2L9X' });
  });

  it('a mobile money payment with no reference still saves, with the reference empty', async () => {
    const { h, fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    await settle(fixture);
    const chan = el.querySelector('#chan') as HTMLSelectElement;
    chan.value = 'mpesa';
    chan.dispatchEvent(new Event('change', { bubbles: true }));
    await settle(fixture);

    byTestId(el, 'till-charge')!.click();
    await settle(fixture);

    const post = h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && r.method === 'POST');
    expect((post.request.body as { payments: Record<string, unknown>[] }).payments[0]).toMatchObject({ method: 'mpesa', reference: null });
  });

  it('cash sends no reference at all', async () => {
    const { h, fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    await settle(fixture);
    byTestId(el, 'till-charge')!.click();
    await settle(fixture);
    const post = h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && r.method === 'POST');
    expect((post.request.body as { payments: Record<string, unknown>[] }).payments[0]).toMatchObject({ method: 'cash', reference: null });
  });

  it('a part payment by bank can also carry the reference of what was paid now', async () => {
    const { fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    byTestId(el, 'mode-partial')!.click();
    await settle(fixture);
    expect(byTestId(el, 'till-partial-ref')).toBeNull();
    const chan = el.querySelector('#pchan') as HTMLSelectElement;
    chan.value = 'bank_transfer';
    chan.dispatchEvent(new Event('change', { bubbles: true }));
    await settle(fixture);
    expect(byTestId(el, 'till-partial-ref')).not.toBeNull();
  });

  it('a sale paid later says the customer is required and offers the way to add one', async () => {
    const { h, fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    byTestId(el, 'mode-partial')!.click();
    await settle(fixture);
    expect(byTestId(el, 'till-customer-required')).not.toBeNull();
    expect(byTestId(el, 'till-tab-walkin')).toBeNull(); // no name at all is only for a sale paid now
    expect(byTestId(el, 'till-customer-search')).not.toBeNull();

    byTestId(el, 'till-tab-new')!.click();
    await settle(fixture);
    byTestId(el, 'till-newcustomer-save')!.click();
    await settle(fixture);
    expect(text(byTestId(el, 'till-newcustomer-error')!)).toContain("Write the customer's name");

    type(el, '[data-testid=till-newcustomer-name]', 'Neema Joseph');
    type(el, '[data-testid=till-newcustomer-phone]', '0712000111');
    await settle(fixture);
    byTestId(el, 'till-newcustomer-save')!.click();
    const post = h.http.expectOne((r) => r.url.endsWith('/inventory/customers') && r.method === 'POST');
    expect(post.request.body).toEqual({ name: 'Neema Joseph', phone: '0712000111' });
    post.flush({ data: { id: 12, name: 'Neema Joseph', phone: '0712000111' } });
    await settle(fixture);
    h.http.match((r) => r.url.includes('/credit/customers/12/check')).forEach((r) => r.flush({ data: { customer_id: 12, balance: 0, credit_limit: 0, available: null, is_blocked: false, over_limit: false, near_limit: false } }));
    await settle(fixture);

    expect(byTestId(el, 'till-customer')).not.toBeNull();
    expect(byTestId(el, 'till-customer-required')).toBeNull();
  });

  it('the + Add link under the search hits opens the new-customer form with the typed name', async () => {
    const { h, fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    type(el, '[data-testid=till-customer-search]', 'Rehema');
    await settle(fixture);
    h.http.expectOne((r) => r.url.endsWith('/inventory/customers') && r.method === 'GET').flush({ data: [] });
    await settle(fixture);
    byTestId(el, 'till-customer-new')!.click();
    await settle(fixture);
    expect((byTestId(el, 'till-newcustomer-name') as HTMLInputElement).value).toBe('Rehema');
  });
});

describe('the till: required fields', () => {
  it('stylists are in a menu, so many of them never stretch the line, and a long list can be searched', async () => {
    const many = Array.from({ length: 12 }, (_, i) => ({ id: String(20 + i), name: i === 7 ? 'Zuhura Omari' : `Stylist ${i}`, role: 'stylist' }));
    const h = configure({ services: ['salon'] });
    const fixture = TestBed.createComponent(TillPage);
    fixture.detectChanges();
    h.http.match((r) => r.url.endsWith('/inventory/settings')).forEach((r) => r.flush({ data: { sale_tier: 'product', prices_include_vat: '1' } }));
    h.http.expectOne((r) => r.url.endsWith('/inventory/products')).flush({ data: [cut], meta: { last_page: 1 } });
    h.http.match((r) => r.url.endsWith('/salon/staff')).forEach((r) => r.flush({ data: many }));
    h.http.match((r) => r.url.endsWith('/loyalty/settings')).forEach((r) => r.flush({ data: { on: false, per: 0, value: 0 } }));
    await settle(fixture);
    const el = fixture.nativeElement as HTMLElement;

    byTestId(el, 'good-9')!.click();
    await settle(fixture);
    expect(el.querySelectorAll('[data-testid^="stylist-9-"]').length).toBe(0); // nobody is listed until the menu is opened
    byTestId(el, 'stylist-btn-9')!.click();
    await settle(fixture);
    expect(el.querySelectorAll('[data-testid^="stylist-9-"]').length).toBe(12);
    expect(byTestId(el, 'stylist-search')).not.toBeNull();

    type(el, '[data-testid=stylist-search]', 'zuhu');
    await settle(fixture);
    expect(el.querySelectorAll('[data-testid^="stylist-9-"]').length).toBe(1);
    byTestId(el, 'stylist-9-27')!.click();
    await settle(fixture);
    expect(text(byTestId(el, 'stylist-btn-9')!)).toContain('Zuhura Omari');
  });

  it('a short list of stylists needs no search box', async () => {
    const { fixture, el } = await open({}, [cut], true);
    byTestId(el, 'good-9')!.click();
    await settle(fixture);
    byTestId(el, 'stylist-btn-9')!.click();
    await settle(fixture);
    expect(byTestId(el, 'stylist-search')).toBeNull();
  });

  it('marks what must be filled with a red asterisk (not the reference, which is optional), and outlines the empty ones after a failed save', async () => {
    const { fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    const chan = () => el.querySelector('#chan') as HTMLSelectElement;
    await settle(fixture);
    chan().value = 'mpesa';
    chan().dispatchEvent(new Event('change', { bubbles: true }));
    await settle(fixture);
    expect((el.querySelector('label[for=ref]') as HTMLElement).classList.contains('req')).toBe(false);
    expect((el.querySelector('#ref') as HTMLInputElement).required).toBe(false);
    expect((el.querySelector('#ref') as HTMLInputElement).placeholder).toBe('e.g. 8K3J2L9X');
    expect(el.querySelector('section.attempted')).toBeNull();

    byTestId(el, 'mode-debt')!.click(); // a sale on credit with no customer: a real failure
    await settle(fixture);
    byTestId(el, 'till-charge')!.click();
    await settle(fixture);
    expect(el.querySelector('section.attempted')).not.toBeNull();
  });

  it('the new customer form marks the name as required and has placeholders', async () => {
    const { fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    byTestId(el, 'mode-debt')!.click();
    byTestId(el, 'till-tab-new')!.click();
    await settle(fixture);
    expect((el.querySelector('label[for=newName]') as HTMLElement).classList.contains('req')).toBe(true);
    expect((el.querySelector('#newName') as HTMLInputElement).required).toBe(true);
    expect((el.querySelector('#newName') as HTMLInputElement).placeholder).toBe('Full name');
    expect((el.querySelector('#newPhone') as HTMLInputElement).placeholder).toContain('0712');
  });

  it('the reason for a discount is required while there is a discount with no voucher', async () => {
    const { fixture, el } = await open({}, [cut], true);
    byTestId(el, 'good-9')!.click();
    await settle(fixture);
    const why = () => el.querySelector('#why') as HTMLInputElement;
    expect(why().required).toBe(false);
    type(el, '[data-testid=till-discount]', '1000');
    await settle(fixture);
    expect(why().required).toBe(true);
    expect((el.querySelector('label[for=why]') as HTMLElement).classList.contains('req')).toBe(true);
  });
});

describe('the till: where to choose the customer', () => {
  it('the message about the customer has a button that takes the person to the customer step', async () => {
    const { fixture, el } = await open();
    byTestId(el, 'good-1')!.click();
    byTestId(el, 'mode-debt')!.click();
    byTestId(el, 'till-tab-new')!.click();
    await settle(fixture);

    byTestId(el, 'till-goto-customer')!.click();
    await settle(fixture);
    // it opens the search box of step 3
    expect(byTestId(el, 'till-customer-search')).not.toBeNull();
    expect(el.querySelector('#till-customer-section')).not.toBeNull();
  });
});
