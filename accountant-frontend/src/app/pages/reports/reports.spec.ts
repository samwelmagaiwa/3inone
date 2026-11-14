import { describe, expect, it } from 'vitest';

import { TestBed } from '@angular/core/testing';

import { byTestId, configure, settle } from '../../testing';
import { ReportsPage, readSalonReport, reportRange } from './reports';

describe('reports page', () => {
  const wed = new Date(2026, 10, 11);

  it('gives the phone\'s four periods', () => {
    expect(reportRange('today', wed)).toEqual(['2026-11-11', '2026-11-11']);
    expect(reportRange('week', wed)).toEqual(['2026-11-09', '2026-11-11']);
    expect(reportRange('month', wed)).toEqual(['2026-11-01', '2026-11-11']);
    expect(reportRange('year', wed)).toEqual(['2026-01-01', '2026-11-11']);
  });

  it('reads every part of the report, and a missing part as empty', () => {
    const r = readSalonReport({
      profit_hidden: true,
      summary: { revenue: 100 },
      by_service: [{ name: 'Braids', times: 3, revenue: 90, commission: 5, materials_cost: 2, profit: 83 }],
      by_method: [{ method: 'cash', amount: 60 }],
      owed: { total: 40, list: [{ client: 'Asha', days: 12, due: 40 }] },
      clients: { top_spenders: [{ name: 'Neema', visits: 4, spent: 200 }], active: 7 },
      stock: { items: 5 },
    });
    expect(r.hidden).toBe(true);
    expect(r.byService[0]).toEqual({ name: 'Braids', times: 3, revenue: 90, commission: 5, materials: 2, profit: 83 });
    expect(r.owedTotal).toBe(40);
    expect(r.owed[0].client).toBe('Asha');
    expect(r.topSpenders[0].spent).toBe(200);
    expect(readSalonReport({}).byBranch).toEqual([]);
  });
});

describe('reports page layout', () => {
  it('puts every section of the report in ONE card, told apart by lines, not in a card each', async () => {
    const h = configure({ services: ['salon'] });
    const fixture = TestBed.createComponent(ReportsPage);
    fixture.detectChanges();
    h.http.expectOne((r) => r.url.endsWith('/inventory/salon/reports')).flush({ data: { summary: { revenue: 100 }, by_service: [], by_method: [], owed: { total: 0, list: [] }, clients: {}, stock: {} } });
    await settle(fixture);
    const el = fixture.nativeElement as HTMLElement;

    const joined = byTestId(el, 'rp-joined')!;
    expect(joined.classList.contains('ph-card')).toBe(true);
    expect(joined.querySelectorAll(':scope > section.ph-sec').length).toBeGreaterThanOrEqual(8);
    expect(el.querySelectorAll('section.ph-card').length).toBe(0);
  });
});
