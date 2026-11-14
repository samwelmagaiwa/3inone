import { HttpClient } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { parseAmount, serverMessage } from '../../core/format';
import { I18nService } from '../../core/i18n.service';

const API = environment.apiUrl;

const text = (v: unknown): string => (v === null || v === undefined ? '' : String(v));
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {});
export const on = (v: unknown): boolean => v === true || v === 1 || v === '1' || v === 'true';

/** The switches of the salon, with the field each one saves. */
export const SWITCHES: { field: string; title: string; sub: string; group: 'texts' | 'owner' | 'online' }[] = [
  { field: 'rebook_enabled', title: 'set.rebook', sub: 'set.rebook.sub', group: 'texts' },
  { field: 'appointment_reminders', title: 'set.reminders', sub: 'set.reminders.sub', group: 'texts' },
  { field: 'feedback_sms', title: 'set.feedback', sub: 'set.feedback.sub', group: 'texts' },
  { field: 'birthday_offer', title: 'set.birthday', sub: 'set.birthday.sub', group: 'texts' },
  { field: 'daily_summary', title: 'set.summary', sub: 'set.summary.sub', group: 'owner' },
  { field: 'online_booking', title: 'set.online', sub: 'set.online.sub', group: 'online' },
];

/** What a loyalty form sends, as the phone sends it (whole numbers; the value of a point may be 0, the spend per point at least 1). */
export function loyaltyBody(per: string, value: string, referral: string): { per: number; value: number; referral: number } {
  const n = (s: string): number => {
    const v = parseAmount(s);

    return Number.isFinite(v) ? Math.trunc(v) : NaN;
  };

  return { per: Number.isFinite(n(per)) ? n(per) : 1, value: Number.isFinite(n(value)) ? n(value) : 0, referral: Number.isFinite(n(referral)) ? n(referral) : 0 };
}

