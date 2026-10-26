import { TestBed } from '@angular/core/testing';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';

import { environment } from '../../environments/environment';
import { configure, user } from '../testing';
import { authGuard, canOpen, noAuthGuard, startPage } from './auth.guard';
import { AuthService, toSessionUser } from './auth.service';
import { NAV, allowedPages, homePath } from './nav';

const accountantPayload = {
  token: 'T1',
  role_display: 'Accountant',
  user: {
    id: 7,
    name: 'Amina Hassan',
    email: 'amina@shop.test',
    role: 'accountant',
    phone_number: '0712345678',
    services: [{ service_type: 'inventory' }, { service_type: 'rental' }, { service_type: 'salon' }],
    effective_permissions: ['inv_view_reports', 'inv_view_credit'],
    business: { name: 'Mama Shop' },
  },
};

describe('sign-in', () => {
  it('sends email, phone and password, then keeps the token, the person, their rights and the services the web app supports', async () => {
    const { auth, http } = configure(null);

    const done = auth.login('amina@shop.test', '0712345678', 'secret');
    const req = http.expectOne(`${environment.apiUrl}/auth/login`);
    expect(req.request.body).toEqual({ email: 'amina@shop.test', phone_number: '0712345678', password: 'secret' });
    req.flush({ status: 'success', message: 'ok', data: accountantPayload });
    await done;

    expect(auth.isLoggedIn()).toBe(true);
    expect(auth.user()).toMatchObject({ id: '7', name: 'Amina Hassan', roleLabel: 'Accountant', business: 'Mama Shop' });
    expect(auth.user()?.services).toEqual(['inventory', 'salon']); // rental is not for this app
    expect(auth.service()).toBe('inventory');
    expect(localStorage.getItem('accountant_token')).toBe('T1');
  });

  it('a wrong password leaves nobody signed in', async () => {
    const { auth, http } = configure(null);

    const done = auth.login('x@y.test', '0712345678', 'bad');
    http.expectOne(`${environment.apiUrl}/auth/login`).flush({ status: 'error', message: 'Invalid credentials' }, { status: 401, statusText: 'Unauthorized' });

    await expect(done).rejects.toMatchObject({ status: 401 });
    expect(auth.isLoggedIn()).toBe(false);
  });

  it('signing out forgets everything and tells the server', () => {
    const { auth, http } = configure({});
    const navigate = vi.spyOn(TestBed.inject(Router), 'navigate').mockResolvedValue(true);

    auth.logout();

    http.expectOne(`${environment.apiUrl}/auth/logout`).flush({});
    expect(auth.isLoggedIn()).toBe(false);
    expect(localStorage.getItem('accountant_token')).toBeNull();
    expect(navigate).toHaveBeenCalledWith(['/login']);
  });

  it('keeps the rights the server resolved, and never invents any', () => {
    const none = toSessionUser({ token: 't', user: { id: 1, name: 'N', email: 'n@x.test', role: 'viewer' } });
    expect(none.permissions).toEqual([]);
    expect(none.services).toEqual([]);
  });
});

describe('what a person may do', () => {
  it('asks the server\'s own list; the owner\'s "everything" opens all', () => {
    const { auth } = configure({ permissions: ['inv_view_credit'] });
    expect(auth.can('inv_view_credit')).toBe(true);
    expect(auth.can('inv_view_reports')).toBe(false);
    expect(auth.canAny('inv_view_reports', 'inv_view_credit')).toBe(true);

    auth.user.set(user({ permissions: ['__all__'] }));
    expect(auth.can('anything')).toBe(true);
  });

  it('switching service only works between services the person works in', () => {
    const { auth } = configure({ services: ['inventory', 'salon'] });
    auth.switchService('salon');
    expect(auth.service()).toBe('salon');
    auth.user.set(user({ services: ['inventory'] }));
    auth.switchService('salon');
    expect(auth.service()).toBe('salon'); // unchanged: no such service for this person
  });
});

describe('the interceptor', () => {
  it('sends the token and the service the person is working in to our API', () => {
    const { auth, http: ctrl } = configure({ services: ['inventory', 'salon'] });
    const http = TestBed.inject(HttpClient);

    http.get(`${environment.apiUrl}/inventory/monthly-report`).subscribe();
    let req = ctrl.expectOne(`${environment.apiUrl}/inventory/monthly-report`);
    expect(req.request.headers.get('Authorization')).toBe('Bearer TOKEN');
    expect(req.request.headers.get('X-Service')).toBe('inventory');
    req.flush({});

    auth.switchService('salon');
    http.get(`${environment.apiUrl}/inventory/sales`).subscribe();
    req = ctrl.expectOne(`${environment.apiUrl}/inventory/sales`);
    expect(req.request.headers.get('X-Service')).toBe('salon');
    req.flush({});
  });

  it('never sends the token anywhere else', () => {
    const { http: ctrl } = configure({});
    TestBed.inject(HttpClient).get('https://example.com/data').subscribe();
    expect(ctrl.expectOne('https://example.com/data').request.headers.has('Authorization')).toBe(false);
  });

  it('a 401 on the API signs out and goes to the sign-in page, but a failed sign-in does not', () => {
    const { auth, http: ctrl } = configure({});
    const http = TestBed.inject(HttpClient);
    const navigate = vi.spyOn(TestBed.inject(Router), 'navigate').mockResolvedValue(true);

    http.get(`${environment.apiUrl}/inventory/products`).subscribe({ error: () => undefined });
    ctrl.expectOne(`${environment.apiUrl}/inventory/products`).flush({}, { status: 401, statusText: 'Unauthorized' });
    expect(auth.isLoggedIn()).toBe(false);
    expect(navigate).toHaveBeenCalledWith(['/login']);

    navigate.mockClear();
    auth.token.set('NEW');
    http.post(`${environment.apiUrl}/auth/login`, {}).subscribe({ error: () => undefined });
    ctrl.expectOne(`${environment.apiUrl}/auth/login`).flush({}, { status: 401, statusText: 'Unauthorized' });
    expect(auth.isLoggedIn()).toBe(true);
    expect(navigate).not.toHaveBeenCalled();
  });
});

