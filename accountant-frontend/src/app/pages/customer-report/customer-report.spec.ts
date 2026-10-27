import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, convertToParamMap } from '@angular/router';

import { environment } from '../../../environments/environment';
import { byTestId, configure, settle, text } from '../../testing';
import { CustomerReportPage } from './customer-report';

const API = environment.apiUrl;
const URL = `${API}/inventory/credit/customers/1/report`;

const report = (over: Record<string, unknown> = {}) => ({
  data: {
    customer: { id: 1, name: 'Mama Neema Joseph', phone: '0711000001', address: 'Kariakoo', credit_limit: 500000 },
    from: '2026-11-01', to: '2026-11-25', group: 'week', profit_visible: true,
    totals: { purchases: 3, sales: 6000000, paid: 5000000, unpaid_in_period: 1000000, cost: 4000000, profit: 2000000, margin_percent: 33.3, average_purchase: 2000000 },
    debt: { owes_now: 1090000, from_sales: 1000000, from_before_app: 90000 },
    lifetime: { purchases: 9, sales: 12000000, profit: 4000000, first_purchase: '2026-01-05 09:00', last_purchase: '2026-11-20 09:00' },
    by_period: [
      { period: '2026-11-02', purchases: 2, sales: 4000000, paid: 4000000, profit: 1500000 },
      { period: '2026-11-16', purchases: 1, sales: 2000000, paid: 1000000, profit: 500000 },
    ],
    top_products: [{ name: 'Soda', qty: 40, sales: 4000000, profit: 1600000 }],
    recent_sales: [{ id: 7, number: 'S-0007', at: '2026-11-20 09:00', total: 2000000, paid: 1000000, status: 'partial' }],
    ...over,
  },
});

async function open(permissions: string[] = ['inv_view_credit', 'inv_view_reports'], answer = report()) {
  const h = configure({ permissions }, [{ provide: ActivatedRoute, useValue: { snapshot: { paramMap: convertToParamMap({ id: '1' }) } } }]);
  const fixture = TestBed.createComponent(CustomerReportPage);
  fixture.detectChanges();
  h.http.expectOne((r) => r.url === URL && r.params.get('group') === 'week').flush(answer);
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

const click = (el: HTMLElement, id: string) => (byTestId(el, id) as HTMLElement).click();

describe('a customer\'s report', () => {
  it('starts on this month by week and shows what was bought, paid, the profit and what is owed, with commas', async () => {
    const { el } = await open();

    expect(text(byTestId(el, 'crr-name')!)).toBe('Mama Neema Joseph');
    expect(text(byTestId(el, 'crr-sales')!)).toBe('TSH 6,000,000');
    expect(text(byTestId(el, 'crr-count')!)).toContain('3 purchases');
    expect(text(byTestId(el, 'crr-paid')!)).toBe('TSH 5,000,000');
    expect(text(byTestId(el, 'crr-profit')!)).toBe('TSH 2,000,000');
    expect(text(byTestId(el, 'crr-owes')!)).toBe('TSH 1,090,000');
    expect(text(el)).toContain('TSH 90,000 from before the app');
  });

  it('shows week by week with the Monday each week starts on, and the goods and latest purchases', async () => {
    const { el } = await open();

    expect(text(byTestId(el, 'crr-row-2026-11-02')!)).toContain('Week of 02/11/2026');
    expect(text(byTestId(el, 'crr-row-2026-11-02')!)).toContain('TSH 4,000,000');
    expect(text(byTestId(el, 'crr-row-2026-11-16')!)).toContain('TSH 2,000,000');
    expect(text(el)).toContain('Soda');
    expect(text(el)).toContain('S-0007');
    expect(text(byTestId(el, 'crr-life-sales')!)).toBe('TSH 12,000,000');
  });

  it('a person who may not see profit gets no profit column or figure anywhere', async () => {
    const answer = report({
      profit_visible: false,
      totals: { purchases: 3, sales: 6000000, paid: 5000000, unpaid_in_period: 1000000, cost: null, profit: null, margin_percent: null, average_purchase: 2000000 },
      lifetime: { purchases: 9, sales: 12000000, profit: null, first_purchase: null, last_purchase: null },
      by_period: [{ period: '2026-11-02', purchases: 2, sales: 4000000, paid: 4000000, profit: null }],
      top_products: [{ name: 'Soda', qty: 40, sales: 4000000, profit: null }],
    });
    const { el } = await open(['inv_view_credit'], answer);

    expect(byTestId(el, 'crr-profit')).toBeNull();
    expect(text(el).toLowerCase()).not.toContain('profit');
    expect(text(byTestId(el, 'crr-owes')!)).toBe('TSH 1,090,000');
  });

  it('choosing a year asks for the year grouped by month, and the grouping can be changed', async () => {
    const { h, fixture, el } = await open();

    click(el, 'crr-period-year');
    const year = h.http.expectOne((r) => r.url === URL && r.params.get('group') === 'month');
    expect(year.request.params.get('from')).toMatch(/^\d{4}-01-01$/);
    year.flush(report({ group: 'month', by_period: [{ period: '2026-11', purchases: 3, sales: 6000000, paid: 5000000, profit: 2000000 }] }));
    await settle(fixture);
    expect(text(byTestId(el, 'crr-row-2026-11')!)).toContain('November 2026');

    click(el, 'crr-group-day');
    h.http.expectOne((r) => r.url === URL && r.params.get('group') === 'day').flush(report({ group: 'day', by_period: [{ period: '2026-11-03', purchases: 1, sales: 1000, paid: 1000, profit: 400 }] }));
    await settle(fixture);
    expect(text(byTestId(el, 'crr-row-2026-11-03')!)).toContain('03/11/2026');
  });

  it('says plainly when nothing was bought in the days chosen', async () => {
    const { el } = await open(['inv_view_credit', 'inv_view_reports'], report({ by_period: [], top_products: [], recent_sales: [] }));

    expect(byTestId(el, 'crr-none')).not.toBeNull();
  });

  it('shows the server message when it refuses', async () => {
    const h = configure({ permissions: ['inv_view_credit'] }, [{ provide: ActivatedRoute, useValue: { snapshot: { paramMap: convertToParamMap({ id: '1' }) } } }]);
    const fixture = TestBed.createComponent(CustomerReportPage);
    fixture.detectChanges();
    h.http.expectOne((r) => r.url === URL).flush({ message: 'Not found' }, { status: 404, statusText: 'x' });
    await settle(fixture);

    expect(text(fixture.nativeElement as HTMLElement)).toContain('Not found');
  });
});
