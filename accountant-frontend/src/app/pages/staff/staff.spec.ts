import { TestBed } from '@angular/core/testing';

import { environment } from '../../../environments/environment';
import { NAV } from '../../core/nav';
import { byTestId, configure, settle, text, type, user } from '../../testing';
import { StaffPage, defaultPassword, readStaff } from './staff';

const API = environment.apiUrl;
const LIST = {
  data: {
    users: [
      { id: 'u1', name: 'Asha Juma', email: 'asha@glow.test', phone_number: '0711000001', role: 'hair_stylist', is_active: true },
      { id: 'u2', name: 'Neema Paul', email: 'neema@glow.test', phone_number: '0711000002', role: 'accountant', is_active: false },
    ],
  },
};

async function open(list: object = LIST) {
  const h = configure({ role: 'admin', roleLabel: 'Admin', services: ['salon'], permissions: ['__all__'] });
  const fixture = TestBed.createComponent(StaffPage);
  fixture.detectChanges();
  h.http.expectOne((r) => r.method === 'GET' && r.url === `${API}/admin/users/mine` && r.params.get('created_by') === 'me').flush(list);
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

describe('staff', () => {
  it('makes the first password the way the phone does: the last word in capitals, repeated to eight letters', () => {
    expect(defaultPassword('Asha Juma')).toBe('JUMAJUMA');
    expect(defaultPassword('Magaiwa')).toBe('MAGAIWAM');
    expect(defaultPassword('Neema Elizabeth Mwakyusa')).toBe('MWAKYUSA');
    expect(defaultPassword('')).toBe('PASSWORD');
  });

  it('reads the list the server sends, and an odd answer as nobody', () => {
    expect(readStaff(LIST).map((p) => [p.name, p.role, p.active])).toEqual([['Asha Juma', 'hair_stylist', true], ['Neema Paul', 'accountant', false]]);
    expect(readStaff(null)).toEqual([]);
    expect(readStaff({ data: { users: 'x' } })).toEqual([]);
  });

  it('is in the menu for the business owner only, in a salon', () => {
    const item = NAV.find((n) => n.key === 'staff')!;
    const { auth } = configure({ role: 'admin', services: ['salon'] });
    expect(item.allowed(auth)).toBe(true);
    auth.user.set(user({ role: 'accountant', services: ['salon'] }));
    expect(item.allowed(auth)).toBe(false);
  });

  it('lists the people with their role, phone and email, and shows who is switched off', async () => {
    const { el } = await open();

    expect(text(byTestId(el, 'st-row-u1')!)).toContain('Asha Juma');
    expect(text(byTestId(el, 'st-row-u1')!)).toContain('Hair stylist');
    expect(text(byTestId(el, 'st-row-u1')!)).toContain('0711000001');
    expect(text(byTestId(el, 'st-row-u2')!)).toContain('Switched off');
  });

  it('registers a person in the salon with a first password made from the name, and shows it once', async () => {
    const { h, fixture, el } = await open({ data: { users: [] } });
    expect(byTestId(el, 'st-empty')).not.toBeNull();

    (byTestId(el, 'st-add') as HTMLButtonElement).click();
    fixture.detectChanges();
    await settle(fixture);
    type(el, '[data-testid="st-name"]', 'Asha Juma');
    type(el, '[data-testid="st-phone"]', '0711000001');
    type(el, '[data-testid="st-email"]', 'asha@glow.test');
    const role = byTestId(el, 'st-role') as HTMLSelectElement;
    expect(Array.from(role.options).map((o) => o.value)).toEqual(['manager', 'accountant', 'hair_stylist', 'nail_technician', 'lash_makeup_artist', 'viewer']);
    role.value = 'hair_stylist';
    role.dispatchEvent(new Event('change', { bubbles: true }));
    fixture.detectChanges();
    expect(text(byTestId(el, 'st-password-note')!)).toContain('JUMAJUMA');

    (byTestId(el, 'st-save') as HTMLButtonElement).click();
    const req = h.http.expectOne({ method: 'POST', url: `${API}/admin/users` });
    expect(req.request.body).toMatchObject({
      name: 'Asha Juma', email: 'asha@glow.test', phone_number: '0711000001', role: 'hair_stylist', is_active: true,
      password: 'JUMAJUMA', password_confirmation: 'JUMAJUMA', service_types: ['salon'],
    });
    req.flush({ success: true, data: { user: { id: 'u9' } } }, { status: 201, statusText: 'Created' });
    await settle(fixture);
    h.http.expectOne((r) => r.method === 'GET' && r.url === `${API}/admin/users/mine`).flush(LIST);
    await settle(fixture);

    expect(text(byTestId(el, 'st-given-password')!)).toBe('JUMAJUMA');
  });

  it('asks for a name, a correct email and a phone before it sends anything', async () => {
    const { fixture, el } = await open();
    (byTestId(el, 'st-add') as HTMLButtonElement).click();
    fixture.detectChanges();
    await settle(fixture);

    (byTestId(el, 'st-save') as HTMLButtonElement).click();
    fixture.detectChanges();
    expect(text(byTestId(el, 'st-error')!)).toContain('full name');
    type(el, '[data-testid="st-name"]', 'Asha Juma');
    (byTestId(el, 'st-save') as HTMLButtonElement).click();
    fixture.detectChanges();
    expect(text(byTestId(el, 'st-error')!)).toContain('email');
  });

  it('says what the server refused (an email already taken)', async () => {
    const { h, fixture, el } = await open();
    (byTestId(el, 'st-add') as HTMLButtonElement).click();
    fixture.detectChanges();
    await settle(fixture);
    type(el, '[data-testid="st-name"]', 'Asha Juma');
    type(el, '[data-testid="st-phone"]', '0711000001');
    type(el, '[data-testid="st-email"]', 'asha@glow.test');

    (byTestId(el, 'st-save') as HTMLButtonElement).click();
    h.http.expectOne({ method: 'POST', url: `${API}/admin/users` }).flush({ success: false, message: 'The email has already been taken.' }, { status: 422, statusText: 'Unprocessable' });
    await settle(fixture);

    expect(text(byTestId(el, 'st-error')!)).toContain('already been taken');
  });

  it('switches a person off, and on again', async () => {
    const { h, fixture, el } = await open();

    (byTestId(el, 'st-menu-u1') as HTMLButtonElement).click();
    await settle(fixture);
    (byTestId(el, 'st-toggle-u1') as HTMLButtonElement).click();
    const off = h.http.expectOne({ method: 'PUT', url: `${API}/admin/users/u1` });
    expect(off.request.body).toEqual({ is_active: false });
    off.flush({ success: true });
    await settle(fixture);
    h.http.expectOne((r) => r.method === 'GET' && r.url === `${API}/admin/users/mine`).flush(LIST);
    await settle(fixture);

    (byTestId(el, 'st-menu-u2') as HTMLButtonElement).click();
    await settle(fixture);
    (byTestId(el, 'st-toggle-u2') as HTMLButtonElement).click();
    const on = h.http.expectOne({ method: 'PUT', url: `${API}/admin/users/u2` });
    expect(on.request.body).toEqual({ is_active: true });
    on.flush({ success: true });
    await settle(fixture);
    h.http.expectOne((r) => r.method === 'GET' && r.url === `${API}/admin/users/mine`).flush(LIST);
  });

  it('gives a new first password and shows it', async () => {
    const { h, fixture, el } = await open();

    (byTestId(el, 'st-menu-u2') as HTMLButtonElement).click();
    await settle(fixture);
    (byTestId(el, 'st-reset-u2') as HTMLButtonElement).click();
    await settle(fixture);
    const req = h.http.expectOne({ method: 'POST', url: `${API}/admin/users/u2/reset-password` });
    expect(req.request.body).toEqual({ password: 'PAULPAUL', password_confirmation: 'PAULPAUL' });
    req.flush({ success: true });
    await settle(fixture);

    expect(text(byTestId(el, 'st-given-password')!)).toBe('PAULPAUL');
  });
});
