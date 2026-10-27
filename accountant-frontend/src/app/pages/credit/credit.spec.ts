import { TestBed } from '@angular/core/testing';

import { environment } from '../../../environments/environment';
import { byTestId, configure, settle, text, type } from '../../testing';
import { CreditPage } from './credit';

const API = environment.apiUrl;
const CUSTOMERS = `${API}/inventory/credit/customers`;

const customer = (id: number, over: Record<string, unknown> = {}) => ({
  id, name: `Customer ${id}`, phone: `07110000${id}`, balance: 0, old_balance: 0, credit_limit: '0.00', payment_terms_days: 30, is_blocked: 0, block_reason: null, ...over,
});

const ROWS = [
  customer(1, { name: 'Mama Neema Joseph', balance: 350000, old_balance: 90000, credit_limit: '500000.00' }),
  customer(2, { name: 'Baba Juma', balance: 120000, credit_limit: '100000.00' }),
  customer(3, { name: 'Dada Rehema', balance: 95000, credit_limit: '100000.00' }),
  customer(4, { name: 'Mzee Hamisi', balance: 20000, is_blocked: 1, block_reason: 'not paying' }),
  customer(5, { name: 'Kaka Ali', balance: 0 }),
];

const AGEING = {
  data: [{ customer_id: 1, customer_name: 'Mama Neema Joseph', customer_phone: '071100001', credit_limit: 500000, current: 100000, days_31_60: 0, days_61_90: 0, days_90_plus: 250000, total: 350000, oldest_days: 200 }],
  meta: { grand_total: 350000, current: 100000, days_31_60: 0, days_61_90: 0, days_90_plus: 250000 },
};

const SALES_OFFICER = ['inv_view_products', 'inv_create_sales', 'inv_view_credit', 'inv_view_cash'];
const WITHOUT_CASH = ['inv_view_credit'];

