import { describe, expect, it } from 'vitest';

import { TestBed } from '@angular/core/testing';

import { byTestId, configure, settle, type } from '../../testing';
import { MoneyPage, periodRange, readProfitLoss } from './money';

describe('money page', () => {
  const wed = new Date(2026, 10, 11); // Wednesday 11 Nov 2026

  it('gives the same periods as the phone (weeks run Monday to Sunday)', () => {
    expect(periodRange('today', wed)).toEqual(['2026-11-11', '2026-11-11']);
    expect(periodRange('yesterday', wed)).toEqual(['2026-11-10', '2026-11-10']);
    expect(periodRange('last7', wed)).toEqual(['2026-11-05', '2026-11-11']);
    expect(periodRange('thisWeek', wed)).toEqual(['2026-11-09', '2026-11-11']);
    expect(periodRange('lastWeek', wed)).toEqual(['2026-11-02', '2026-11-08']);
    expect(periodRange('thisMonth', wed)).toEqual(['2026-11-01', '2026-11-11']);
    expect(periodRange('lastMonth', wed)).toEqual(['2026-10-01', '2026-10-31']);
    expect(periodRange('thisYear', wed)).toEqual(['2026-01-01', '2026-11-11']);
    expect(periodRange('custom', wed, '2026-11-08', '2026-11-03')).toEqual(['2026-11-03', '2026-11-08']);
  });

  it('reads the server answer, leaving out nothing the phone shows', () => {
    const d = readProfitLoss({
      revenue: '100', net_profit: 40, profit_hidden: false,
      expenses_by_category: [{ category: 'rent', total: 30 }],
      collections: [{ method: 'cash', amount: 60 }],
      cancelled: { count: 2, total: 9 },
      vat: { total: 5, by_rate: [{ rate: 18, taxable: 28, vat: 5 }] },
    });
    expect(d.revenue).toBe(100);
    expect(d.netProfit).toBe(40);
    expect(d.expensesByCategory).toEqual([{ category: 'rent', total: 30 }]);
    expect(d.cancelledCount).toBe(2);
    expect(d.vatByRate[0].vat).toBe(5);
    expect(readProfitLoss({}).profitHidden).toBe(false);
  });
});

describe('money page layout and dates', () => {
  const open = async () => {
    const h = configure({ services: ['salon'] });
    const fixture = TestBed.createComponent(MoneyPage);
    fixture.detectChanges();
    const first = h.http.expectOne((r) => r.url.endsWith('/inventory/salon/profit-loss'));
    first.flush({ data: { revenue: 100, collections: [], expenses_by_category: [] } });
    await settle(fixture);
    return { h, fixture, el: fixture.nativeElement as HTMLElement, first };
  };

  it('puts the sections in ONE card told apart by lines, and the period is chosen with dates', async () => {
    const { el } = await open();

    expect(byTestId(el, 'pl-joined')!.querySelectorAll(':scope > section.ph-sec').length).toBeGreaterThanOrEqual(2);
    expect(el.querySelectorAll('section.glass').length).toBe(0);
    expect(el.querySelectorAll('.pl-chips .pill-tab').length).toBe(0);
    expect((byTestId(el, 'pl-from') as HTMLInputElement).type).toBe('date');
    expect((byTestId(el, 'pl-to') as HTMLInputElement).type).toBe('date');
  });

  it('starts on this month: the first day of the month to today', async () => {
    const { el, first } = await open();
    const today = new Date();
    const pad = (n: number) => String(n).padStart(2, '0');

    expect((byTestId(el, 'pl-from') as HTMLInputElement).value).toBe(`${today.getFullYear()}-${pad(today.getMonth() + 1)}-01`);
    expect(first.request.params.get('from')).toBe(`${today.getFullYear()}-${pad(today.getMonth() + 1)}-01`);
  });

  it('the report follows when a date is written, with the two dates sent', async () => {
    const { h, fixture, el } = await open();

    type(el, '[data-testid=pl-from]', '2026-10-01');
    type(el, '[data-testid=pl-to]', '2026-10-31');
    await settle(fixture);

    const asked = h.http.match((r) => r.url.endsWith('/inventory/salon/profit-loss'));
    const last = asked[asked.length - 1];
    expect(last.request.params.get('from')).toBe('2026-10-01');
    expect(last.request.params.get('to')).toBe('2026-10-31');
    asked.forEach((r) => r.flush({ data: {} }));
  });

  it('a quick pick fills in the two dates', async () => {
    const { h, fixture, el } = await open();
    const quick = byTestId(el, 'pl-quick') as HTMLSelectElement;

    quick.value = 'today';
    quick.dispatchEvent(new Event('change', { bubbles: true }));
    await settle(fixture);

    const day = (byTestId(el, 'pl-from') as HTMLInputElement).value;
    expect((byTestId(el, 'pl-to') as HTMLInputElement).value).toBe(day);
    h.http.match((r) => r.url.endsWith('/inventory/salon/profit-loss')).forEach((r) => r.flush({ data: {} }));
  });
});
