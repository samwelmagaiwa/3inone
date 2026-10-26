import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';

import { environment } from '../../../environments/environment';
import { ToastService } from '../../core/services/toast.service';
import { configure, settle, text, type } from '../../testing';
import { LoginPage } from './login';

async function open() {
  const h = configure(null);
  const navigate = vi.spyOn(TestBed.inject(Router), 'navigate').mockResolvedValue(true);
  const fixture = TestBed.createComponent(LoginPage);
  fixture.detectChanges();
  await settle(fixture);

  return { h, navigate, fixture, el: fixture.nativeElement as HTMLElement };
}

const submit = (el: HTMLElement) => (el.querySelector('form') as HTMLFormElement).dispatchEvent(new Event('submit'));

const loginAnswer = { status: 'success', message: 'ok', data: { token: 'T', user: { id: 1, name: 'Amina Hassan', email: 'a@shop.test', role: 'accountant', services: [{ service_type: 'inventory' }], effective_permissions: ['inv_view_reports'] } } };

describe('sign-in page', () => {
  it('has no phone number written into it: the hint is words, not a number', async () => {
    const { el } = await open();
    const phone = el.querySelector('#phone') as HTMLInputElement;
    expect(phone.placeholder).not.toMatch(/\d{6}/);
    expect(text(el)).not.toMatch(/0\d{9}|\+255\d{9}/);
    expect(text(el)).toContain('The phone number saved on your account.');
  });

  it('asks for all three details before it asks the server', async () => {
    const { h, fixture, el } = await open();

    type(el, '#email', 'a@shop.test');
    submit(el);
    await settle(fixture);

    expect(text(el.querySelector('.form-error') as HTMLElement)).toBe('Please fill in your email, phone number and password.');
    h.http.expectNone(() => true);
  });

  it('sends the details (spaces in the phone number are dropped), welcomes the person and opens their first page', async () => {
    const { h, navigate, fixture, el } = await open();

    type(el, '#email', ' a@shop.test ');
    type(el, '#phone', '0712 345-678');
    type(el, '#password', 'secret');
    await settle(fixture);
    submit(el);
    const req = h.http.expectOne(`${environment.apiUrl}/auth/login`);
    expect(req.request.body).toEqual({ email: 'a@shop.test', phone_number: '0712345678', password: 'secret' });
    req.flush(loginAnswer);
    await settle(fixture);

    expect(navigate).toHaveBeenCalledWith(['/']);
    expect(TestBed.inject(ToastService).toasts()[0].message).toBe('Welcome back, Amina Hassan.');
  });

  it('shows the server\'s own words when sign-in fails, and plain words when the server cannot be reached', async () => {
    const { h, fixture, el } = await open();
    type(el, '#email', 'a@shop.test');
    type(el, '#phone', '0712345678');
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