async function open(permissions: string[], rows: unknown[] = ROWS) {
  const h = configure({ permissions });
  const fixture = TestBed.createComponent(CreditPage);
  fixture.detectChanges();
  h.http.expectOne({ method: 'GET', url: CUSTOMERS }).flush({ data: rows });
  h.http.expectOne({ method: 'GET', url: `${API}/inventory/credit/debtors-ageing` }).flush(AGEING);
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

const click = (el: HTMLElement, id: string) => (byTestId(el, id) as HTMLElement).click();

const STATEMENT = {
  data: {
    from: '2026-11-01', to: '2026-11-30', opening_balance: 100000, old_debt: 90000, period_charges: 300000, period_payments: 50000, closing_balance: 350000,
    sales: [
      { id: 11, number: 'S-0011', total: 200000, paid_total: 0, payment_status: 'debt', due_date: '2026-12-01', created_at: '2026-11-05 10:00:00' },
      { id: 12, number: 'S-0012', total: 100000, paid_total: 40000, payment_status: 'partial', due_date: null, created_at: '2026-11-10 10:00:00' },
      { id: 13, number: 'S-0013', total: 50000, paid_total: 50000, payment_status: 'paid', due_date: null, created_at: '2026-11-12 10:00:00' },
    ],
    payments: [{ id: 1, amount: 50000, method: 'cash', reference: null, paid_at: '2026-11-12 10:00:00', sale_number: 'S-0013' }],
  },
};

describe('customers & credit', () => {
  it('shows what each customer owes, the old part, the limit and a plain status', async () => {
    const { el } = await open(SALES_OFFICER);

    const neema = text(byTestId(el, 'cr-row-1')!);
    expect(neema).toContain('Mama Neema Joseph');
    expect(neema).toContain('071100001');
    expect(neema).toContain('TSH 350,000');
    expect(neema).toContain('including TSH 90,000 from before the app');
    expect(neema).toContain('TSH 500,000');

    expect(text(byTestId(el, 'cr-state-1')!)).toBe('OK');
    expect(text(byTestId(el, 'cr-state-2')!)).toBe('Over the limit');
    expect(text(byTestId(el, 'cr-state-3')!)).toBe('Near the limit');
    expect(text(byTestId(el, 'cr-state-4')!)).toBe('Blocked');
    expect(text(byTestId(el, 'cr-row-4')!)).toContain('not paying');
  });

  it('adds up what is owed, who owes and who needs attention', async () => {
    const { el } = await open(SALES_OFFICER);

    expect(text(byTestId(el, 'cr-total')!)).toBe('TSH 585,000');
    expect(text(byTestId(el, 'cr-owing')!)).toBe('4');
    expect(text(byTestId(el, 'cr-watch')!)).toBe('2');
  });

  it('searches by name and filters to those who owe or are near, over or blocked', async () => {
    const { fixture, el } = await open(SALES_OFFICER);

    type(el, '.filter-input', 'juma');
    await settle(fixture);
    expect(text(el)).toContain('Baba Juma');
    expect(text(el)).not.toContain('Mama Neema');

    type(el, '.filter-input', '');
    const filter = byTestId(el, 'cr-filter') as HTMLSelectElement;
    filter.value = 'limit';
    filter.dispatchEvent(new Event('change', { bubbles: true }));
    await settle(fixture);
    expect(byTestId(el, 'cr-row-1')).toBeNull();
    expect(byTestId(el, 'cr-row-2')).not.toBeNull();
    expect(byTestId(el, 'cr-row-3')).not.toBeNull();
    expect(byTestId(el, 'cr-row-4')).not.toBeNull();
  });

  it('receiving money needs the cash right, as on the server; reading the account does not', async () => {
    const withCash = await open(SALES_OFFICER);
    expect(byTestId(withCash.el, 'cr-pay-1')).not.toBeNull();

    TestBed.resetTestingModule();
    const without = await open(WITHOUT_CASH);
    expect(byTestId(without.el, 'cr-pay-1')).toBeNull();
    expect(byTestId(without.el, 'cr-statement-1')).not.toBeNull();
    expect(byTestId(without.el, 'cr-settings-1')).not.toBeNull();
  });

  it('shows the debts by age', async () => {
    const { fixture, el } = await open(SALES_OFFICER);

    click(el, 'cr-tab-ageing');
    await settle(fixture);

    expect(text(byTestId(el, 'age-90')!)).toBe('TSH 250,000');
    expect(text(byTestId(el, 'age-row-1')!)).toContain('200 days');
  });

  describe('a customer\'s statement', () => {
    it('asks for the days chosen and shows where the account started, moved and stands', async () => {
      const { h, fixture, el } = await open(SALES_OFFICER);

      click(el, 'cr-statement-1');
      const req = h.http.expectOne((r) => r.url === `${CUSTOMERS}/1/statement`);
      expect(req.request.params.get('from')).toMatch(/^\d{4}-\d{2}-01$/);
      req.flush(STATEMENT);
      await settle(fixture);

      expect(text(byTestId(el, 'st-opening')!)).toContain('TSH 100,000');
      expect(text(byTestId(el, 'st-closing')!)).toBe('TSH 350,000');
      expect(text(byTestId(el, 'st-summary')!)).toContain('TSH 90,000 from before the app');
      expect(text(el)).toContain('S-0011');
      expect(text(el)).toContain('S-0013');
    });
  });

  describe('credit settings', () => {
    it('saves the limit, the days to pay and a block with its reason', async () => {
      const { h, fixture, el } = await open(SALES_OFFICER);

      click(el, 'cr-settings-5');
      await settle(fixture);
      type(el, '[data-testid="cs-limit"]', '250,000');
      type(el, '[data-testid="cs-terms"]', '14');
      (byTestId(el, 'cs-blocked') as HTMLInputElement).click();
      await settle(fixture);
      type(el, '[data-testid="cs-reason"]', 'late again');
      await settle(fixture);
      click(el, 'cs-save');

      const req = h.http.expectOne({ method: 'PUT', url: `${CUSTOMERS}/5` });
      expect(req.request.body).toEqual({ credit_limit: 250000, payment_terms_days: 14, is_blocked: true, block_reason: 'late again' });
      req.flush({ message: 'Credit settings saved' });
      await settle(fixture);
      h.http.expectOne({ method: 'GET', url: CUSTOMERS }).flush({ data: ROWS });
      h.http.expectOne({ method: 'GET', url: `${API}/inventory/credit/debtors-ageing` }).flush(AGEING);
    });

    it('refuses a limit that is not a number, without sending anything', async () => {
      const { h, fixture, el } = await open(SALES_OFFICER);

      click(el, 'cr-settings-1');
      await settle(fixture);
      type(el, '[data-testid="cs-limit"]', 'plenty');
      await settle(fixture);
      click(el, 'cs-save');
      await settle(fixture);

      expect(text(el)).toContain('The limit must be a number');
      h.http.expectNone({ method: 'PUT', url: `${CUSTOMERS}/1` });
    });
  });

  describe('receiving a payment', () => {
    async function openPay() {
      const o = await open(SALES_OFFICER);
      click(o.el, 'cr-pay-1');
      const req = o.h.http.expectOne((r) => r.url === `${CUSTOMERS}/1/statement`);
      expect(req.request.params.get('from')).toBe('2000-01-01');
      req.flush(STATEMENT);
      await settle(o.fixture);

      return o;
    }

    it('lists only the sales still unpaid, with what each still owes', async () => {
      const { el } = await openPay();

      expect(text(el)).toContain('S-0011');
      expect(text(el)).toContain('still owes TSH 200,000');
      expect(text(el)).toContain('S-0012');
      expect(text(el)).toContain('still owes TSH 60,000');
      expect(byTestId(el, 'pay-pick-13')).toBeNull();
    });

    it('ticking a sale fills in what it owes, and the payment is sent with its allocations', async () => {
      const { h, fixture, el } = await openPay();

      (byTestId(el, 'pay-pick-12') as HTMLInputElement).click();
      await settle(fixture);
      expect((byTestId(el, 'pay-amount-12') as HTMLInputElement).value).toBe('60,000');
      type(el, '[data-testid="pay-amount-12"]', '25000');
      type(el, '[data-testid="pay-reference"]', 'MP123');
      const method = byTestId(el, 'pay-method') as HTMLSelectElement;
      method.value = 'mobile_money';
      method.dispatchEvent(new Event('change', { bubbles: true }));
      await settle(fixture);
      expect(text(byTestId(el, 'pay-total')!)).toBe('Total received: TSH 25,000');
      click(el, 'pay-save');

      const req = h.http.expectOne({ method: 'POST', url: `${API}/inventory/payments` });
      expect(req.request.body).toEqual({ customer_id: 1, amount: 25000, method: 'mobile_money', reference: 'MP123', allocations: [{ sale_id: 12, amount: 25000 }] });
      req.flush({ data: {} });
      await settle(fixture);
      h.http.expectOne({ method: 'GET', url: CUSTOMERS }).flush({ data: ROWS });
      h.http.expectOne({ method: 'GET', url: `${API}/inventory/credit/debtors-ageing` }).flush(AGEING);
    });

    it('asks to tick a sale first, and refuses more than a sale owes', async () => {
      const { h, fixture, el } = await openPay();

      click(el, 'pay-save');
      await settle(fixture);
      expect(text(byTestId(el, 'pay-error')!)).toContain('Tick at least one sale');

      (byTestId(el, 'pay-pick-12') as HTMLInputElement).click();
      await settle(fixture);
      type(el, '[data-testid="pay-amount-12"]', '90000');
      await settle(fixture);
      click(el, 'pay-save');
      await settle(fixture);
      expect(text(byTestId(el, 'pay-error')!)).toContain('S-0012 owes only TSH 60,000');
      h.http.expectNone({ method: 'POST', url: `${API}/inventory/payments` });
    });

    it('says so when the customer has no unpaid sale', async () => {
      const { h, fixture, el } = await open(SALES_OFFICER);

      click(el, 'cr-pay-1');
      h.http.expectOne((r) => r.url === `${CUSTOMERS}/1/statement`).flush({ data: { ...STATEMENT.data, sales: [STATEMENT.data.sales[2]] } });
      await settle(fixture);

      expect(text(byTestId(el, 'pay-none')!)).toContain('no unpaid sales');
    });
  });
});
