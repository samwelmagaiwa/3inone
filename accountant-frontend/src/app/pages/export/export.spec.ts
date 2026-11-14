import { describe, expect, it } from 'vitest';

import { EXPORT_RIGHTS, EXPORT_TYPES, exportRange, exportUrl } from './export';

describe('export page', () => {
  it('asks for the same file the phone does', () => {
    const url = exportUrl('profit-loss', 'csv', 'sw', '2026-11-01', '2026-11-14');
    expect(url).toContain('/inventory/salon/export/profit-loss?format=csv&lang=sw&from=2026-11-01&to=2026-11-14&month=2026-11');
    expect(exportUrl('sales', 'pdf', 'en', '2026-11-14', '2026-11-14')).toContain('lang=en');
  });

  it('gives today, this month and last month', () => {
    const d = new Date(2026, 10, 11);
    expect(exportRange('today', d)).toEqual(['2026-11-11', '2026-11-11']);
    expect(exportRange('month', d)).toEqual(['2026-11-01', '2026-11-11']);
    expect(exportRange('last', d)).toEqual(['2026-10-01', '2026-10-31']);
  });

  it('every report has the right it needs', () => {
    for (const t of EXPORT_TYPES) expect(EXPORT_RIGHTS[t]).toMatch(/^inv_/);
  });
});
