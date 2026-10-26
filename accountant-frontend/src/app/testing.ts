import { Provider } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { provideRouter } from '@angular/router';

import { authInterceptor } from './core/auth.interceptor';
import { AuthService } from './core/auth.service';
import { I18nService } from './core/i18n.service';
import { ServiceName, SessionUser } from './core/models';
import { ConfirmService } from './core/services/confirm.service';
import { ToastService } from './core/services/toast.service';

/** Helpers shared by the specs. Not part of the app. */

export function user(over: Partial<SessionUser> = {}): SessionUser {
  return {
    id: '1',
    name: 'Amina Hassan',
    email: 'amina@shop.test',
    role: 'accountant',
    roleLabel: 'Accountant',
    phone: '0712345678',
    services: ['inventory'],
    otherServices: [],
    permissions: ['inv_view_reports', 'inv_view_credit', 'inv_view_expenses', 'inv_manage_expenses', 'inv_create_sales', 'inv_manage_sales'],
    business: 'Mama Shop',
    ...over,
  };
}

export interface Harness {
  auth: AuthService;
  i18n: I18nService;
  http: HttpTestingController;
  confirmAnswer: { value: boolean };
}

/** The testing module with the real interceptor, a signed-in person, English, and a ConfirmService that answers as told. */
export function configure(who: Partial<SessionUser> | null = {}, extra: Provider[] = []): Harness {
  localStorage.clear();
  const confirmAnswer = { value: true };
  TestBed.configureTestingModule({
    providers: [
      provideRouter([]),
      provideHttpClient(withInterceptors([authInterceptor])),
      provideHttpClientTesting(),
      { provide: ConfirmService, useValue: { ask: async () => confirmAnswer.value, notify: async () => undefined } },
      ...extra,
    ],
  });
  const auth = TestBed.inject(AuthService);
  const i18n = TestBed.inject(I18nService);
  i18n.setLang('en');
  if (who !== null) {
    const u = user(who);
    auth.token.set('TOKEN');
    auth.user.set(u);
    auth.service.set((u.services[0] ?? 'inventory') as ServiceName);
  }
  return { auth, i18n, http: TestBed.inject(HttpTestingController), confirmAnswer };
}

/** Let promises settle, then draw the page. */
export async function settle(fixture: ComponentFixture<unknown>): Promise<void> {
  await fixture.whenStable();
  fixture.detectChanges();
  await fixture.whenStable();
  fixture.detectChanges();
}

export function text(el: HTMLElement): string {
  return (el.textContent ?? '').replace(/\s+/g, ' ').trim();
}

export function byTestId(el: HTMLElement, id: string): HTMLElement | null {
  return el.querySelector(`[data-testid="${id}"]`);
}

/** Type into an input the way a person does (Angular forms listen for the input event). */
export function type(el: HTMLElement, selector: string, value: string): void {
  const input = el.querySelector(selector) as HTMLInputElement;
  input.value = value;
  input.dispatchEvent(new Event('input', { bubbles: true }));
}

/** The messages shown to the person so far (the shell draws them; page tests read them here). */
export function toasts(): string[] {
  return TestBed.inject(ToastService)
    .toasts()
    .map((t) => t.message);
}
