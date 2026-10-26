import { dayLabel, dayOf, monthKey, monthName, offline, parseAmount, serverMessage, shiftMonth, shortMoney, tsh } from './format';

describe('format', () => {
  it('writes money with thousands separators and keeps the sign', () => {
    expect(tsh(45000)).toBe('TSH 45,000');
    expect(tsh(1250000)).toBe('TSH 1,250,000');
    expect(tsh(-2000)).toBe('TSH -2,000');
    expect(tsh(0)).toBe('TSH 0');
  });

  it('shortens money for a headline', () => {
    expect(shortMoney(1250000)).toBe('TSH 1.25M');
    expect(shortMoney(45000)).toBe('TSH 45K');
    expect(shortMoney(9500)).toBe('TSH 9,500');
    expect(shortMoney(-2000000)).toBe('-TSH 2M');
  });

  it('reads an amount typed with commas or spaces, and rejects anything else', () => {
    expect(parseAmount('1,250,000')).toBe(1250000);
    expect(parseAmount(' 350 000 ')).toBe(350000);
    expect(parseAmount('12.5')).toBe(12.5);
    for (const bad of ['', 'abc', '12abc', '-5', '1e5']) expect(parseAmount(bad), bad).toBeNaN();
  });

  it('names and moves months, across a year end too, in either language', () => {
    expect(monthKey(new Date(2026, 0, 15))).toBe('2026-01');
    expect(shiftMonth('2026-01', -1)).toBe('2025-12');
    expect(shiftMonth('2026-12', 1)).toBe('2027-01');
    expect(monthName('2026-11', 'en-GB')).toBe('November 2026');
    expect(monthName('2026-03', 'sw-TZ').toLowerCase()).toContain('2026');
  });

  it('writes dates as day/month/year, and reads today from the computer', () => {
    expect(dayLabel('2026-11-05')).toBe('05/11/2026');
    expect(dayLabel('2026-11-05 09:30:00')).toBe('05/11/2026');
    expect(dayLabel(null)).toBe('');
    expect(dayOf(new Date(2026, 10, 5))).toBe('2026-11-05');
  });

  it('reads the words of a failed request', () => {
    expect(serverMessage({ status: 422, error: { message: 'Validation failed', errors: { email: ['Enter an email'] } } })).toBe('Enter an email');
    expect(serverMessage({ status: 401, error: { message: 'Invalid credentials' } })).toBe('Invalid credentials');
    expect(serverMessage({ status: 500 })).toBeNull();
    expect(offline({ status: 0 })).toBe(true);
    expect(offline({ status: 500 })).toBe(false);
  });
});
