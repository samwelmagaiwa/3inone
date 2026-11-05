import { TestBed } from '@angular/core/testing';

import { environment } from '../../../environments/environment';
import { byTestId, configure, settle, text } from '../../testing';
import { SalonHomeComponent } from './salon-home';

const API = environment.apiUrl;

const period = (revenue: number, sales: number, extra: Record<string, unknown> = {}) => ({ revenue, expenses: 0, clients: sales, sales, ...extra });

const OVERVIEW = {
  periods: { today: period(0, 0), week: period(209000, 6), month: period(404000, 11), year: period(2310601, 90) },
  month: { collections: [{ method: 'cash', amount: 300000 }, { method: 'mpesa', amount: 104000 }], outstanding: 75000 },
  top_services: [{ name: 'Knotless Braids', times: 4, revenue: 150000 }, { name: 'Haircut', times: 9, revenue: 90000 }],
  top_staff: [{ staff_id: '1', name: 'Neema', revenue: 200000 }, { staff_id: '2', name: '', revenue: 50000 }],
  bookings: { today: 2, upcoming: 5 },
};

const ACCOUNTANT = ['inv_view_products', 'inv_create_sales', 'inv_view_credit', 'inv_view_cash', 'inv_view_expenses', 'inv_salon_money'];

async function open(answers: { overview?: unknown | 'deny'; permissions?: string[] } = {}) {
  const h = configure({ name: 'ivan samwel', roleLabel: 'Accountant', permissions: answers.permissions ?? ACCOUNTANT, services: ['salon'] });
  const fixture = TestBed.createComponent(SalonHomeComponent);
  fixture.detectChanges();

  h.http.expectOne(`${API}/inventory/kpis`).flush({ data: { today: { total: 50000, cash: 30000, expenses: 5000 }, outstanding_debt: 540000 } });
  const ov = h.http.expectOne(`${API}/inventory/salon/overview`);
  if (answers.overview === 'deny') ov.flush({ message: 'no' }, { status: 403, statusText: 'Forbidden' });
  else ov.flush({ data: answers.overview ?? OVERVIEW });
  h.http.expectOne((r) => r.url === `${API}/inventory/sales/summary`).flush({ data: { count: 3, total: 100000, paid: 100000, debt: 0 } });
  for (const [key, total] of [['1', 12], ['0', 8]] as const) {
    h.http.expectOne((r) => r.url === `${API}/inventory/products` && r.params.get('is_service') === key && !r.params.has('low_stock')).flush({ data: [], meta: { total } });
  }
  h.http.expectOne((r) => r.url === `${API}/inventory/products` && r.params.get('low_stock') === '1').flush({ data: [], meta: { total: 3 } });
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

describe('the salon home', () => {
  it('welcomes the person and offers the places they may go', async () => {
    const { el } = await open();
    expect(text(byTestId(el, 'home-welcome')!)).toContain('Welcome, ivan samwel');
    expect(text(byTestId(el, 'home-welcome')!)).toContain('Accountant');
    expect(byTestId(el, 'home-link-/sales/new')).not.toBeNull();
    expect(byTestId(el, 'home-link-/customers')).not.toBeNull();
  });

  it('puts who is here, today and the quick links in one section, the links in one row', async () => {
    const { el } = await open();
    const welcome = byTestId(el, 'home-welcome')!;

    expect(welcome.contains(byTestId(el, 'home-today')!)).toBe(true);
    expect(welcome.contains(byTestId(el, 'home-today-sales')!)).toBe(true);
    const links = byTestId(el, 'home-links')!;
    expect(welcome.contains(links)).toBe(true);
    expect(links.querySelectorAll('a').length).toBeGreaterThan(1);
    expect(getComputedStyle(links).flexWrap).toBe('nowrap');
  });

  it('puts the best services and the money received in one section with the figures of the month', async () => {
    const { el } = await open();
    const summary = byTestId(el, 'home-summary')!;

    expect(summary.contains(byTestId(el, 'home-top-services')!)).toBe(true);
    expect(summary.contains(byTestId(el, 'home-collections')!)).toBe(true);
    expect(text(summary)).toContain('Knotless Braids');
    expect(text(summary)).toContain('TSH 300,000');
  });

  it("shows today's sales and number of sales, and how today stands against yesterday", async () => {
    const { el } = await open();
    expect(text(byTestId(el, 'home-today-sales')!)).toBe('TSH 50,000');
    expect(byTestId(el, 'home-today-count')).not.toBeNull();
    expect(text(byTestId(el, 'home-vs')!)).toBe('↓ 50%');
  });

  it('shows the cash, credit and expenses of the day, the catalogue and the goods running low', async () => {
    const { el } = await open();
    expect(text(byTestId(el, 'home-cash')!)).toContain('TSH 30,000');
    expect(text(byTestId(el, 'home-credit')!)).toContain('TSH 540,000');
    expect(text(byTestId(el, 'home-expenses')!)).toContain('TSH 5,000');
    expect(text(byTestId(el, 'home-catalogue')!)).toContain('12 services');
    expect(text(byTestId(el, 'home-catalogue')!)).toContain('8 goods');
    expect(text(byTestId(el, 'home-low')!)).toContain('3 items');
  });

  it('shows the business overview: the four periods, the diary, clients and what is owed', async () => {
    const { el } = await open();
    expect(text(byTestId(el, 'ov-home.week')!)).toContain('TSH 209,000');
    expect(text(byTestId(el, 'ov-home.year')!)).toContain('TSH 2,310,601');
    expect(text(byTestId(el, 'ov-bookings-today')!)).toContain('2');
    expect(text(byTestId(el, 'ov-bookings-upcoming')!)).toContain('5');
    expect(text(byTestId(el, 'ov-clients')!)).toContain('11');
    expect(text(byTestId(el, 'ov-outstanding')!)).toContain('TSH 75,000');
  });

  it('keeps profit out when the server did not send it', async () => {
    const { el } = await open();
    expect(text(byTestId(el, 'home-overview')!)).not.toContain('Profit');
  });

  it('shows the best stylists and services and the money received', async () => {
    const { el } = await open();
    expect(text(byTestId(el, 'ov-staff-0')!)).toContain('Neema');
    expect(text(byTestId(el, 'ov-staff-1')!)).toContain('No stylist named');
    expect(text(byTestId(el, 'ov-service-0')!)).toContain('Knotless Braids');
    expect(text(byTestId(el, 'ov-service-0')!)).toContain('4 times');
    expect(text(byTestId(el, 'ov-collect-mpesa')!)).toContain('TSH 104,000');
  });

  it('leaves the overview out when the server refuses it, and keeps the rest', async () => {
    const { el } = await open({ overview: 'deny' });
    expect(byTestId(el, 'home-overview')).toBeNull();
    expect(byTestId(el, 'home-cash')).not.toBeNull();
  });

  it('shows no cash, credit or expenses card to someone who may not see them', async () => {
    const { el } = await open({ permissions: ['inv_view_products', 'inv_create_sales'] });
    expect(byTestId(el, 'home-cash')).toBeNull();
    expect(byTestId(el, 'home-credit')).toBeNull();
    expect(byTestId(el, 'home-expenses')).toBeNull();
  });
});
