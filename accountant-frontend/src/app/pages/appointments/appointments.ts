import { HttpClient } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AuthService } from '../../core/auth.service';
import { dayOf, serverMessage, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';

const API = environment.apiUrl;

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {});
const text = (v: unknown): string => (v === null || v === undefined ? '' : String(v));

export interface ApptService {
  productId: number;
  name: string;
  price: number;
  minutes: number | null;
  label: string | null;
}

export interface Appointment {
  id: number;
  clientName: string;
  clientPhone: string | null;
  staffId: string | null;
  staffName: string | null;
  startsAt: string; // 2026-11-14 09:00
  endsAt: string;
  status: string;
  services: ApptService[];
  notes: string | null;
  total: number;
  online: boolean;
  deposit: number;
  depositStatus: string | null;
}

const ACTIVE = ['booked', 'confirmed', 'in_progress'];

/** One appointment as the server sends it, read the way the phone reads it. */
export function readAppointment(j: Record<string, unknown>): Appointment {
  const dep = obj(j['deposit']);
  const services = Array.isArray(j['services']) ? (j['services'] as unknown[]) : [];

  return {
    id: num(j['id']),
    clientName: text(j['client_name']),
    clientPhone: text(j['client_phone']) || null,
    staffId: j['staff_id'] === null || j['staff_id'] === undefined ? null : text(j['staff_id']),
    staffName: text(j['staff_name']) || null,
    startsAt: text(j['starts_at']),
    endsAt: text(j['ends_at']),
    status: text(j['status']) || 'booked',
    services: services.map((s) => {
      const o = obj(s);

      return { productId: num(o['product_id']), name: text(o['name']), price: num(o['price']), minutes: o['minutes'] === null || o['minutes'] === undefined ? null : num(o['minutes']), label: text(o['label']) || null };
    }),
    notes: text(j['notes']) || null,
    total: num(j['total']),
    online: text(j['source']) === 'online',
    deposit: num(dep['amount']),
    depositStatus: dep['status'] ? text(dep['status']) : null,
  };
}

export const isActive = (a: Appointment): boolean => ACTIVE.includes(a.status);

/** "2026-11-14 09:30" (or an ISO stamp) -> "09:30". */
export function hm(stamp: string): string {
  const m = /(\d{2}):(\d{2})/.exec(stamp.slice(10));

  return m ? `${m[1]}:${m[2]}` : '';
}

interface ServiceChoice {
  id: number;
  name: string;
  price: number;
  minutes: number | null;
  staffIds: string[];
  options: { label: string; price: number }[];
  active: boolean;
}

interface Staff {
  id: string;
  name: string;
}

