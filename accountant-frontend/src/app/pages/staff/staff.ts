import { HttpClient } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';

import { environment } from '../../../environments/environment';
import { AuthService } from '../../core/auth.service';
import { offline, serverMessage } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { MotionService } from '../../core/services/motion.service';
import { ToastService } from '../../core/services/toast.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';

const API = environment.apiUrl;

/** One person of the business, as the server lists them. */
export interface StaffMember {
  id: string;
  name: string;
  email: string;
  phone: string;
  role: string;
  active: boolean;
}

/** The roles a salon gives its people, and the ones a shop or depot gives. The server decides again what each may do. */
export const SALON_ROLES = ['manager', 'accountant', 'hair_stylist', 'nail_technician', 'lash_makeup_artist', 'viewer'];
export const SHOP_ROLES = ['manager', 'sales_officer', 'accountant', 'operator', 'viewer'];

/**
 * The first password a new person gets, the same one the phone makes: the last word of the name in capitals, repeated to 8 letters
 * ("Asha Juma" -> "JUMAJUMA"). They must choose their own at first sign-in.
 */
export function defaultPassword(fullName: string): string {
  const words = fullName.trim().split(/\s+/).filter(Boolean);
  const base = (words.length ? words[words.length - 1] : '').toUpperCase().replace(/[^A-Z0-9]/g, '') || 'PASSWORD';
  let pwd = base;
  while (pwd.length < 8) pwd += base;

  return pwd.slice(0, 8);
}

const text = (v: unknown): string => (v === null || v === undefined ? '' : String(v));

export function readStaff(j: unknown): StaffMember[] {
  const o = j && typeof j === 'object' ? (j as Record<string, unknown>) : {};
  const data = o['data'] && typeof o['data'] === 'object' ? (o['data'] as Record<string, unknown>) : {};
  const list = Array.isArray(data['users']) ? (data['users'] as unknown[]) : [];

  return list.map((u) => {
    const x = (u && typeof u === 'object' ? u : {}) as Record<string, unknown>;

    return { id: text(x['id']), name: text(x['name']), email: text(x['email']), phone: text(x['phone_number']), role: text(x['role']), active: x['is_active'] === true || x['is_active'] === 1 };
  });
}

/**
 * The business owner registers their people here: a name, a phone number, an email (the name they sign in with) and a role, in the service
 * they are working in. The first password is made from the name and shown once. The owner can also switch a person off (and on again) and give
 * them a new first password. Only the owner sees this page, and the server checks that again.
 */
@Component({
  selector: 'app-staff',
  imports: [RowMenuComponent, FormsModule, ModalDialogComponent],
  templateUrl: './staff.html',
})
export class StaffPage implements OnInit {
  private readonly http = inject(HttpClient);
  private readonly toast = inject(ToastService);
  private readonly confirm = inject(ConfirmService);
  protected readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);
  protected readonly motion = inject(MotionService);

  protected readonly rows = signal<StaffMember[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly roles = computed(() => (this.auth.service() === 'salon' ? SALON_ROLES : SHOP_ROLES));

  protected readonly formOpen = signal(false);
  protected name = '';
  protected email = '';
  protected phone = '';
  protected role = '';
  protected readonly formError = signal('');
  protected readonly saving = signal(false);
  /** What a new person (or a reset) was given, shown once: "Asha / JUMAJUMA". */
  protected readonly given = signal<{ name: string; email: string; password: string } | null>(null);

  ngOnInit(): void {
    void this.load();
  }

  /** The three dots of a person's row: a new first password, and switch off / on. */
  protected menuFor(p: { id: string; active: boolean }): MenuItem[] {
    return [
      { id: 'reset', label: this.i18n.t('st.reset'), testid: 'st-reset-' + p.id },
      { id: 'toggle', label: this.i18n.t(p.active ? 'st.switchoff' : 'st.switchon'), danger: p.active, primary: !p.active, testid: 'st-toggle-' + p.id },
    ];
  }

  protected picked(id: string, p: StaffMember): void {
    if (id === 'reset') void this.reset(p);
    else void this.setActive(p, !p.active);
  }

  protected roleName(role: string): string {
    const key = 'role.' + role;
    const word = this.i18n.t(key);

    return word === key ? role : word;
  }

  protected async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.rows.set(readStaff(await firstValueFrom(this.http.get(`${API}/admin/users/mine`, { params: { created_by: 'me', limit: '200' } }))));
    } catch (err) {
      this.error.set(this.messageOf(err));
    } finally {
      this.loading.set(false);
    }
  }

  protected openForm(): void {
    this.name = '';
    this.email = '';
    this.phone = '';
    this.role = this.roles()[0];
    this.formError.set('');
    this.formOpen.set(true);
  }

  protected passwordFor(): string {
    return defaultPassword(this.name);
  }

  protected async save(): Promise<void> {
    const name = this.name.trim();
    const email = this.email.trim();
    const phone = this.phone.trim();
    if (name.length < 2) return this.formError.set(this.i18n.t('st.err.name'));
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return this.formError.set(this.i18n.t('st.err.email'));
    if (phone.length < 7) return this.formError.set(this.i18n.t('st.err.phone'));
    const service = this.auth.service();
    const password = defaultPassword(name);
    this.saving.set(true);
    this.formError.set('');
    try {
      await firstValueFrom(
        this.http.post(`${API}/admin/users`, {
          name,
          email,
          phone_number: phone,
          role: this.role,
          is_active: true,
          password,
          password_confirmation: password,
          service_types: service ? [service] : [],
        }),
      );
      this.formOpen.set(false);
      this.given.set({ name, email, password });
      await this.load();
    } catch (err) {
      this.formError.set(this.messageOf(err));
    } finally {
      this.saving.set(false);
    }
  }

  protected async setActive(p: StaffMember, active: boolean): Promise<void> {
    try {
      await firstValueFrom(this.http.put(`${API}/admin/users/${p.id}`, { is_active: active }));
      this.toast.success(this.i18n.t(active ? 'st.on.done' : 'st.off.done', p.name), this.i18n.t('common.done'));
      await this.load();
    } catch (err) {
      this.toast.error(this.messageOf(err), this.i18n.t('error.title'));
    }
  }

  protected async reset(p: StaffMember): Promise<void> {
    const password = defaultPassword(p.name);
    const yes = await this.confirm.ask({
      title: this.i18n.t('st.reset.title'),
      message: this.i18n.t('st.reset.message', p.name, password),
      confirmLabel: this.i18n.t('st.reset'),
      cancelLabel: this.i18n.t('common.keep'),
      danger: false,
    });
    if (!yes) return;
    try {
      await firstValueFrom(this.http.post(`${API}/admin/users/${p.id}/reset-password`, { password, password_confirmation: password }));
      this.given.set({ name: p.name, email: p.email, password });
    } catch (err) {
      this.toast.error(this.messageOf(err), this.i18n.t('error.title'));
    }
  }

  private messageOf(err: unknown): string {
    return offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic'));
  }
}
