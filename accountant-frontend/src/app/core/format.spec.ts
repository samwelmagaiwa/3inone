import { eatDay, eatDateTime, serverDate, dayLabel, dayOf, monthKey, monthName, offline, parseAmount, serverMessage, shiftMonth, shortMoney, tsh , localizedName } from './format';

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

describe('server times (UTC) shown as Tanzania time', () => {
  it('a plain server time is UTC and is shown three hours later, as the clock in Tanzania', () => {
    expect(eatDateTime('2026-10-27 06:30:00')).toBe('27/10/2026 09:30');
    expect(eatDateTime('2026-10-27T06:30:00')).toBe('27/10/2026 09:30');
  });

  it('a time with a Z (Laravel JSON) is the same', () => {
    expect(eatDateTime('2026-10-27T06:30:00.000000Z')).toBe('27/10/2026 09:30');
  });

  it('the date moves with the hours', () => {
    expect(eatDateTime('2026-10-27 21:30:00')).toBe('28/10/2026 00:30');
    expect(eatDay('2026-10-27 21:30:00')).toBe('28/10/2026');
  });

  it('a time that says its zone is respected', () => {
    expect(eatDateTime('2026-10-27T09:30:00+03:00')).toBe('27/10/2026 09:30');
    expect(eatDateTime('2026-10-27T05:00:00-01:00')).toBe('27/10/2026 09:00');
  });

  it('nothing, or text that is not a time, gives nothing (never a wrong time)', () => {
    expect(eatDateTime(null)).toBe('');
    expect(eatDateTime('')).toBe('');
    expect(eatDateTime('yesterday')).toBe('');
    expect(serverDate('yesterday')).toBeNull();
  });
});

describe('names written "Kiswahili / English"', () => {
  it('show the half of the language chosen, and any other name as typed', () => {
    expect(localizedName('Kusuka / Braiding', 'sw')).toBe('Kusuka');
    expect(localizedName('Kusuka / Braiding', 'en')).toBe('Braiding');
    expect(localizedName('Soda', 'sw')).toBe('Soda');
    expect(localizedName('A / B / C', 'en')).toBe('A / B / C');
    expect(localizedName(null, 'en')).toBe('');
  });
});
