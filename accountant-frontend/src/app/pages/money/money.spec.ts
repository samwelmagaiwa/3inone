import { describe, expect, it } from 'vitest';

import { periodRange, readProfitLoss } from './money';

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
