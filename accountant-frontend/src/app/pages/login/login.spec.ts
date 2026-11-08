import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';

import { environment } from '../../../environments/environment';
import { ToastService } from '../../core/services/toast.service';
import { byTestId, configure, settle, text, type } from '../../testing';
import { LoginPage } from './login';

async function open(opts: { remembered?: string } = {}) {
  const h = configure(null);
  if (opts.remembered) localStorage.setItem('login_remembered_email', opts.remembered);
  const navigate = vi.spyOn(TestBed.inject(Router), 'navigate').mockResolvedValue(true);
  const fixture = TestBed.createComponent(LoginPage);
  fixture.detectChanges();
  await settle(fixture);

  return { h, navigate, fixture, el: fixture.nativeElement as HTMLElement };
}

const submit = (el: HTMLElement) => (el.querySelector('form') as HTMLFormElement).dispatchEvent(new Event('submit'));

const brief = {
  month: '2026-11', is_current: true, is_future: false, days_elapsed: 4, days_in_month: 30,
  previous: { month: '2026-10', like_for_like: true },
  compare: { net_profit: { now: 120000, before: 80000, change: 40000, percent: 50, direction: 'up', good: true } },
  overall: { direction: 'up', percent: 50 },
};

const loginAnswer = { status: 'success', message: 'ok', data: { token: 'T', user: { id: 1, name: 'Amina Hassan', email: 'a@shop.test', role: 'accountant', services: [{ service_type: 'inventory' }], effective_permissions: ['inv_view_reports'] } } };

