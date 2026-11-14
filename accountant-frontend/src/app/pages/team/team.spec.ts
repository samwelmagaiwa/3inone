import { describe, expect, it } from 'vitest';

import { hm, hoursText, readAttendance } from './team';

describe('team page', () => {
  it('reads who worked, for how many days and hours, and who is at work now', () => {
    const p = readAttendance({
      staff: [{ staff_id: 5, name: 'Rehema', days: 12, hours: 96.5, at_work: true, records: [{ date: '2026-11-13', clock_in: '2026-11-13 08:55:00', clock_out: null }, { date: '2026-11-12', clock_in: '2026-11-12T09:00:00', clock_out: '2026-11-12T17:30:00', hours: 8.5 }] }],
    });
    expect(p).toHaveLength(1);
    expect(p[0]).toMatchObject({ staffId: '5', name: 'Rehema', days: 12, hours: 96.5, atWork: true });
    expect(p[0].records[0].clockOut).toBeNull();
    expect(p[0].records[0].hours).toBeNull();
    expect(hm(p[0].records[0].clockIn)).toBe('08:55');
    expect(hm(p[0].records[1].clockOut)).toBe('17:30');
    expect(readAttendance({})).toEqual([]);
  });

  it('writes hours as the phone does', () => {
    expect(hoursText(8)).toBe('8');
    expect(hoursText(7.5)).toBe('7.5');
  });
});
