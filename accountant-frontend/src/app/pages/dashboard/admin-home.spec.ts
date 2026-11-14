import { TestBed } from '@angular/core/testing';
import { TestRequest } from '@angular/common/http/testing';

import { environment } from '../../../environments/environment';
import { byTestId, configure, settle, text } from '../../testing';
import { AdminHomeComponent } from './admin-home';
import { DashboardEntryPage } from './dashboard-entry';

const API = environment.apiUrl;

const RIGHTS = ['inv_view_products', 'inv_create_sales', 'inv_view_credit', 'inv_view_cash', 'inv_view_expenses', 'inv_view_reports', 'inv_salon_money', 'inv_salon_profit'];

const period = (revenue: number, sales: number, profit: number | null) => ({ revenue, expenses: 0, ...(profit === null ? {} : { net_profit: profit }), clients: sales, sales });

const OVERVIEW = {
  periods: { today: period(156000, 4, 70000), week: period(612000, 17, 281000), month: period(2404000, 66, 1010000), year: period(12310601, 410, 5100000) },
  month: { collections: [{ method: 'cash', amount: 1300000 }, { method: 'mpesa', amount: 804000 }], outstanding: 75000 },
  top_services: [{ name: 'Knotless Braids', times: 14, revenue: 560000 }, { name: 'Haircut', times: 30, revenue: 300000 }],
  top_staff: [{ staff_id: '1', name: 'Neema', revenue: 900000 }, { staff_id: '2', name: '', revenue: 90000 }],
  bookings: { today: 2, upcoming: 5 },
};

const cmp = (now: number, before: number) => ({ now, before, change: now - before, percent: before ? ((now - before) / before) * 100 : null, direction: now >= before ? 'up' : 'down', good: now >= before });

const REPORT = {
  owner_figures: true, month: '2026-11', is_current: true, is_future: false, days_elapsed: 14, days_in_month: 30,
  figures: { sales: 2404000, sales_count: 66, cost_of_goods: 600000, gross_profit: 1800000, margin_percent: 70, expenses: 790000, personal_spending: 0, write_offs: 0, net_profit: 1010000, expenses_by_category: [] },
  previous: { month: '2026-10', like_for_like: true },
  compare: { sales: cmp(2404000, 2100000), gross_profit: cmp(1800000, 1500000), expenses: cmp(790000, 700000), net_profit: cmp(1010000, 880000) },
  overall: { direction: 'up', percent: 14 }, position: null, capital_change: null,
  target: { profit_target: 2000000, profit: 1010000, progress_percent: 50.5, left: 990000, over_by: 0, expected_by_today: 930000, days_left: 16, status: 'on_track' },
  top_products: [{ name: 'Knotless Braids', qty: 14, sales: 560000, profit: 500000 }, { name: 'Haircut', qty: 30, sales: 300000, profit: 300000 }],
  top_customers: [], slow_stock: [], debtors: [],
};

const SERVICES = [
  { id: 1, name: 'Knotless Braids', sku: 'S1', is_service: true, selling_price: 25000, duration_minutes: 120, quantity: 0, min_stock: 0, unit: 'pcs', status: 'active', cost_price: 0, staff_ids: [], price_options: [] },
  { id: 2, name: 'Haircut', sku: 'S2', is_service: true, selling_price: 10000, duration_minutes: null, quantity: 0, min_stock: 0, unit: 'pcs', status: 'active', cost_price: 0, staff_ids: [], price_options: [] },
];

interface Answers { overview?: unknown | 'deny'; report?: unknown | 'deny' }

/** Answer every request the dashboard makes, by what it asks for. */
function answer(h: ReturnType<typeof configure>, a: Answers = {}) {
  for (const r of h.http.match(() => true) as TestRequest[]) {
    const url = r.request.url;
    const p = r.request.params;
    if (url === `${API}/inventory/kpis`) r.flush({ data: { today: { total: 156000, cash: 90000, expenses: 12000 }, outstanding_debt: 1064991 } });
    else if (url === `${API}/inventory/salon/overview`) a.overview === 'deny' ? r.flush({ message: 'no' }, { status: 403, statusText: 'Forbidden' }) : r.flush({ data: a.overview ?? OVERVIEW });
    else if (url === `${API}/inventory/sales/summary`) r.flush({ data: { count: 3, total: 100000, paid: 100000, debt: 0 } });
    else if (url === `${API}/inventory/monthly-report`) a.report === 'deny' ? r.flush({ message: 'no' }, { status: 403, statusText: 'Forbidden' }) : r.flush({ data: a.report ?? REPORT });
    else if (url === `${API}/inventory/sales/monthly-chart`) r.flush({ data: { days: Array.from({ length: 30 }, (_, i) => ({ total: i % 5 === 0 ? 0 : 20000 + i * 1000 })) } });
    else if (url === `${API}/inventory/products`) {
      if (p.get('low_stock') === '1') r.flush({ data: [], meta: { total: 3 } });
      else if (p.has('status')) r.flush({ data: SERVICES, meta: { current_page: 1, last_page: 1, total: 2 } });
      else r.flush({ data: [], meta: { total: p.get('is_service') === '1' ? 12 : 8 } });
    } else r.flush({ data: [] });
  }
}

