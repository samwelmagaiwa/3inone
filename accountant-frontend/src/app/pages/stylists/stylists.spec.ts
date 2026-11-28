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

describe('stylists page on screen', () => {
  it('shows every stylist as a row of one grid-lines table, with a total row, under the pinned figure cards', async () => {
    const { TestBed } = await import('@angular/core/testing');
    const { configure, settle, byTestId, text } = await import('../../testing');
    const { environment } = await import('../../../environments/environment');
    const { StylistsPage } = await import('./stylists');
    const h = configure({ role: 'admin', services: ['salon'] });
    const fixture = TestBed.createComponent(StylistsPage);
    fixture.detectChanges();
    h.http.expectOne((r) => r.url === `${environment.apiUrl}/inventory/salon/stylists`).flush({
      data: {
        sees_everyone: true,
        totals: { services: 13, revenue: 503000, commission: 21800, visits: 9, avg_ticket: 55889, previous: { revenue: 1495501 }, change: { revenue: -66 } },
        stylists: [
          { staff_id: 2, name: 'ivan samwel', services: 6, revenue: 285000, visits: 4, clients: 2, avg_ticket: 71250, return_rate: 100, share: 57, rank: 1 },
          { staff_id: 1, name: 'samii', services: 7, revenue: 218000, visits: 5, clients: 3, avg_ticket: 43600, return_rate: 100, share: 43, rank: 2, commission: 21800 },
        ],
      },
    });
    await settle(fixture);
    const el = fixture.nativeElement as HTMLElement;
    expect(byTestId(el, 'st-pin')?.querySelector('[data-testid="st-tiles"]')).not.toBeNull();
    const rows = el.querySelectorAll('[data-testid="st-table"] tbody tr');
    expect(rows.length).toBe(2);
    expect(text(rows[0] as HTMLElement)).toContain('ivan samwel');
    expect(text(rows[0] as HTMLElement)).toContain('71,250');
    expect(text(rows[1] as HTMLElement)).toContain('21,800');
    expect(text(byTestId(el, 'st-total') as HTMLElement)).toContain('503,000');
  });
});
