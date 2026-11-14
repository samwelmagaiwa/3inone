import { describe, expect, it } from 'vitest';

import { cashRange, readCashbook } from './cashbook';

describe('cashbook page', () => {
  it('reads the three places day by day with the counts, and the owner moves', () => {
    const b = readCashbook({
      places: {
        cash: { opening: 100, in: 50, out: 20, closing: 130, days: [{ date: '2026-11-10', in: 50, out: 20, closing: 130, count: { counted: 120, difference: -10 } }, { date: '2026-11-11', in: 0, out: 0, closing: 130 }] },
      },
      moves: [{ id: 3, kind: 'owner_deposit', method: 'cash', moved_on: '2026-11-10', note: 'float', amount: 100 }],
    });
    expect(b.places.map((p) => p.place)).toEqual(['cash', 'mobile', 'bank']);
    expect(b.places[0].closing).toBe(130);
    expect(b.places[0].days[0]).toMatchObject({ counted: 120, difference: -10 });
    expect(b.places[0].days[1].counted).toBeNull();
    expect(b.places[1].closing).toBe(0);
    expect(b.moves[0]).toEqual({ id: 3, kind: 'owner_deposit', method: 'cash', movedOn: '2026-11-10', note: 'float', amount: 100 });
  });

  it('gives today, this month and last month', () => {
    const d = new Date(2026, 10, 11);
    expect(cashRange('today', d)).toEqual(['2026-11-11', '2026-11-11']);
    expect(cashRange('month', d)).toEqual(['2026-11-01', '2026-11-11']);
    expect(cashRange('last', d)).toEqual(['2026-10-01', '2026-10-31']);
  });
});
