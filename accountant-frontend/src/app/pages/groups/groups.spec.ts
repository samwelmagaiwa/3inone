import { TestBed } from '@angular/core/testing';

import { environment } from '../../../environments/environment';
import { GroupsContext } from '../../core/groups/groups-context.service';
import { GroupsApi } from '../../core/groups/groups-api.service';
import { groupHasMember, groupRights, groupViewAsMember } from '../../core/groups/groups-rights';
import { allowedPages, homePath } from '../../core/nav';
import { TRANSLATIONS } from '../../core/translations';
import { byTestId, configure, settle, text } from '../../testing';
import { GDashboardPage, G_WAITING } from './dashboard';
import { GMembersPage } from './members';
import { GPaymentsPage } from './payments';
import { GPreviousDialog } from './previous';

const API = `${environment.apiUrl}/groups`;
const ALL = [
  'view_members', 'manage_members', 'approve_members', 'manage_offices', 'view_finance', 'record_payments', 'verify_payments', 'reverse_payments',
  'record_payouts', 'manage_contributions', 'grant_exemptions', 'view_loans', 'recommend_loans', 'approve_loans', 'view_benefits', 'approve_benefits',
  'manage_settings', 'view_expenses', 'request_expenses', 'approve_expenses', 'manage_assets', 'view_projects', 'manage_projects', 'call_meetings',
  'record_meetings', 'approve_minutes', 'post_announcements', 'send_texts', 'manage_votings', 'prepare_dividends', 'approve_dividends', 'view_audit',
];

/** A signed-in business admin working in Groups, with these rights in the group. */
function asGroups(rights: string[], waiting: Record<string, number> = {}) {
  const h = configure({ role: 'admin', services: ['groups'], permissions: [] });
  groupRights.set(new Set(rights));
  TestBed.inject(GroupsContext).me.set({ is_owner: true, rights, waiting, group: { name: 'MEG', logo_url: null } });
  return h;
}

describe('Groups (Vikundi) on the web: the menu', () => {
  afterEach(() => groupRights.set(new Set()));

  it('the business admin sees every Groups page and none of the shop pages; Groups starts at its own start page', () => {
    const h = asGroups(ALL);
    const keys = allowedPages(h.auth).map((p) => p.key);
    expect(keys).toEqual(expect.arrayContaining(['g_dashboard', 'g_members', 'g_payments', 'g_contributions', 'g_loans', 'g_welfare', 'g_expenses', 'g_dividends', 'g_assets', 'g_projects', 'g_meetings', 'g_votings', 'g_reports', 'g_settings']));
    expect(keys).not.toContain('products');
    expect(keys).not.toContain('sales');
    expect(homePath(h.auth)).toBe('/groups');
  });

  it('a secretary (members, meetings) sees only those pages; nobody sees Groups pages in the shop', () => {
    const h = asGroups(['view_members', 'manage_members', 'call_meetings', 'record_meetings']);
    const keys = allowedPages(h.auth).map((p) => p.key).filter((k) => k.startsWith('g_'));
    expect(keys.sort()).toEqual(['g_dashboard', 'g_meetings', 'g_members', 'g_reports', 'g_settings'].sort());
    h.auth.service.set('inventory');
    expect(allowedPages(h.auth).some((p) => p.key.startsWith('g_'))).toBe(false);
  });
});

