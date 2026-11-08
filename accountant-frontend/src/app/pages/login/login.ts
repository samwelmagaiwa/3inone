import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AccountantApi } from '../../core/accountant-api.service';
import { AuthService } from '../../core/auth.service';
import { monthKey, monthName, offline, serverMessage, tsh } from '../../core/format';
import { headlineText } from '../../core/headline';
import { I18nService } from '../../core/i18n.service';
import { ToastService } from '../../core/services/toast.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';

type LoginView = 'login' | 'forgot' | 'forgot-sent' | 'reset';

@Component({
  selector: 'app-login',
  imports: [FormsModule, ModalDialogComponent],
  templateUrl: './login.html',
})
export class LoginPage implements OnInit {
  private readonly auth = inject(AuthService);
  private readonly api = inject(AccountantApi);
  private readonly router = inject(Router);
  protected readonly i18n = inject(I18nService);
  protected readonly toastService = inject(ToastService);

  protected readonly appName = environment.appName;

  // form fields
  protected email = '';
  protected phone = '';
  protected password = '';
  protected code = '';
  protected newPassword = '';
  protected confirmPassword = '';

  // screen state
  protected readonly view = signal<LoginView>('login');
  protected readonly loading = signal(false);
  protected readonly error = signal('');
  protected readonly showPassword = signal(false);

  /** The accountant's message on signing in: how the month is going. Pressing OK goes on to the dashboard. */
  protected readonly brief = signal<{ month: string; title: string; lines: string[] } | null>(null);

  /** "Remember me": the email last used on this computer is filled in again, so the next sign-in is the password alone. */
  protected remember = true;
  private static readonly REMEMBERED_KEY = 'login_remembered_email';

  ngOnInit(): void {
    try {
      const saved = localStorage.getItem(LoginPage.REMEMBERED_KEY);
      if (saved && !this.email) this.email = saved;
    } catch {
      // nothing remembered: the person types it
    }
  }

  private saveRemembered(): void {
    try {
      if (this.remember) localStorage.setItem(LoginPage.REMEMBERED_KEY, this.email.trim());
      else localStorage.removeItem(LoginPage.REMEMBERED_KEY);
    } catch {
      // not remembered this time
    }
  }

  protected togglePassword(): void {
    this.showPassword.update((v) => !v);
  }

  protected showForgot(): void {
    this.view.set('forgot');
    this.error.set('');
  }

  protected showLogin(): void {
    this.view.set('login');
    this.error.set('');
  }

  /** A phone number as typed for readability ("0712 345 678") without the spaces and dashes the server does not want. */
  private cleanPhone(): string {
    return this.phone.replace(/[\s-]/g, '');
  }

  private failure(err: unknown, fallbackKey: string): string {
    return offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t(fallbackKey));
  }

  protected async onLogin(): Promise<void> {
    const t = (k: string) => this.i18n.t(k);
    if (!this.email.trim() || !this.password) {
      this.error.set(t('login.incomplete'));
      return;
    }
    this.error.set('');
    this.loading.set(true);
    try {
      await this.auth.login(this.email.trim(), this.password);
      this.saveRemembered();
      this.toastService.success(this.i18n.t('login.welcome', this.auth.user()?.name ?? ''), t('login.signed'));
      if (!(await this.showBrief())) await this.router.navigate(['/']);
    } catch (err) {
      this.error.set(this.failure(err, 'login.failed'));
    } finally {
      this.loading.set(false);
    }
  }

  /** For an accountant: asks how this month compares with the last and shows it. False when there is nothing to show (or no signal). */
  private async showBrief(): Promise<boolean> {
    if (this.auth.user()?.role !== 'accountant') return false;
    try {
      const month = monthKey(new Date());
      const r = await firstValueFrom(this.api.monthlyReport(month));
      if (r.is_future) return false;
      // Profit is the owner's: an accountant is told how the sales compare instead.
      const ownerView = r.owner_figures !== false;
      const lines = [(ownerView ? this.i18n.t('headline.profit', tsh(r.compare.net_profit.now), tsh(r.compare.net_profit.before)) : this.i18n.t('headline.sales', tsh(r.compare.sales.now), tsh(r.compare.sales.before))) + (r.previous.like_for_like ? ` · ${this.i18n.t('headline.samedays')}` : '')];
      if (r.is_current) lines.push(this.i18n.t('headline.inprogress', r.days_elapsed, r.days_in_month));
      this.brief.set({ month: monthName(month, this.i18n.locale()), title: headlineText(r, this.i18n), lines });

      return true;
    } catch {
      return false; // no message is better than a sign-in that waits on it
    }
  }

  /** OK on the message: on to the dashboard. */
  protected async proceed(): Promise<void> {
    this.brief.set(null);
    await this.router.navigate(['/']);
  }

  protected async onForgot(): Promise<void> {
    if (!this.email.trim() || !this.cleanPhone()) {
      this.error.set(this.i18n.t('forgot.incomplete'));
      return;
    }
    this.error.set('');
    this.loading.set(true);
    try {
      await firstValueFrom(this.api.forgotPassword(this.email.trim(), this.cleanPhone()));
      this.view.set('forgot-sent');
    } catch (err) {
      this.error.set(this.failure(err, 'forgot.failed'));
    } finally {
      this.loading.set(false);
    }
  }

  protected async onReset(): Promise<void> {
    const t = (k: string) => this.i18n.t(k);
    if (!this.email.trim() || !/^\d{6}$/.test(this.code.trim()) || !this.newPassword) {
      this.error.set(t('reset.incomplete'));
      return;
    }
    if (this.newPassword.length < 8) {
      this.error.set(t('reset.short'));
      return;
    }
    if (this.newPassword !== this.confirmPassword) {
      this.error.set(t('reset.mismatch'));
      return;
    }
    this.error.set('');
    this.loading.set(true);
    try {
      await firstValueFrom(this.api.resetPassword(this.email.trim(), this.code.trim(), this.newPassword));
      this.toastService.success(t('reset.done'), t('reset.done.title'));
      this.password = '';
      this.view.set('login');
    } catch (err) {
      this.error.set(this.failure(err, 'reset.failed'));
    } finally {
      this.loading.set(false);
    }
  }
}