@Component({
  selector: 'app-salon-settings',
  imports: [FormsModule],
  template: `
    <div class="ad ph-page" data-testid="settings-page">
      @if (error() && !loaded()) {
        <section class="ph-card"><p data-testid="set-error">{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (!loaded()) {
        <section class="ph-card"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else {
        @if (message()) { <p class="ph-good" data-testid="set-message">{{ message() }}</p> }
        @if (error()) { <p class="ph-bad" data-testid="set-problem">{{ error() }}</p> }

        <section class="ph-card">
          <h3>{{ i18n.t('set.texts') }}</h3>
          @for (s of group('texts'); track s.field) {
            <div class="ph-row" style="padding: 6px 0"><span>{{ i18n.t(s.title) }}<br /><span class="ph-muted">{{ i18n.t(s.sub) }}</span></span><input type="checkbox" [checked]="isOn(s.field)" (change)="toggle(s.field, $any($event.target).checked)" [attr.data-testid]="'set-' + s.field" /></div>
          }
          <label class="ph-field" style="margin-top: 6px">{{ i18n.t('set.birthday.text') }}<input class="modal-input" maxlength="160" [ngModel]="birthdayText()" (ngModelChange)="birthdayText.set($event)" data-testid="set-birthday-text" name="setBt" /></label>
          <button type="button" class="btn-outline ph-btn" style="margin-top: 6px" (click)="save({ birthday_text: birthdayText().trim() })" data-testid="set-birthday-save">{{ i18n.t('common.save') }}</button>
        </section>

        <section class="ph-card">
          <h3>{{ i18n.t('set.owner') }}</h3>
          @for (s of group('owner'); track s.field) {
            <div class="ph-row"><span>{{ i18n.t(s.title) }}<br /><span class="ph-muted">{{ i18n.t(s.sub) }}</span></span><input type="checkbox" [checked]="isOn(s.field)" (change)="toggle(s.field, $any($event.target).checked)" [attr.data-testid]="'set-' + s.field" /></div>
          }
        </section>

        <section class="ph-card">
          <h3>{{ i18n.t('set.deposits') }}</h3>
          <label class="ph-field">{{ i18n.t('set.cancel.hours') }}<input class="modal-input" inputmode="numeric" [ngModel]="cancelHours()" (ngModelChange)="cancelHours.set($event)" data-testid="set-cancel" name="setCancel" /></label>
          <button type="button" class="btn-outline ph-btn" style="margin-top: 6px" (click)="save({ cancel_hours: toInt(cancelHours()) })" data-testid="set-cancel-save">{{ i18n.t('common.save') }}</button>
        </section>

        <section class="ph-card">
          <h3>{{ i18n.t('set.booking') }}</h3>
          @for (s of group('online'); track s.field) {
            <div class="ph-row"><span>{{ i18n.t(s.title) }}<br /><span class="ph-muted">{{ i18n.t(s.sub) }}</span></span><input type="checkbox" [checked]="isOn(s.field)" (change)="toggle(s.field, $any($event.target).checked)" [attr.data-testid]="'set-' + s.field" /></div>
          }
          <label class="ph-field" style="margin-top: 6px">{{ i18n.t('set.slug') }}<input class="modal-input" [ngModel]="slug()" (ngModelChange)="slug.set($event)" data-testid="set-slug" name="setSlug" /></label>
          <button type="button" class="btn-outline ph-btn" style="margin-top: 6px" (click)="save({ booking_slug: slug().trim().toLowerCase() })" data-testid="set-slug-save">{{ i18n.t('common.save') }}</button>
          @if (bookingUrl()) {
            <div class="ph-row" style="margin-top: 6px"><a [href]="bookingUrl()" target="_blank" rel="noopener" data-testid="set-url">{{ bookingUrl() }}</a><button type="button" class="btn-outline ph-btn" (click)="copy()" data-testid="set-copy">{{ i18n.t('set.copy') }}</button></div>
          }
        </section>

        <section class="ph-card">
          <h3>{{ i18n.t('set.categories') }}</h3>
          <p class="ph-muted">{{ i18n.t('set.presets.sub') }}</p>
          <button type="button" class="btn-outline ph-btn" (click)="presets()" data-testid="set-presets">{{ i18n.t('set.presets') }}</button>
        </section>

        @if (loyaltyKnown()) {
          <section class="ph-card">
            <h3>{{ i18n.t('set.loyalty') }}</h3>
            <div class="ph-row"><span>{{ i18n.t('set.loyalty.on') }}</span><input type="checkbox" [checked]="loyaltyOn()" (change)="saveLoyalty({ on: $any($event.target).checked })" data-testid="set-loyalty" /></div>
            <label class="ph-field" style="margin-top: 6px">{{ i18n.t('set.per') }}<input class="modal-input" inputmode="numeric" [ngModel]="per()" (ngModelChange)="per.set($event)" data-testid="set-per" name="setPer" /></label>
            <label class="ph-field" style="margin-top: 6px">{{ i18n.t('set.value') }}<input class="modal-input" inputmode="numeric" [ngModel]="pointValue()" (ngModelChange)="pointValue.set($event)" data-testid="set-value" name="setValue" /></label>
            <label class="ph-field" style="margin-top: 6px">{{ i18n.t('set.referral') }}<input class="modal-input" inputmode="numeric" [ngModel]="referral()" (ngModelChange)="referral.set($event)" data-testid="set-referral" name="setReferral" /></label>
            <button type="button" class="btn-outline ph-btn" style="margin-top: 6px" (click)="saveLoyalty(loyaltyForm())" data-testid="set-loyalty-save">{{ i18n.t('set.points.save') }}</button>
          </section>
        }
      }
    </div>
  `,
})
export class SalonSettingsPage implements OnInit {
  private readonly http = inject(HttpClient);
  protected readonly i18n = inject(I18nService);

  protected readonly loaded = signal(false);
  protected readonly error = signal('');
  protected readonly message = signal('');
  protected readonly settings = signal<Record<string, unknown>>({});
  protected readonly loyalty = signal<Record<string, unknown>>({});
  protected readonly loyaltyKnown = signal(true);