describe('Groups texts', () => {
  it('every value the server sends has its words in both languages', () => {
    const families: Record<string, string[]> = {
      'g.st.': ['submitted', 'active', 'suspended', 'exited', 'rejected', 'deceased', 'pending', 'verified', 'reversed', 'approved', 'declined', 'cancelled', 'paid', 'paying', 'completed', 'closed', 'done', 'returned', 'overdue', 'issued', 'requested', 'proposed', 'scheduled', 'held', 'draft', 'open', 'paused', 'posted', 'discarded', 'due', 'exempt', 'kept', 'under_review', 'awaiting_guarantors', 'recommended', 'repaid', 'accepted', 'queued', 'sent', 'failed'],
      'g.cat.': ['joining_fee', 'shares', 'savings', 'contribution', 'expense', 'loan_disbursement', 'loan_repayment', 'welfare', 'hire', 'dividend', 'opening_balance'],
      'g.method.': ['cash', 'mpesa', 'mixx', 'airtel_money', 'halopesa', 'bank_transfer', 'other'],
      'g.office.': ['mwenyekiti', 'makamu_mwenyekiti', 'mweka_hazina', 'mweka_hazina_msaidizi', 'katibu', 'katibu_msaidizi', 'mwenyekiti_miradi', 'kamati_miradi', 'none'],
      'g.wait.': Object.keys(G_WAITING),
      'g.rel.': ['self', 'parent', 'spouse', 'child', 'parent_in_law', 'other'],
      'g.repay.': ['daily', 'weekly', 'every_2_weeks', 'monthly', 'every_2_months', 'quarterly', 'every_6_months', 'custom'],
      'g.setv.': ['none', 'loans', 'membership', 'off', 'on', 'flat', 'reducing', 'daily', 'weekly', 'every_2_weeks', 'monthly', 'every_2_months', 'quarterly', 'every_6_months', 'custom', 'both', 'between'],
      'g.ev.': ['maintenance', 'repair', 'damage', 'loss', 'adjust', 'retire', 'custody'],
      'g.e.cat.': ['project', 'office', 'meeting', 'transport', 'event', 'other'],
      'g.v.cat.': ['leadership', 'project', 'financial', 'policy', 'proposal', 'general'],
      'g.nk.': ['general', 'meeting', 'event', 'bereavement', 'contribution', 'loan', 'asset', 'emergency'],
      'service.': ['groups'],
    };
    for (const [prefix, values] of Object.entries(families)) {
      for (const v of values) {
        expect(prefix + v in TRANSLATIONS.en, prefix + v).toBe(true);
        expect(prefix + v in TRANSLATIONS.sw, prefix + v).toBe(true);
      }
    }
  });
});

