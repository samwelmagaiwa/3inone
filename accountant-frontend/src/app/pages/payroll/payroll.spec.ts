import { describe, expect, it } from 'vitest';

import { readPayouts, readPayroll } from './payroll';

describe('payroll page', () => {
  it('reads the totals and each person, and the payments', () => {
    const r = readPayroll({
      totals: { salary: 800000, commission_earned: 120000, owed: 300000 },
      staff: [{ staff_id: 4, name: 'Rehema', salary: 400000, commission_earned: 60000, salary_paid: 200000, commission_paid: 0, advances: 50000, owed: 210000 }],
    });
    expect(r.salary).toBe(800000);
    expect(r.owed).toBe(300000);
    expect(r.staff[0]).toEqual({ staffId: '4', name: 'Rehema', salary: 400000, commissionEarned: 60000, salaryPaid: 200000, commissionPaid: 0, advances: 50000, owed: 210000 });
    expect(readPayroll({}).staff).toEqual([]);

    const p = readPayouts([{ id: 9, staff_id: 4, staff_name: 'Rehema', kind: 'advance', amount: '50000', paid_on: '2026-11-10', method: '', note: null }]);
    expect(p[0]).toMatchObject({ id: 9, staffId: '4', kind: 'advance', amount: 50000, method: 'cash', note: '' });
    expect(readPayouts(undefined)).toEqual([]);
  });
});
