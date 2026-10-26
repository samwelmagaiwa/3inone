import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AccountantApi } from '../../core/accountant-api.service';
import { AuthService } from '../../core/auth.service';
import { offline, serverMessage } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { ToastService } from '../../core/services/toast.service';

type LoginView = 'login' | 'forgot' | 'forgot-sent' | 'reset';

@Component({
  selector: 'app-login',
  imports: [FormsModule],
  templateUrl: './login.html',
})
export class LoginPage {
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
    if (!this.email.trim() || !this.cleanPhone() || !this.password) {
      this.error.set(t('login.incomplete'));
      return;
    }
    this.error.set('');
    this.loading.set(true);
    try {
      await this.auth.login(this.email.trim(), this.cleanPhone(), this.password);
      this.toastService.success(this.i18n.t('login.welcome', this.auth.user()?.name ?? ''), t('login.signed'));
      await this.router.navigate(['/']);
    } catch (err) {
      this.error.set(this.failure(err, 'login.failed'));
    } finally {
      this.loading.set(false);
    }
  }

  protected async onForgot(): Promise<void> {
    if (!this.email.trim() || !this.cleanPhone()) {
      this.error.set(this.i18n.t('login.incomplete'));
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
