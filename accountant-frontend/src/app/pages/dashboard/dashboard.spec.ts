import { TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';

import { DashboardPage } from './dashboard';
import { environment } from '../../../environments/environment';
import { monthKey } from '../../core/format';

const cmp = (now: number, before: number, direction: 'up' | 'down' | 'same', percent: number | null, good = true) => ({ now, before, change: now - before, percent, direction, good });

const report = (month: string, direction: 'up' | 'down' | 'same' = 'up') => ({
  month,
  is_current: true,
  is_future: false,
  figures: { sales: 300000, sales_count: 12, cost_of_goods: 150000, gross_profit: 150000, margin_percent: 50, expenses: 30000, personal_spending: 0, write_offs: 0, net_profit: 120000, expenses_by_category: [] },
  previous: { month: '2026-10', like_for_like: true },
  compare: { sales: cmp(300000, 200000, 'up', 50), gross_profit: cmp(150000, 100000, 'up', 50), expenses: cmp(30000, 20000, 'up', 50, false), net_profit: cmp(120000, 80000, direction, 50) },
  overall: { direction, percent: 50 },
  position: { stock_value: 900000, receivable: 150000, payable: 50000, capital: 1000000 },
  capital_change: null,
  target: { profit_target: 300000, profit: 120000, progress_percent: 40, left: 180000, over_by: 0, expected_by_today: 200000, days_left: 10, status: 'behind' },
  top_products: [],
  debtors: [],
});

async function open() {
  TestBed.configureTestingModule({ providers: [provideHttpClient(), provideHttpClientTesting()] });
  const ctrl = TestBed.inject(HttpTestingController);
  const fixture = TestBed.createComponent(DashboardPage);
  fixture.detectChanges();
  return { fixture, ctrl, el: fixture.nativeElement as HTMLElement };
}

describe('dashboard', () => {
  it('asks for this month and shows the headline, the target and the figures', async () => {
    const { fixture, ctrl, el } = await open();
    const month = monthKey(new Date());

    ctrl.expectOne(`${environment.apiUrl}/inventory/monthly-report?month=${month}`).flush({ status: 'success', message: 'ok', data: report(month) });
    fixture.detectChanges();

    expect(el.querySelector('[data-testid=headline]')?.textContent).toContain('Better than October 2026 50%');
    expect(el.querySelector('[data-testid=target]')?.textContent).toContain('TSH 120,000');
    expect(el.textContent).toContain('TSH 300,000');
    expect(el.textContent).toContain('Capital');
    expect(el.textContent).toContain('TSH 1,000,000');
  });

  it('the arrows load the month before', async () => {
    const { fixture, ctrl, el } = await open();
    const month = monthKey(new Date());
    ctrl.expectOne(`${environment.apiUrl}/inventory/monthly-report?month=${month}`).flush({ data: report(month) });
    fixture.detectChanges();

    (el.querySelector('[aria-label="Previous month"]') as HTMLButtonElement).click();
    const [y, m] = month.split('-').map(Number);
    const before = monthKey(new Date(y, m - 2, 1));
    ctrl.expectOne(`${environment.apiUrl}/inventory/monthly-report?month=${before}`).flush({ data: report(before) });
    fixture.detectChanges();

    expect(el.querySelector('[data-testid=month-title]')?.textContent).toMatch(/\d{4}/);
  });

  it('a failed load says why and offers to try again', async () => {
    const { fixture, ctrl, el } = await open();
    const month = monthKey(new Date());

    ctrl.expectOne(`${environment.apiUrl}/inventory/monthly-report?month=${month}`).flush({ message: 'Mwezi si sahihi' }, { status: 422, statusText: 'Unprocessable' });
    fixture.detectChanges();

    expect(el.querySelector('[role=alert]')?.textContent).toContain('Mwezi si sahihi');
    expect(el.textContent).toContain('Try again');
  });
});
