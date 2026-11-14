import { describe, expect, it } from 'vitest';

import { hm, isActive, readAppointment } from './appointments';

describe('appointments page', () => {
  it('reads an appointment as the phone does', () => {
    const a = readAppointment({
      id: '7', client_name: 'Neema', client_phone: '', staff_id: 3, staff_name: 'Rehema', starts_at: '2026-11-14 09:30:00', ends_at: '2026-11-14 10:45:00',
      status: 'confirmed', total: '45000', source: 'online', deposit: { amount: 5000, status: 'held' },
      services: [{ product_id: 2, name: 'Braids', price: 45000, label: 'Long', minutes: 75 }],
    });
    expect(a.id).toBe(7);
    expect(a.clientPhone).toBeNull();
    expect(a.staffId).toBe('3');
    expect(a.online).toBe(true);
    expect(a.deposit).toBe(5000);
    expect(a.services[0]).toEqual({ productId: 2, name: 'Braids', price: 45000, minutes: 75, label: 'Long' });
    expect(isActive(a)).toBe(true);
    expect(hm(a.startsAt)).toBe('09:30');
    expect(hm(a.endsAt)).toBe('10:45');
  });

  it('a finished appointment is not active, and an empty answer does not break', () => {
    expect(isActive(readAppointment({ status: 'done' }))).toBe(false);
    expect(isActive(readAppointment({ status: 'cancelled' }))).toBe(false);
    expect(readAppointment({}).status).toBe('booked');
  });
});
