import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';

import { environment } from '../../../environments/environment';
import { configure, settle, text } from '../../testing';
import { ShellLayout } from './shell-layout';

async function open(who = {}, notifications: { id: number; title: string; body: string; read_at: string | null; created_at: string; type: string }[] = []) {
  const h = configure(who);
  const navigate = vi.spyOn(TestBed.inject(Router), 'navigate').mockResolvedValue(true);
  const fixture = TestBed.createComponent(ShellLayout);
  fixture.detectChanges();
  h.http.expectOne(`${environment.apiUrl}/inventory/notifications`).flush({ data: notifications, meta: { unread_count: notifications.filter((n) => !n.read_at).length } });
  await settle(fixture);

  return { h, navigate, fixture, el: fixture.nativeElement as HTMLElement };
}

/** The work pages of the menu (the assistant, which is for everyone, has its own test below). */
const nav = (el: HTMLElement) => Array.from(el.querySelectorAll('.sidebar-nav a.nav-item .nav-label')).map((e) => text(e as HTMLElement)).filter((l) => l !== 'AI assistant' && l !== 'Msaidizi wa AI');

describe('the frame', () => {
  it('shows only the pages this person\'s rights open, in the template\'s sidebar', async () => {
    const { el } = await open();
    expect(nav(el)).toEqual(['This month', 'Sales', 'Debts', 'Expenses']);
    expect(el.querySelector('aside.sidebar')).not.toBeNull();
  });

  it('has a labelled AI assistant button in the top bar and a menu entry, for everyone, even with no rights', async () => {
    const full = await open();
    const chip = full.el.querySelector('[data-testid="header-ai"]') as HTMLAnchorElement;
    expect(text(chip)).toBe('AI assistant');
    expect(chip.getAttribute('href')).toBe('/assistant');
    expect(chip.getAttribute('aria-label')).toBe('AI assistant');
    expect(Array.from(full.el.querySelectorAll('.sidebar-nav a.nav-item .nav-label')).map((e) => text(e as HTMLElement))).toContain('AI assistant');

    TestBed.resetTestingModule();
    const none = await open({ permissions: [] });
    expect(text(none.el.querySelector('[data-testid="header-ai"]') as HTMLElement)).toBe('AI assistant');
  });

  it('asks for the plan only when the person belongs to a business (no business, no plan, no failed request)', async () => {
    const withBusiness = await open();
    withBusiness.h.http.expectOne(`${environment.apiUrl}/business/subscription`);

    TestBed.resetTestingModule();
    const without = await open({ business: '' });
    without.h.http.expectNone(`${environment.apiUrl}/business/subscription`);
  });

  it('fewer rights, fewer pages', async () => {
    const some = await open({ permissions: ['inv_view_expenses'] });
    expect(nav(some.el)).toEqual(['Expenses']);
  });

  it('no rights at all says so instead of showing an empty menu', async () => {
    const none = await open({ permissions: [] });
    expect(nav(none.el)).toEqual([]);
    expect(text(none.el.querySelector('.sidebar-nav') as HTMLElement)).toContain('Nothing to open yet');
  });

  it('shows the business and the person', async () => {
    const { el } = await open();
    expect(text(el.querySelector('.sidebar-logo-text') as HTMLElement)).toContain('Mama Shop');
    expect(text(el.querySelector('.profile-name') as HTMLElement)).toBe('Amina Hassan');
  });

  it('the shop / salon switch is not shown to someone who works in one service only', async () => {
    const one = await open();
    expect(one.el.querySelector('.svc-switch')).toBeNull();
  });

  it('for someone who works in both the switch changes what the menu offers', async () => {
    const both = await open({ services: ['inventory', 'salon'] });
    expect(both.el.querySelector('.svc-switch')).not.toBeNull();
    const buttons = Array.from(both.el.querySelectorAll('.svc-btn')) as HTMLButtonElement[];
    expect(buttons.map((b) => text(b))).toEqual(['Shop', 'Salon']);

    buttons[1].click();
    both.h.http.expectOne(`${environment.apiUrl}/inventory/notifications`).flush({ data: [], meta: { unread_count: 0 } });
    await settle(both.fixture);
    expect(both.h.auth.service()).toBe('salon');
    expect(nav(both.el)).toEqual(['Sales', 'Expenses']);
    expect(both.navigate).toHaveBeenCalledWith(['/sales']);
  });

  it('the language button switches the menu between Swahili and English', async () => {
    const { h, fixture, el } = await open();
    (el.querySelector('button.top-chip') as HTMLButtonElement).click();
    await settle(fixture);

    expect(h.i18n.lang()).toBe('sw');
    expect(nav(el)).toEqual(['Mwezi huu', 'Mauzo', 'Madeni', 'Matumizi']);
    expect(document.documentElement.lang).toBe('sw');
  });

  it('the bell shows how many messages are new, lists them, and marks one read when it is opened', async () => {
    const now = new Date().toISOString();
    const items = [
      { id: 1, type: 'x', title: 'The October report is ready', body: 'Profit TSh 5,000', read_at: null, created_at: now },
      { id: 2, type: 'x', title: 'Old news', body: 'Already read', read_at: now, created_at: now },
    ];
    const { h, fixture, el } = await open({}, items);
    expect(text(el.querySelector('.bell-badge') as HTMLElement)).toBe('1');

    (el.querySelector('.bell-btn') as HTMLButtonElement).click();
    h.http.expectOne(`${environment.apiUrl}/inventory/notifications`).flush({ data: items, meta: { unread_count: 1 } });
    await settle(fixture);
    const panel = text(el.querySelector('.bell-panel') as HTMLElement);
    expect(panel).toContain('The October report is ready');
    expect(panel).toContain('Old news');

    (el.querySelector('.bell-item--unread') as HTMLButtonElement).click();
    expect(h.http.expectOne(`${environment.apiUrl}/inventory/notifications/1/read`).request.method).toBe('POST');
    await settle(fixture);
    expect(el.querySelector('.bell-badge')).toBeNull();
  });

  it('signing out asks first; "no" keeps the person signed in', async () => {
    const { h, fixture, el } = await open();
    const logout = vi.spyOn(h.auth, 'logout').mockImplementation(() => undefined);

    h.confirmAnswer.value = false;
    (el.querySelector('.signout-btn') as HTMLButtonElement).click();
    await settle(fixture);
    expect(logout).not.toHaveBeenCalled();

    h.confirmAnswer.value = true;
    (el.querySelector('.signout-btn') as HTMLButtonElement).click();
    await settle(fixture);
    expect(logout).toHaveBeenCalledTimes(1);
  });

  it('"My profile" says in words what the person can do, not codes', async () => {
    const { fixture, el } = await open({ permissions: ['inv_view_reports', 'inv_view_credit'] });
    (el.querySelector('.profile-btn') as HTMLButtonElement).click();
    await settle(fixture);
    (el.querySelector('.pm-item') as HTMLButtonElement).click();
    await settle(fixture);

    const modal = text(el.querySelector('app-modal-dialog') as HTMLElement);
    expect(modal).toContain('See reports and the monthly figures');
    expect(modal).toContain('See and write down debts');
    expect(modal).not.toContain('inv_view_reports');
  });

  it('there is a help window written for someone new to computers', async () => {
    const { fixture, el } = await open();
    (el.querySelector('.sidebar-nav button.nav-item') as HTMLButtonElement).click();
    await settle(fixture);

    const modals = Array.from(el.querySelectorAll('app-modal-dialog')).map((m) => text(m as HTMLElement)).join(' ');
    expect(modals).toContain('You do not need to know computers');
    expect(modals).toContain('Sign out');
    expect(modals).toContain('Nothing you do here can be lost');
  });
});