describe('Groups payments page', () => {
  afterEach(() => groupRights.set(new Set()));

  async function open() {
    const h = asGroups(ALL);
    const fixture = TestBed.createComponent(GPaymentsPage);
    fixture.detectChanges();
    h.http.expectOne((r) => r.url === `${API}/transactions` && r.params.get('status') === 'pending').flush({
      data: { transactions: [{ id: 5, member_name: 'Asha Juma', member_number: 'MEG-0001', category: 'savings', direction: 'in', amount: 20000, method: 'mpesa', external_ref: 'QX12', paid_on: '2026-11-20', status: 'pending', reference: 'TRX-1', submitted_by_name: 'Mweka Hazina' }] },
      meta: { pagination: { page: 1, total: 1, has_more: false } },
    });
    h.http.expectOne(`${API}/transactions/summary`).flush({ data: { cash_on_record: 1250000, pending_count: 1, pending_amount: 20000, verified: { savings: 800000, shares: 240000 }, expenses_in_month: 15000 } });
    h.http.expectOne(`${API}/payment-methods`).flush({ data: { configured: true, methods: [{ method: 'mpesa' }, { method: 'cash' }] } });
    await settle(fixture);

    return { h, fixture, el: fixture.nativeElement as HTMLElement };
  }

  it('shows the cash on record and the waiting payments, and verifies one after a yes', async () => {
    const { h, fixture, el } = await open();
    expect(text(byTestId(el, 'g-p-cash')!)).toContain('1,250,000');
    const list = el.querySelector('[data-testid="g-p-list"] table.grid-table') as HTMLElement;
    expect(list).not.toBeNull();
    expect(text(list)).toContain('Asha Juma');
    expect(text(list)).toContain('QX12');
    expect(Array.from(list.querySelectorAll('thead th')).map((th) => text(th as HTMLElement))).toContain('Actions');

    // the actions are behind the row's three dots
    expect(byTestId(el, 'g-p-verify-5')).toBeNull();
    (el.querySelector('[data-testid="g-p-menu-5"]') as HTMLButtonElement).click();
    await settle(fixture);
    (byTestId(el, 'g-p-verify-5') as HTMLButtonElement).click();
    await settle(fixture);
    const req = h.http.expectOne(`${API}/transactions/5/verify`);
    expect(req.request.method).toBe('POST');
    req.flush({ data: { transaction: {} } });
    await settle(fixture);
    h.http.match(() => true).forEach((r) => r.flush({ data: {} }));
  });

  it('records an opening balance for the group (no member) on an earlier day', async () => {
    const { h, fixture, el } = await open();
    // the four kinds of record are behind one "Record" button
    (el.querySelector('[data-testid="g-p-record"]') as HTMLButtonElement).click();
    await settle(fixture);
    (byTestId(el, 'g-p-opening') as HTMLButtonElement).click();
    await settle(fixture);
    const amount = byTestId(el, 'g-pf-amount') as HTMLInputElement;
    amount.value = '500,000';
    amount.dispatchEvent(new Event('input'));
    const date = byTestId(el, 'g-pf-date') as HTMLInputElement;
    date.value = '2026-10-01';
    date.dispatchEvent(new Event('input'));
    const method = byTestId(el, 'g-pf-method') as HTMLSelectElement;
    method.value = 'cash';
    method.dispatchEvent(new Event('change'));
    await settle(fixture);
    (byTestId(el, 'g-pf-save') as HTMLButtonElement).click();
    await settle(fixture);
    const req = h.http.expectOne((r) => r.url === `${API}/transactions` && r.method === 'POST');
    expect(req.request.body).toEqual({ amount: 500000, method: 'cash', paid_on: '2026-10-01', category: 'opening_balance' });
    req.flush({ data: { transaction: {} } });
    await settle(fixture);
    h.http.match(() => true).forEach((r) => r.flush({ data: {} }));
  });
});

describe('Groups members page', () => {
  afterEach(() => groupRights.set(new Set()));

  it('adds someone who was a member before the app, with their old number and the day they joined', async () => {
    const h = asGroups(ALL);
    const fixture = TestBed.createComponent(GMembersPage);
    fixture.detectChanges();
    h.http.expectOne((r) => r.url === `${API}/members`).flush({ data: { members: [] }, meta: { pagination: { page: 1, total: 0, has_more: false } } });
    await settle(fixture);
    const el = fixture.nativeElement as HTMLElement;

    (byTestId(el, 'g-m-new') as HTMLButtonElement).click();
    await settle(fixture);
    const type = (id: string, v: string) => {
      const box = byTestId(el, id) as HTMLInputElement;
      box.value = v;
      box.dispatchEvent(new Event('input'));
    };
    type('g-f-name', 'Rehema Said');
    type('g-f-phone', '0713000002');
    const existing = byTestId(el, 'g-f-existing') as HTMLInputElement;
    existing.click();
    await settle(fixture);
    const number = el.querySelector('input[name="fmn"]') as HTMLInputElement;
    number.value = 'MEG-0007';
    number.dispatchEvent(new Event('input'));
    const joined = el.querySelector('input[name="fj"]') as HTMLInputElement;
    joined.value = '2024-03-01';
    joined.dispatchEvent(new Event('input'));
    await settle(fixture);
    (byTestId(el, 'g-f-save') as HTMLButtonElement).click();
    await settle(fixture);

    const req = h.http.expectOne((r) => r.url === `${API}/members` && r.method === 'POST');
    expect(req.request.body).toEqual({ full_name: 'Rehema Said', phone: '0713000002', existing: true, member_number: 'MEG-0007', joined_on: '2024-03-01' });
    req.flush({ data: { member: { id: 9 } } });
    await settle(fixture);
    h.http.match(() => true).forEach((r) => r.flush({ data: { members: [] }, meta: { pagination: {} } }));
  });
});