async function open(permissions = RIGHTS, a: Answers = {}) {
  const h = configure({ role: 'admin', name: 'Mary Owner', permissions, services: ['salon'] });
  const fixture = TestBed.createComponent(AdminHomeComponent);
  fixture.detectChanges();
  answer(h, a);
  await settle(fixture);
  answer(h, a);
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

describe("the business admin's dashboard in a salon", () => {
  it("shows today's sales, how many sales and the profit, against yesterday", async () => {
    const { el } = await open();
    expect(text(byTestId(el, 'ad-sales')!)).toBe('TSH 156,000');
    expect(text(byTestId(el, 'ad-count')!)).toBe('4');
    expect(text(byTestId(el, 'ad-profit')!)).toBe('TSH 70,000');
    expect(text(byTestId(el, 'ad-vs')!)).toBe('↑ 100%');
  });

  it('shows the cash, credit and expenses of the day, the services and goods, and the goods running low', async () => {
    const { el } = await open();
    expect(text(byTestId(el, 'ad-cash')!)).toContain('TSH 90,000');
    expect(text(byTestId(el, 'ad-credit')!)).toContain('TSH 1,064,991');
    expect(text(byTestId(el, 'ad-expenses')!)).toContain('TSH 12,000');
    expect(text(byTestId(el, 'ad-catalogue')!)).toContain('12 services');
    expect(text(byTestId(el, 'ad-catalogue')!)).toContain('8 goods');
    expect(text(byTestId(el, 'ad-low')!)).toContain('3 items');
  });

  it("shows the month's profit against the last month, with the target", async () => {
    const { el } = await open();
    expect(text(byTestId(el, 'ad-month-profit')!)).toBe('TSH 1,010,000');
    expect(text(byTestId(el, 'ad-month-cmp')!)).toContain('15%');
    expect(text(byTestId(el, 'ad-month-cmp')!)).toContain('TSH 880,000');
    expect(text(byTestId(el, 'ad-target')!)).toContain('TSH 2,000,000');
  });

  it('shows the business overview: the four periods with profit, clients, what is owed, the best stylists and services, and the money received, but not the bookings', async () => {
    const { el } = await open();
    expect(text(byTestId(el, 'ad-ov-week')!)).toContain('TSH 612,000');
    expect(text(byTestId(el, 'ad-ov-year')!)).toContain('TSH 5,100,000');
    expect(text(byTestId(el, 'ad-clients')!)).toContain('66');
    expect(text(byTestId(el, 'ad-owed')!)).toContain('TSH 75,000');
    expect(text(byTestId(el, 'ad-staff-0')!)).toContain('Neema');
    expect(text(byTestId(el, 'ad-staff-1')!)).toContain('No stylist named');
    expect(text(byTestId(el, 'ad-service-0')!)).toContain('14 times');
    expect(text(byTestId(el, 'ad-collect-mpesa')!)).toContain('TSH 804,000');
    expect(text(el)).not.toContain('Bookings today');
    expect(text(el)).not.toContain('Coming up');
  });

  it('draws the sales of each day of the month, and the best earners, and lists the services', async () => {
    const { el } = await open();
    expect(el.querySelectorAll('[data-testid=ad-chart] .bar-col').length).toBe(30);
    expect(text(byTestId(el, 'ad-top-0')!)).toContain('Knotless Braids');
    expect(text(byTestId(el, 'ad-top-0')!)).toContain('TSH 500,000');
    expect(text(byTestId(el, 'ad-srv-1')!)).toContain('120 min');
    expect(text(byTestId(el, 'ad-srv-2')!)).toContain('—');
  });

  it('the filter changes the figures: this week, this year, or dates picked', async () => {
    const { h, fixture, el } = await open();
    byTestId(el, 'ad-filter')!.click();
    await settle(fixture);
    expect(byTestId(el, 'ad-sheet')).not.toBeNull();

    byTestId(el, 'ad-opt-week')!.click();
    await settle(fixture);
    expect(byTestId(el, 'ad-sheet')).toBeNull();
    expect(text(byTestId(el, 'ad-sales')!)).toBe('TSH 612,000');
    expect(text(byTestId(el, 'ad-count')!)).toBe('17');
    expect(byTestId(el, 'ad-vs')).toBeNull(); // the bar against yesterday is for today only

    byTestId(el, 'ad-filter')!.click();
    await settle(fixture);
    byTestId(el, 'ad-opt-custom')!.click();
    await settle(fixture);
    const from = byTestId(el, 'ad-from') as HTMLInputElement;
    const to = byTestId(el, 'ad-to') as HTMLInputElement;
    from.value = '2026-10-01';
    from.dispatchEvent(new Event('input'));
    to.value = '2026-10-15';
    to.dispatchEvent(new Event('input'));
    await settle(fixture);
    byTestId(el, 'ad-apply')!.click();
    const req = h.http.expectOne((r) => r.url === `${API}/inventory/sales/summary` && r.params.get('from') === '2026-10-01');
    expect(req.request.params.get('to')).toBe('2026-10-15');
    req.flush({ data: { count: 9, total: 320000, paid: 300000, debt: 20000 } });
    await settle(fixture);
    expect(text(byTestId(el, 'ad-sales')!)).toBe('TSH 320,000');
    expect(text(byTestId(el, 'ad-count')!)).toBe('9');
    expect(byTestId(el, 'ad-profit')).toBeNull(); // dates picked have no profit figure
  });

  it('the month of the chart can be moved back, and asks the server for that month', async () => {
    const { h, fixture, el } = await open();
    const month = new Date().getMonth() + 1;
    if (month === 1) return; // nothing earlier this year to move to
    expect((byTestId(el, 'ad-month-next') as HTMLButtonElement).disabled).toBe(true);
    byTestId(el, 'ad-month-prev')!.click();
    const req = h.http.expectOne((r) => r.url === `${API}/inventory/sales/monthly-chart`);
    expect(req.request.params.get('month')).toBe(String(month - 1));
    req.flush({ data: { days: [{ total: 10000 }, { total: 20000 }] } });
    await settle(fixture);
    expect(el.querySelectorAll('[data-testid=ad-chart] .bar-col').length).toBe(2);
  });

  it('leaves out what the server refuses and keeps the rest', async () => {
    const { el } = await open(RIGHTS, { overview: 'deny', report: 'deny' });
    expect(byTestId(el, 'ad-overview')).toBeNull();
    expect(byTestId(el, 'ad-month')).toBeNull();
    expect(byTestId(el, 'ad-cash')).not.toBeNull();
    expect(text(byTestId(el, 'ad-sales')!)).toBe('TSH 156,000'); // today's total still comes from the till's own figures
  });

  it('shows no cash, credit or expenses to someone who may not see them, and no profit when the server sends none', async () => {
    const noProfit = { ...OVERVIEW, periods: { today: period(156000, 4, null), week: period(612000, 17, null), month: period(2404000, 66, null), year: period(12310601, 410, null) } };
    const { el } = await open(['inv_view_products', 'inv_create_sales'], { overview: noProfit, report: { ...REPORT, owner_figures: false } });
    expect(byTestId(el, 'ad-cash')).toBeNull();
    expect(byTestId(el, 'ad-credit')).toBeNull();
    expect(byTestId(el, 'ad-expenses')).toBeNull();
    expect(byTestId(el, 'ad-profit')).toBeNull();
    expect(byTestId(el, 'ad-month')).toBeNull();
  });
});

describe('which dashboard opens', () => {
  async function entry(role: string) {
    const h = configure({ role, name: 'Someone', permissions: RIGHTS, services: ['salon'] });
    const fixture = TestBed.createComponent(DashboardEntryPage);
    fixture.detectChanges();
    answer(h);
    await settle(fixture);

    return fixture.nativeElement as HTMLElement;
  }

  it("the business admin of a salon gets the phone's dashboard", async () => {
    expect(byTestId(await entry('admin'), 'admin-home')).not.toBeNull();
  });

  it('the accountant gets the dashboard they had', async () => {
    const el = await entry('accountant');
    expect(byTestId(el, 'admin-home')).toBeNull();
    expect(byTestId(el, 'salon-home')).not.toBeNull();
  });
});