@Component({
  selector: 'app-appointments',
  imports: [FormsModule, ModalDialogComponent],
  template: `
    <div class="ad ph-page" data-testid="appointments-page">
      <div class="ph-row">
        <button type="button" class="btn-outline ph-btn" (click)="go(-1)" data-testid="appt-prev" [attr.aria-label]="i18n.t('ap.prev')">‹</button>
        <div style="text-align: center">
          <input type="date" class="ap-day" [ngModel]="day()" (ngModelChange)="setDay($event)" data-testid="appt-day" />
          <p class="ph-muted">{{ isToday() ? i18n.t('pl.p.today') : weekday() }}</p>
        </div>
        <button type="button" class="btn-outline ph-btn" (click)="go(1)" data-testid="appt-next" [attr.aria-label]="i18n.t('ap.next')">›</button>
      </div>
      @if (!isToday()) { <button type="button" class="btn-outline ph-btn" (click)="setDay(todayKey)" data-testid="appt-today">{{ i18n.t('ap.back.today') }}</button> }
      @if (!stylist()) { <button type="button" class="btn-primary ph-btn" (click)="openForm(null)" data-testid="appt-add">{{ i18n.t('ap.book') }}</button> }

      @if (settings(); as s) {
        <section class="ph-card ph-row"><span>{{ i18n.t('ap.remind') }}</span><input type="checkbox" [checked]="s.reminders" (change)="switchSetting('appointment_reminders', $any($event.target).checked)" data-testid="appt-reminders" /></section>
        @if (auth.can('inv_salon_money')) {
          <section class="ph-card ph-row"><span>{{ i18n.t('ap.daily') }}</span><input type="checkbox" [checked]="s.daily" (change)="switchSetting('daily_summary', $any($event.target).checked)" data-testid="appt-daily" /></section>
        }
      }

      @if (error()) {
        <section class="ph-card"><p data-testid="appt-error">{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (loading()) {
        <section class="ph-card"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else if (!items().length) {
        <section class="ph-card"><p class="ph-muted" data-testid="appt-empty">{{ i18n.t('ap.empty') }}</p></section>
      } @else {
        <p class="ph-muted" data-testid="appt-count">{{ i18n.t('ap.count', items().length) }}</p>
        @for (a of items(); track a.id) {
          <section class="ph-card" [style.opacity]="isActive(a) || a.status === 'done' ? 1 : 0.6" [attr.data-testid]="'appt-' + a.id">
            <div class="ph-row"><b class="ph-accent">{{ hm(a.startsAt) }}–{{ hm(a.endsAt) }}</b><span class="ph-badge" [class]="statusClass(a.status)">{{ statusName(a.status) }}</span></div>
            <h3>{{ a.clientName }}</h3>
            @if (a.clientPhone) { <p class="ph-muted">{{ a.clientPhone }}</p> }
            <p class="ph-muted">{{ servicesText(a) }}</p>
            <div class="ph-row"><span [class.ph-warn]="!a.staffName" class="ph-muted">{{ a.staffName ?? i18n.t('ap.no.stylist') }}</span><b>{{ tsh(a.total) }}</b></div>
            @if (a.online) { <span class="ph-badge ph-accent">{{ i18n.t('ap.online') }}</span> }
            @if (a.deposit > 0) { <span class="ph-badge ph-warn">{{ i18n.t('ap.deposit') }} {{ tsh(a.deposit) }}</span> }
            @if (a.notes) { <p class="ph-muted"><i>{{ a.notes }}</i></p> }
            <div class="ap-actions">
              @if (a.status === 'booked') { <button type="button" class="btn-outline ph-btn" (click)="setStatus(a, 'confirmed')" [attr.data-testid]="'appt-confirm-' + a.id">{{ i18n.t('ap.confirm') }}</button> }
              @if (a.status === 'booked' || a.status === 'confirmed') { <button type="button" class="btn-outline ph-btn" (click)="setStatus(a, 'in_progress')" [attr.data-testid]="'appt-start-' + a.id">{{ i18n.t('ap.start') }}</button> }
              @if (isActive(a)) { <button type="button" class="btn-primary ph-btn" (click)="setStatus(a, 'done')" [attr.data-testid]="'appt-done-' + a.id">{{ i18n.t('ap.done') }}</button> }
              @if (isActive(a) && !stylist()) { <button type="button" class="btn-outline ph-btn" (click)="openForm(a)" [attr.data-testid]="'appt-edit-' + a.id">{{ i18n.t('ap.edit') }}</button> }
              @if (!stylist() && (a.status === 'booked' || a.status === 'confirmed')) { <button type="button" class="btn-outline ph-btn" (click)="setStatus(a, 'no_show')">{{ i18n.t('ap.noshow') }}</button> }
              @if (isActive(a) && !stylist()) { <button type="button" class="btn-outline ph-btn" (click)="setStatus(a, 'cancelled')" [attr.data-testid]="'appt-cancel-' + a.id">{{ i18n.t('ap.cancel') }}</button> }
            </div>
            @if (!isActive(a)) { <p class="ph-muted">{{ i18n.t('ap.finished') }}</p> }
          </section>
        }
      }
    </div>

    <app-modal-dialog [show]="formOpen()" [eyebrow]="i18n.t('nav.ph.appointments')" [title]="editing() ? i18n.t('ap.form.edit') : i18n.t('ap.form.new')" size="md" (close)="formOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 12px">
        <label class="ph-field">{{ i18n.t('ap.client') }}<input class="modal-input" [ngModel]="fName()" (ngModelChange)="fName.set($event)" data-testid="appt-name" name="apName" /></label>
        <label class="ph-field">{{ i18n.t('ap.phone') }}<input class="modal-input" type="tel" [ngModel]="fPhone()" (ngModelChange)="fPhone.set($event)" data-testid="appt-phone" name="apPhone" /></label>
        <div class="ph-row" style="gap: 10px">
          <label class="ph-field" style="flex: 1">{{ i18n.t('ap.date') }}<input class="modal-input" type="date" [ngModel]="fDate()" (ngModelChange)="fDate.set($event)" data-testid="appt-date" name="apDate" /></label>
          <label class="ph-field" style="flex: 1">{{ i18n.t('ap.time') }}<input class="modal-input" type="time" [ngModel]="fTime()" (ngModelChange)="fTime.set($event)" data-testid="appt-time" name="apTime" /></label>
        </div>
        <div>
          <p class="ph-field">{{ i18n.t('ap.services') }}</p>
          @for (s of fServices(); track $index) {
            <div class="ph-row ph-card" style="margin-top: 6px; padding: 6px 12px"><span>{{ s.label ? s.name + ' (' + s.label + ')' : s.name }}</span><span><b>{{ tsh(s.price) }}</b> <button type="button" class="btn-outline" style="padding: 0 8px" (click)="removeService($index)" [attr.data-testid]="'appt-remove-' + $index">×</button></span></div>
          }
          <select class="modal-input" style="margin-top: 6px" (change)="addService($any($event.target).value); $any($event.target).value = ''" data-testid="appt-add-service" name="apSvc">
            <option value="">{{ i18n.t('ap.add.service') }}</option>
            @for (c of choices(); track c.id) { @if (c.options.length) { @for (o of c.options; track o.label) { <option [value]="c.id + '|' + o.label">{{ c.name }} ({{ o.label }}) · {{ tsh(o.price) }}</option> } } @else { <option [value]="c.id + '|'">{{ c.name }} · {{ tsh(c.price) }}</option> } }
          </select>
        </div>
        <label class="ph-field">{{ i18n.t('ap.stylist') }}
          <select class="modal-input" [ngModel]="fStaff()" (ngModelChange)="fStaff.set($event)" data-testid="appt-staff" name="apStaff">
            <option value="">{{ i18n.t('ap.not.yet') }}</option>
            @for (m of eligible(); track m.id) { <option [value]="m.id">{{ m.name }}</option> }
          </select>
        </label>
        <label class="ph-field">{{ i18n.t('ap.notes') }}<textarea class="modal-input" rows="2" [ngModel]="fNotes()" (ngModelChange)="fNotes.set($event)" name="apNotes"></textarea></label>
        @if (formError()) { <p class="ph-bad" data-testid="appt-form-error">{{ formError() }}</p> }
      </div>
      <div slot="footer" class="flex gap-2 justify-end">
        <button type="button" class="modal-cancel-btn" (click)="formOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        @if (clash()) { <button type="button" class="btn-outline" (click)="save(true)" data-testid="appt-force">{{ i18n.t('ap.book.anyway') }}</button> }
        <button type="button" class="btn-primary" [disabled]="saving()" (click)="save(false)" data-testid="appt-save">{{ saving() ? i18n.t('common.saving') : i18n.t('ap.save') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [
    `
      .ap-day { padding: 6px 10px; border-radius: 10px; font-weight: 800; text-align: center; }
      .ap-actions { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; }
    `,
  ],
})
export class AppointmentsPage implements OnInit {
  private readonly http = inject(HttpClient);
  protected readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);
  protected readonly tsh = tsh;
  protected readonly hm = hm;
  protected readonly isActive = isActive;
  protected readonly todayKey = dayOf(new Date());

  protected readonly day = signal(dayOf(new Date()));
  protected readonly items = signal<Appointment[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal('');
  protected readonly settings = signal<{ reminders: boolean; daily: boolean } | null>(null);
  private asked = 0;

  protected readonly isToday = computed(() => this.day() === this.todayKey);
  /** A stylist works the diary; booking is for the reception and the owner. */
  protected readonly stylist = computed(() => ['hair_stylist', 'nail_technician', 'lash_makeup_artist'].includes((this.auth.user()?.role ?? '').toLowerCase()));

  protected readonly weekday = computed(() => {
    const [y, m, d] = this.day().split('-').map(Number);

    return new Date(y, m - 1, d).toLocaleDateString(this.i18n.lang() === 'sw' ? 'sw-TZ' : 'en-GB', { weekday: 'long' });
  });

  // the form
  protected readonly formOpen = signal(false);
  protected readonly editing = signal<Appointment | null>(null);
  protected readonly fName = signal('');
  protected readonly fPhone = signal('');
  protected readonly fDate = signal(dayOf(new Date()));
  protected readonly fTime = signal('09:00');
  protected readonly fServices = signal<ApptService[]>([]);
  protected readonly fStaff = signal('');
  protected readonly fNotes = signal('');
  protected readonly formError = signal('');
  protected readonly clash = signal(false);
  protected readonly saving = signal(false);
  protected readonly choices = signal<ServiceChoice[]>([]);
  private readonly staff = signal<Staff[]>([]);

  /** The people who may do every chosen service (a service that names nobody may be done by anyone). */
  protected readonly eligible = computed(() => {
    const limits = this.fServices()
      .map((s) => this.choices().find((c) => c.id === s.productId)?.staffIds ?? [])
      .filter((l) => l.length > 0);

    return this.staff().filter((m) => limits.every((l) => l.includes(m.id)));
  });

  ngOnInit(): void {
    void this.load();
    void this.loadSettings();
  }

  protected setDay(d: string): void {
    if (!d) return;
    this.day.set(d);
    void this.load();
  }

  protected go(by: number): void {
    const [y, m, d] = this.day().split('-').map(Number);
    this.setDay(dayOf(new Date(y, m - 1, d + by)));
  }

  protected servicesText(a: Appointment): string {
    return a.services.map((s) => (s.label ? `${s.name} (${s.label})` : s.name)).join(', ');
  }

  protected statusName(s: string): string {
    switch (s) {
      case 'confirmed': return this.i18n.t('ap.s.confirmed');
      case 'in_progress': return this.i18n.t('ap.s.progress');
      case 'done': return this.i18n.t('ap.s.done');
      case 'cancelled': return this.i18n.t('ap.s.cancelled');
      case 'no_show': return this.i18n.t('ap.s.noshow');
      default: return this.i18n.t('ap.s.booked');
    }
  }

  protected statusClass(s: string): string {
    switch (s) {
      case 'confirmed': return 'ph-accent';
      case 'in_progress': return 'ph-warn';
      case 'done': return 'ph-good';
      case 'cancelled':
      case 'no_show': return 'ph-bad';
      default: return '';
    }
  }

  async load(): Promise<void> {
    const asked = this.day();
    const ticket = ++this.asked;
    this.loading.set(true);
    this.error.set('');
    try {
      const r = await firstValueFrom(this.http.get<{ data?: unknown[] }>(`${API}/inventory/salon/appointments`, { params: { date: asked } }));
      if (ticket !== this.asked) return;
      this.items.set((r.data ?? []).map((x) => readAppointment(obj(x))));
    } catch {
      if (ticket !== this.asked) return;
      this.error.set(this.i18n.t('pl.error'));
    }
    if (ticket === this.asked) this.loading.set(false);
  }

  private async loadSettings(): Promise<void> {
    try {
      const r = await firstValueFrom(this.http.get<{ data?: Record<string, unknown> }>(`${API}/inventory/salon/settings`));
      const d = obj(r.data);
      this.settings.set({ reminders: d['appointment_reminders'] === true || d['appointment_reminders'] === 1, daily: d['daily_summary'] === true || d['daily_summary'] === 1 });
    } catch {
      // the diary works without it: the switches stay hidden
    }
  }

  protected async switchSetting(key: 'appointment_reminders' | 'daily_summary', on: boolean): Promise<void> {
    const before = this.settings();
    if (!before) return;
    this.settings.set(key === 'appointment_reminders' ? { ...before, reminders: on } : { ...before, daily: on });
    try {
      await firstValueFrom(this.http.put(`${API}/inventory/salon/settings`, { [key]: on }));
    } catch {
      this.settings.set(before);
    }
  }

  protected async setStatus(a: Appointment, status: string): Promise<void> {
    this.error.set('');
    try {
      await firstValueFrom(this.http.post(`${API}/inventory/salon/appointments/${a.id}/status`, { status }));
      await this.load();
    } catch {
      this.error.set(this.i18n.t('pl.error'));
    }
  }

  protected async openForm(a: Appointment | null): Promise<void> {
    this.editing.set(a);
    this.formError.set('');
    this.clash.set(false);
    this.fName.set(a?.clientName ?? '');
    this.fPhone.set(a?.clientPhone ?? '');
    this.fDate.set(a ? a.startsAt.slice(0, 10) : this.day());
    this.fTime.set(a ? hm(a.startsAt) : '09:00');
    this.fServices.set(a ? a.services.map((s) => ({ ...s })) : []);
    this.fStaff.set(a?.staffId ?? '');
    this.fNotes.set(a?.notes ?? '');
    this.formOpen.set(true);
    await Promise.all([this.loadChoices(), this.loadStaff()]);
  }

  private async loadChoices(): Promise<void> {
    if (this.choices().length) return;
    try {
      const r = await firstValueFrom(this.http.get<{ data?: unknown[] }>(`${API}/inventory/products`, { params: { is_service: '1', per_page: '200' } }));
      this.choices.set(
        (r.data ?? []).map((x) => {
          const o = obj(x);
          const opts = Array.isArray(o['price_options']) ? (o['price_options'] as unknown[]) : [];

          return {
            id: num(o['id']),
            name: text(o['name']),
            price: num(o['selling_price']),
            minutes: o['duration_minutes'] === null || o['duration_minutes'] === undefined ? null : num(o['duration_minutes']),
            staffIds: Array.isArray(o['staff_ids']) ? (o['staff_ids'] as unknown[]).map(text) : [],
            options: opts.map((p) => ({ label: text(obj(p)['label']), price: num(obj(p)['price']) })),
            active: text(o['status']) !== 'inactive',
          };
        }).filter((c) => c.active),
      );
    } catch {
      // the list stays empty: the form says so
    }
  }

  private async loadStaff(): Promise<void> {
    if (this.staff().length) return;
    try {
      const r = await firstValueFrom(this.http.get<{ data?: unknown[] }>(`${API}/inventory/salon/staff`));
      this.staff.set((r.data ?? []).map((x) => ({ id: text(obj(x)['id']), name: text(obj(x)['name']) })));
    } catch {
      // booking works without naming a stylist
    }
  }

  protected addService(value: string): void {
    if (!value) return;
    const [id, label] = value.split('|');
    const c = this.choices().find((x) => x.id === Number(id));
    if (!c) return;
    const opt = label ? c.options.find((o) => o.label === label) : undefined;
    this.fServices.update((l) => [...l, { productId: c.id, name: c.name, price: opt?.price ?? c.price, minutes: c.minutes, label: opt?.label ?? null }]);
    if (this.fStaff() && !this.eligible().some((m) => m.id === this.fStaff())) this.fStaff.set('');
  }

  protected removeService(i: number): void {
    this.fServices.update((l) => l.filter((_, k) => k !== i));
  }

  protected async save(force: boolean): Promise<void> {
    if (!this.fName().trim()) {
      this.formError.set(this.i18n.t('ap.err.name'));
      return;
    }
    if (!this.fServices().length) {
      this.formError.set(this.i18n.t('ap.err.service'));
      return;
    }
    this.saving.set(true);
    this.formError.set('');
    const body = {
      client_name: this.fName().trim(),
      client_phone: this.fPhone().trim(),
      staff_id: this.fStaff() || null,
      starts_at: `${this.fDate()} ${this.fTime()}`,
      services: this.fServices().map((s) => ({ product_id: s.productId, price: s.price, ...(s.label ? { label: s.label } : {}) })),
      notes: this.fNotes().trim(),
      ...(force ? { force: true } : {}),
    };
    try {
      const a = this.editing();
      await firstValueFrom(a ? this.http.put(`${API}/inventory/salon/appointments/${a.id}`, body) : this.http.post(`${API}/inventory/salon/appointments`, body));
      this.saving.set(false);
      this.formOpen.set(false);
      this.day.set(this.fDate());
      await this.load();
    } catch (e) {
      this.saving.set(false);
      const msg = serverMessage(e) || this.i18n.t('pl.error');
      this.formError.set(msg);
      // the stylist is booked then, off that day or on other hours: say so, and let the owner book anyway if they mean it
      this.clash.set(!force && /\d{1,2}:\d{2}-\d{1,2}:\d{2}|\d{2}\/\d{2}\/\d{4}/.test(msg));
    }
  }
}