describe('Groups dashboard', () => {
  afterEach(() => groupRights.set(new Set()));

  it('lists what waits for the leader, each leading to its page, with the month in figures', async () => {
    const h = asGroups(ALL, { payments_to_verify: 3, loans_to_approve: 1, applications: 0 });
    const fixture = TestBed.createComponent(GDashboardPage);
    fixture.detectChanges();
    h.http.match((r) => r.url === `${API}/me`).forEach((r) => r.flush({ data: { is_owner: true, rights: ALL, waiting: { payments_to_verify: 3, loans_to_approve: 1, applications: 0 } } }));
    h.http.expectOne((r) => r.url === `${API}/dashboard`).flush({
      data: {
        members: { active: 24, applications: 2, joined_in_month: 1 },
        money: { cash_on_record: 1250000, month_in: 400000, month_out: 90000, savings: 800000, shares: 240000, pending_count: 3, contributions: { expected: 200000, collected: 150000 }, loans: {}, year: {}, trend: [], mix: [] },
      },
    });
    await settle(fixture);
    const el = fixture.nativeElement as HTMLElement;

    expect(text(byTestId(el, 'g-cash')!)).toContain('1,250,000');
    expect(text(byTestId(el, 'g-collection')!)).toContain('75%');
    expect(byTestId(el, 'g-wait-payments_to_verify')!.getAttribute('href')).toContain('/groups/payments');
    expect(byTestId(el, 'g-wait-loans_to_approve')).not.toBeNull();
    expect(byTestId(el, 'g-wait-applications')).toBeNull();
  });
});

describe('Groups ME (a leader looking as an ordinary member)', () => {
  afterEach(() => {
    groupRights.set(new Set());
    groupViewAsMember.set(false);
    groupHasMember.set(false);
  });

  it('with ME on the menu is My account alone; with it off a leader starts on the dashboard and still has My account', () => {
    const h = asGroups([]);
    groupHasMember.set(true);
    expect(allowedPages(h.auth).map((p) => p.key).filter((k) => k.startsWith('g_'))).toEqual(['g_me']);

    groupRights.set(new Set(ALL));
    const keys = allowedPages(h.auth).map((p) => p.key).filter((k) => k.startsWith('g_'));
    expect(keys[0]).toBe('g_dashboard');
    expect(keys).toContain('g_me');
  });

  it('every Groups call says "member view" while ME is on, and only Groups calls', async () => {
    const h = asGroups(ALL);
    const api = TestBed.inject(GroupsApi);
    groupViewAsMember.set(true);
    void api.get('/me');
    const on = h.http.expectOne(`${API}/me`);
    expect(on.request.headers.get('X-Group-View')).toBe('member');
    on.flush({ data: {} });

    groupViewAsMember.set(false);
    void api.get('/me');
    const off = h.http.expectOne(`${API}/me`);
    expect(off.request.headers.has('X-Group-View')).toBe(false);
    off.flush({ data: {} });
  });

  it('turning ME on is remembered for this person and reads the group again in that view', async () => {
    const h = asGroups(ALL);
    const ctx = TestBed.inject(GroupsContext);
    const done = ctx.setViewAsMember(true);
    const req = h.http.expectOne(`${API}/me`);
    expect(req.request.headers.get('X-Group-View')).toBe('member');
    req.flush({ data: { is_owner: false, rights: [], can_switch_view: true, member: { id: 1, full_name: 'Juma' } } });
    await done;
    expect(ctx.viewingAsMember()).toBe(true);
    expect(groupHasMember()).toBe(true);
    expect(localStorage.getItem(`groups_me_view_${h.auth.user()!.id}`)).toBe('1');
  });
});

