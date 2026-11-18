import { describe, expect, it } from 'vitest';

import { SWITCHES, loyaltyBody, on } from './salon-settings';

describe('salon settings page', () => {
  it('reads a switch however the server writes it', () => {
    expect(on(true)).toBe(true);
    expect(on(1)).toBe(true);
    expect(on('1')).toBe(true);
    expect(on(0)).toBe(false);
    expect(on(undefined)).toBe(false);
  });

  it('every switch saves the field the phone saves', () => {
    expect(SWITCHES.map((s) => s.field)).toEqual(['rebook_enabled', 'appointment_reminders', 'feedback_sms', 'daily_summary', 'online_booking']);
  });

  it('sends the loyalty numbers as whole numbers, with the phone\'s fall-backs', () => {
    expect(loyaltyBody('1,000', '50', '5')).toEqual({ per: 1000, value: 50, referral: 5 });
    expect(loyaltyBody('', '', '')).toEqual({ per: 1, value: 0, referral: 0 });
  });
});
