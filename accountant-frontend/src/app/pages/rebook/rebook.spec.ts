import { describe, expect, it } from 'vitest';

import { clientStatus, readRebook } from './rebook';

describe('come back page', () => {
  it('reads the settings and the clients due', () => {
    const v = readRebook({
      settings: { rebook_enabled: 1, rebook_weeks: 6, max_weeks: 20 },
      clients: [{ customer_id: 9, name: 'Asha', phone: '0754', visit_on: '2026-10-01', weeks_waited: 6, service: 'Braids', sent: false, can_text: true }],
    });
    expect(v.enabled).toBe(true);
    expect(v.weeks).toBe(6);
    expect(v.maxWeeks).toBe(20);
    expect(v.clients[0]).toMatchObject({ customerId: 9, name: 'Asha', weeksWaited: 6, canText: true, sent: false, skipReason: null });
    expect(readRebook({}).weeks).toBe(4);
    expect(readRebook({}).maxWeeks).toBe(52);
  });

  it('says what will happen to each client', () => {
    const base = { customerId: 1, name: '', phone: '', visitOn: '', weeksWaited: 4, service: '', sent: false, canText: true, skipReason: null };
    expect(clientStatus({ ...base, canText: false, skipReason: 'opted_out' }, true).key).toBe('rb.opted.out');
    expect(clientStatus({ ...base, canText: false }, true).key).toBe('rb.no.phone');
    expect(clientStatus({ ...base, sent: true }, true).key).toBe('rb.texted');
    expect(clientStatus(base, false).key).toBe('rb.off');
    expect(clientStatus(base, true).key).toBe('rb.will');
  });
});