describe('sign-in page', () => {
  it('asks for the email and the password only: no phone number is asked when signing in, as on the phone', async () => {
    const { el } = await open();
    expect(el.querySelector('#phone')).toBeNull();
    expect(el.querySelector('#email')).not.toBeNull();
    expect(el.querySelector('#password')).not.toBeNull();
    expect(text(el)).not.toContain('The phone number saved on your account.');
  });

  it('asks for both details before it asks the server', async () => {
    const { h, fixture, el } = await open();

    type(el, '#email', 'a@shop.test');
    submit(el);
    await settle(fixture);

    expect(text(el.querySelector('.form-error') as HTMLElement)).toBe('Please fill in your email and password.');
    h.http.expectNone(() => true);
  });

  it('sends the email and password only, welcomes the person and opens their first page', async () => {
    const { h, navigate, fixture, el } = await open();

    type(el, '#email', ' a@shop.test ');
    type(el, '#password', 'secret');
    await settle(fixture);
    submit(el);
    const req = h.http.expectOne(`${environment.apiUrl}/auth/login`);
    expect(req.request.body).toEqual({ email: 'a@shop.test', password: 'secret' });
    req.flush(loginAnswer);
    await settle(fixture);
    // an accountant first sees how the month is going; OK takes them on
    h.http.expectOne((r) => r.url === `${environment.apiUrl}/inventory/monthly-report`).flush({ data: brief });
    await settle(fixture);
    expect(navigate).not.toHaveBeenCalled();
    expect(text(byTestId(el, 'login-brief')!)).toContain('Profit TSH 120,000 against TSH 80,000');
    expect(el.textContent).toContain('Better than');
    byTestId(el, 'login-brief-ok')!.click();
    await settle(fixture);

    expect(navigate).toHaveBeenCalledWith(['/']);
    expect(TestBed.inject(ToastService).toasts()[0].message).toBe('Welcome back, Amina Hassan.');
  });

  it('an accountant whose month cannot be read still gets in, and anyone else goes straight on', async () => {
    const { h, navigate, fixture, el } = await open();
    type(el, '#email', 'a@shop.test');
    type(el, '#password', 'secret');
    await settle(fixture);
    submit(el);
    h.http.expectOne(`${environment.apiUrl}/auth/login`).flush(loginAnswer);
    await settle(fixture);
    h.http.expectOne((r) => r.url === `${environment.apiUrl}/inventory/monthly-report`).error(new ProgressEvent('error'), { status: 0 });
    await settle(fixture);

    expect(navigate).toHaveBeenCalledWith(['/']);
  });

  it('shows the server\'s own words when sign-in fails, and plain words when the server cannot be reached', async () => {
    const { h, fixture, el } = await open();
    type(el, '#email', 'a@shop.test');
    type(el, '#password', 'bad');
    await settle(fixture);

    submit(el);
    h.http.expectOne(`${environment.apiUrl}/auth/login`).flush({ message: 'Invalid credentials' }, { status: 401, statusText: 'Unauthorized' });
    await settle(fixture);
    expect(text(el.querySelector('.form-error') as HTMLElement)).toBe('Invalid credentials');

    submit(el);
    h.http.expectOne(`${environment.apiUrl}/auth/login`).error(new ProgressEvent('error'), { status: 0 });
    await settle(fixture);
    expect(text(el.querySelector('.form-error') as HTMLElement)).toContain('Cannot reach the server');
  });

  it('the language button changes every word on the page', async () => {
    const { h, fixture, el } = await open();
    expect(text(el)).toContain('Welcome');

    h.i18n.setLang('sw');
    await settle(fixture);

    expect(text(el)).toContain('Karibu');
    expect(text(el)).toContain('Nywila');
    expect(text(el)).toContain('Ingia');
    expect(text(el)).not.toContain('Sign in');
  });

  it('the eye button shows and hides the password', async () => {
    const { fixture, el } = await open();
    const input = el.querySelector('#password') as HTMLInputElement;
    expect(input.type).toBe('password');
    (el.querySelector('.eye-btn') as HTMLButtonElement).click();
    await settle(fixture);
    expect(input.type).toBe('text');
  });

  describe('forgot password', () => {
    async function toForgot() {
      const o = await open();
      (o.el.querySelector('.forgot-link') as HTMLElement).click();
      await settle(o.fixture);

      return o;
    }

    it('texts a code to the phone on the account, then asks for the code and a new password', async () => {
      const { h, fixture, el } = await toForgot();
      type(el, '#forgotEmail', 'a@shop.test');
      type(el, '#forgotPhone', '0712345678');
      await settle(fixture);

      submit(el);
      const req = h.http.expectOne(`${environment.apiUrl}/auth/forgot-password`);
      expect(req.request.body).toEqual({ email: 'a@shop.test', phone_number: '0712345678' });
      req.flush({ status: 'success' });
      await settle(fixture);
      expect(text(el)).toContain('Check your phone');

      (Array.from(el.querySelectorAll('button')).find((b) => b.textContent?.includes('I have the code')) as HTMLButtonElement).click();
      await settle(fixture);
      expect(text(el)).toContain('New password');
    });

    it('says plainly when text messages are not available', async () => {
      const { h, fixture, el } = await toForgot();
      type(el, '#forgotEmail', 'a@shop.test');
      type(el, '#forgotPhone', '0712345678');
      await settle(fixture);
      submit(el);
      h.http.expectOne(`${environment.apiUrl}/auth/forgot-password`).flush({ message: 'Text messages are not available right now. Ask your administrator.' }, { status: 503, statusText: 'Unavailable' });
      await settle(fixture);
      expect(text(el.querySelector('.form-error') as HTMLElement)).toContain('not available right now');
    });

    it('checks the code, the length and that the two passwords match before it asks the server', async () => {
      const { h, fixture, el } = await toForgot();
      // go straight to the new-password form
      (el.querySelector('.back-btn') as HTMLElement).click();
      await settle(fixture);
      (el.querySelector('.forgot-link') as HTMLElement).click();
      await settle(fixture);
      type(el, '#forgotEmail', 'a@shop.test');
      type(el, '#forgotPhone', '0712345678');
      await settle(fixture);
      submit(el);
      h.http.expectOne(`${environment.apiUrl}/auth/forgot-password`).flush({});
      await settle(fixture);
      (Array.from(el.querySelectorAll('button')).find((b) => b.textContent?.includes('I have the code')) as HTMLButtonElement).click();
      await settle(fixture);

      type(el, '#resetCode', '12');
      type(el, '#newPassword', 'longenough1');
      type(el, '#confirmNewPassword', 'longenough1');
      await settle(fixture);
      submit(el);
      await settle(fixture);
      expect(text(el.querySelector('.form-error') as HTMLElement)).toContain('6-digit code');

      type(el, '#resetCode', '123456');
      type(el, '#newPassword', 'short');
      type(el, '#confirmNewPassword', 'short');
      await settle(fixture);
      submit(el);
      await settle(fixture);
      expect(text(el.querySelector('.form-error') as HTMLElement)).toContain('at least 8 characters');

      type(el, '#newPassword', 'longenough1');
      type(el, '#confirmNewPassword', 'different1');
      await settle(fixture);
      submit(el);
      await settle(fixture);
      expect(text(el.querySelector('.form-error') as HTMLElement)).toContain('not the same');
      h.http.expectNone((r) => r.url.endsWith('/reset-password'));

      type(el, '#confirmNewPassword', 'longenough1');
      await settle(fixture);
      submit(el);
      const req = h.http.expectOne(`${environment.apiUrl}/auth/reset-password`);
      expect(req.request.body).toEqual({ email: 'a@shop.test', code: '123456', password: 'longenough1', password_confirmation: 'longenough1' });
      req.flush({});
      await settle(fixture);
      expect(text(el)).toContain('Welcome'); // back at sign-in
      expect(TestBed.inject(ToastService).toasts()[0].title).toBe('Password changed');
    });
  });
});

describe('remember me', () => {
  it('fills the email in again the next time the page opens, so the next sign-in is the password alone', async () => {
    localStorage.clear();
    const first = await open();
    type(first.el, '#email', 'a@shop.test');
    type(first.el, '#password', 'secret');
    await settle(first.fixture);
    submit(first.el);
    first.h.http.expectOne(`${environment.apiUrl}/auth/login`).flush({ ...loginAnswer, data: { ...loginAnswer.data, user: { ...loginAnswer.data.user, role: 'viewer' } } });
    await settle(first.fixture);
    expect(localStorage.getItem('login_remembered_email')).toBe('a@shop.test');

    TestBed.resetTestingModule();
    const again = await open({ remembered: 'a@shop.test' });
    expect((again.el.querySelector('#email') as HTMLInputElement).value).toBe('a@shop.test');
  });

  it('forgets the email when "Remember me" is unticked', async () => {
    localStorage.clear();
    const { h, fixture, el } = await open();
    (byTestId(el, 'remember-me') as HTMLInputElement).click();
    type(el, '#email', 'a@shop.test');
    type(el, '#password', 'secret');
    await settle(fixture);
    submit(el);
    h.http.expectOne(`${environment.apiUrl}/auth/login`).flush({ ...loginAnswer, data: { ...loginAnswer.data, user: { ...loginAnswer.data.user, role: 'viewer' } } });
    await settle(fixture);
    expect(localStorage.getItem('login_remembered_email')).toBeNull();
  });
});