describe('Groups: previous data (before the app)', () => {
  afterEach(() => groupRights.set(new Set()));

  it('a leader enters a member’s totals as of a date, each kind of contribution by its own amount, and sees what was entered', async () => {
    const h = asGroups(ALL);
    const fixture = TestBed.createComponent(GPreviousDialog);
    fixture.componentRef.setInput('member', { id: 7, full_name: 'Michael Prosper Shirima' });
    fixture.detectChanges();
    const types = [{ id: 1, name: 'JAMII', refundable: false, active: true }, { id: 2, name: 'MRADI', refundable: true, active: true }];
    h.http.expectOne(`${API}/members/7/previous`).flush({ data: { types, entries: [], loans: [] } });
    await settle(fixture);
    const el = fixture.nativeElement as HTMLElement;
    expect(text(byTestId(el, 'g-previous') as HTMLElement)).toContain('MRADI');
    expect(el.querySelectorAll('.ph-badge.ph-good').length).toBe(1);

    const type = (id: string, v: string) => {
      const box = byTestId(el, id) as HTMLInputElement;
      box.value = v;
      box.dispatchEvent(new Event('input'));
    };
    type('g-prev-as-of', '2026-06-30');
    type('g-prev-savings', '1,300,000');
    type('g-prev-c-1', '180,000');
    type('g-prev-c-2', '200000');
    await settle(fixture);
    (byTestId(el, 'g-prev-save') as HTMLButtonElement).click();
    await settle(fixture);

    const req = h.http.expectOne((r) => r.url === `${API}/members/7/previous` && r.method === 'POST');
    expect(req.request.body).toEqual({ as_of: '2026-06-30', savings: 1300000, contributions: [{ type_id: 1, amount: 180000 }, { type_id: 2, amount: 200000 }] });
    req.flush({ data: { created: 3 } });
    await settle(fixture);
    h.http.expectOne(`${API}/members/7/previous`).flush({ data: { types, entries: [{ id: 50, category: 'savings', amount: 1300000, paid_on: '2026-06-30', brought_forward: true }], loans: [] } });
    await settle(fixture);
    expect(text(byTestId(el, 'g-prev-list') as HTMLElement)).toContain('1,300,000');
  });

  it('a running loan is entered from what is still owed; owing more than was borrowed is stopped before it is sent', async () => {
    const h = asGroups(ALL);
    const fixture = TestBed.createComponent(GPreviousDialog);
    fixture.componentRef.setInput('member', { id: 7, full_name: 'Michael Prosper Shirima' });
    fixture.detectChanges();
    h.http.expectOne(`${API}/members/7/previous`).flush({ data: { types: [], entries: [], loans: [] } });
    await settle(fixture);
    const el = fixture.nativeElement as HTMLElement;
    const type = (id: string, v: string) => {
      const box = byTestId(el, id) as HTMLInputElement;
      box.value = v;
      box.dispatchEvent(new Event('input'));
    };
    type('g-prev-l-amount', '500,000');
    type('g-prev-l-left', '600,000');
    type('g-prev-l-inst', '100,000');
    type('g-prev-l-next', '2026-12-05');
    await settle(fixture);
    (byTestId(el, 'g-prev-l-save') as HTMLButtonElement).click();
    await settle(fixture);
    expect(h.http.match((r) => r.method === 'POST')).toEqual([]);

    type('g-prev-l-left', '250,000');
    await settle(fixture);
    (byTestId(el, 'g-prev-l-save') as HTMLButtonElement).click();
    await settle(fixture);
    const req = h.http.expectOne((r) => r.url === `${API}/members/7/previous/loan`);
    expect(req.request.body).toEqual({ amount: 500000, remaining: 250000, instalment: 100000, next_due: '2026-12-05' });
    req.flush({ data: { loan: { id: 3 } } });
    await settle(fixture);
    h.http.match(() => true).forEach((r) => r.flush({ data: { types: [], entries: [], loans: [] } }));
  });
});