describe('pages by rights', () => {
  /** The work pages; the assistant is for everyone and has its own test below. */
  const keys = (auth: AuthService) => allowedPages(auth).map((p) => p.key).filter((k) => k !== 'assistant');

  it('an accountant with the usual rights gets everything of the shop', () => {
    const { auth } = configure({});
    expect(keys(auth)).toEqual(['dashboard', 'sales', 'credit', 'debts', 'expenses']);
    expect(homePath(auth)).toBe('/dashboard');
  });

  it('only what the rights open: no reports means no dashboard, and the first page is the next one', () => {
    const { auth } = configure({ permissions: ['inv_view_credit', 'inv_view_expenses'] });
    expect(keys(auth)).toEqual(['credit', 'debts', 'expenses']);
    expect(homePath(auth)).toBe('/customers');
  });

  it('shop-only pages are not offered while working in the salon', () => {
    const { auth } = configure({ services: ['inventory', 'salon'] });
    auth.switchService('salon');
    expect(keys(auth)).toEqual(['sales', 'expenses']);
  });

  it('the AI assistant is open to everyone signed in, even with no rights, but it is never where they land', () => {
    const none = configure({ permissions: [] }).auth;
    expect(allowedPages(none).map((p) => p.key)).toEqual(['assistant']);
    expect(homePath(none)).toBe('/welcome');
  });

  it('the AI assistant is also in the menu of someone with every right, who still lands on the first work page', () => {
    const full = configure().auth;
    expect(allowedPages(full).map((p) => p.key)).toContain('assistant');
    expect(homePath(full)).toBe('/dashboard');
  });

  // The rights each role gets by default on the server (User::$INV_ROLE_DEFAULTS) and what the mobile app's menu offers for them.
  it('a sales officer gets the till side: products, sales, customers on credit and debts; not the books', () => {
    const { auth } = configure({ role: 'sales_officer', permissions: ['inv_view_products', 'inv_create_products', 'inv_create_sales', 'inv_view_reminders', 'inv_view_credit', 'inv_view_cash', 'inv_view_crates', 'inv_report_damage'] });
    expect(keys(auth)).toEqual(['products', 'sales', 'credit', 'debts']);
    expect(homePath(auth)).toBe('/products');
  });

  it('an accountant gets the books: this month, products (to read), sales, debts and expenses', () => {
    const { auth } = configure({ role: 'accountant', permissions: ['inv_view_products', 'inv_create_sales', 'inv_manage_sales', 'inv_view_credit', 'inv_view_cash', 'inv_view_reports', 'inv_view_expenses', 'inv_manage_expenses', 'inv_view_reminders'] });
    expect(keys(auth)).toEqual(['dashboard', 'products', 'sales', 'credit', 'debts', 'expenses']);
    expect(homePath(auth)).toBe('/dashboard');
  });

  it('seeing reports or managing sales without the right to sell does not open the sales page (the server would refuse it)', () => {
    const { auth } = configure({ permissions: ['inv_view_reports', 'inv_manage_sales'] });
    expect(keys(auth)).toEqual(['dashboard']);
  });

  it('no rights at all lands on the welcome page', () => {
    const { auth } = configure({ permissions: [] });
    expect(keys(auth)).toEqual([]);
    expect(homePath(auth)).toBe('/welcome');
  });

  it('the guards send a person to a page they have instead of one they may not open', () => {
    const { auth } = configure({ permissions: ['inv_view_expenses'] });
    const router = TestBed.inject(Router);
    const run = (guard: (typeof authGuard)) => TestBed.runInInjectionContext(() => guard({} as never, {} as never));

    expect(run(canOpen('expenses'))).toBe(true);
    expect(String(run(canOpen('dashboard')))).toBe(String(router.createUrlTree(['/expenses'])));
    expect(String(run(startPage))).toBe(String(router.createUrlTree(['/expenses'])));
    expect(run(authGuard)).toBe(true);
    expect(String(run(noAuthGuard))).toBe(String(router.createUrlTree(['/'])));

    auth.clear();
    expect(String(run(authGuard))).toBe(String(router.createUrlTree(['/login'])));
    expect(run(noAuthGuard)).toBe(true);
  });

  it('every page has a name and a hint in both languages', () => {
    for (const n of NAV) expect(n.labelKey && n.hintKey && n.path.startsWith('/')).toBeTruthy();
  });
});
