import { describe, expect, it } from 'vitest';

import { readStylistReport } from './stylists';

describe('stylists page', () => {
  it('reads the report: totals, each stylist, the target, and the nobody-named line', () => {
    const r = readStylistReport({
      sees_everyone: true,
      totals: { services: 9, revenue: 500000, commission: 20000, visits: 6, avg_ticket: 83333, previous: { revenue: 400000 }, change: { revenue: 25 } },
      stylists: [
        { staff_id: 4, name: 'Neema', services: 6, revenue: 350000, visits: 4, clients: 4, rank: 1, share: 70, target: { amount: 400000, percent: 87.5, pace: 'ahead' } },
        { staff_id: null, name: '', services: 3, revenue: 150000, visits: 2, clients: 2 },
      ],
    });
    expect(r.revenue).toBe(500000);
    expect(r.revenueChange).toBe(25);
    expect(r.previousRevenue).toBe(400000);
    expect(r.seesEveryone).toBe(true);
    expect(r.stylists[0].target).toEqual({ amount: 400000, percent: 87.5, pace: 'ahead' });
    expect(r.stylists[0].staffId).toBe('4');
    expect(r.stylists[1].staffId).toBeNull();
    expect(r.stylists[1].target).toBeNull();
    expect(r.stylists[1].returnRate).toBeNull();
  });

  it('an empty answer is an empty report', () => {
    const r = readStylistReport({});
    expect(r.stylists).toEqual([]);
    expect(r.revenueChange).toBeNull();
  });
});