  protected readonly birthdayText = signal('');
  protected readonly slug = signal('');
  protected readonly cancelHours = signal('0');
  protected readonly per = signal('');
  protected readonly pointValue = signal('');
  protected readonly referral = signal('');

  ngOnInit(): void {
    void this.load();
  }

  protected group(g: 'texts' | 'owner' | 'online'): typeof SWITCHES {
    return SWITCHES.filter((s) => s.group === g);
  }

  protected isOn(field: string): boolean {
    return on(this.settings()[field]);
  }

  protected loyaltyOn(): boolean {
    return this.loyalty()['on'] === true || this.loyalty()['on'] === 1;
  }

  protected bookingUrl(): string {
    return text(this.settings()['booking_url']);
  }

  protected toInt(s: string): number {
    const n = Math.trunc(Number(s.trim()));

    return Number.isFinite(n) ? n : 0;
  }

  protected loyaltyForm(): { per: number; value: number; referral: number } {
    return loyaltyBody(this.per(), this.pointValue(), this.referral());
  }

  private fill(): void {
    const s = this.settings();
    const l = this.loyalty();
    this.birthdayText.set(text(s['birthday_text']));
    this.slug.set(text(s['booking_slug']));
    this.cancelHours.set(text(s['cancel_hours'] ?? 0));
    this.per.set(text(l['per']));
    this.pointValue.set(text(l['value']));
    this.referral.set(text(l['referral']));
  }

  async load(): Promise<void> {
    this.error.set('');
    try {
      const s = await firstValueFrom(this.http.get<{ data: Record<string, unknown> }>(`${API}/inventory/salon/settings`));
      this.settings.set(obj(s.data));
      try {
        const l = await firstValueFrom(this.http.get<{ data: Record<string, unknown> }>(`${API}/inventory/salon/loyalty/settings`));
        this.loyalty.set(obj(l.data));
        this.loyaltyKnown.set(true);
      } catch {
        this.loyaltyKnown.set(false); // an older server does not know the loyalty page: the rest still works
      }
      this.fill();
      this.loaded.set(true);
    } catch (e) {
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
  }

  protected toggle(field: string, value: boolean): void {
    void this.save({ [field]: value });
  }

  protected async save(body: Record<string, unknown>): Promise<void> {
    this.error.set('');
    this.message.set('');
    try {
      const r = await firstValueFrom(this.http.put<{ data?: Record<string, unknown> }>(`${API}/inventory/salon/settings`, body));
      const got = obj(r.data);
      this.settings.set(Object.keys(got).length ? got : { ...this.settings(), ...body });
      this.fill();
      this.message.set(this.i18n.t('set.saved'));
    } catch (e) {
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
      await this.load();
    }
  }

  protected async saveLoyalty(body: Record<string, unknown>): Promise<void> {
    this.error.set('');
    this.message.set('');
    try {
      const r = await firstValueFrom(this.http.put<{ data?: Record<string, unknown> }>(`${API}/inventory/salon/loyalty/settings`, body));
      const got = obj(r.data);
      this.loyalty.set(Object.keys(got).length ? got : { ...this.loyalty(), ...body });
      this.fill();
      this.message.set(this.i18n.t('set.saved'));
    } catch (e) {
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
      await this.load();
    }
  }

  protected async presets(): Promise<void> {
    this.error.set('');
    this.message.set('');
    try {
      const r = await firstValueFrom(this.http.post<{ data?: Record<string, unknown> }>(`${API}/inventory/salon/category-presets`, {}));
      const added = Array.isArray(obj(r.data)['added']) ? (obj(r.data)['added'] as unknown[]).length : 0;
      this.message.set(added === 0 ? this.i18n.t('set.presets.none') : this.i18n.t('set.presets.added', added));
    } catch (e) {
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
  }

  protected async copy(): Promise<void> {
    try {
      await navigator.clipboard.writeText(this.bookingUrl());
      this.message.set(this.i18n.t('set.copied'));
    } catch {
      // the link is shown: it can be copied by hand
    }
  }
}
