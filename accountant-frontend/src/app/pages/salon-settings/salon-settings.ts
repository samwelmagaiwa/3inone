import { HttpClient } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';

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
  imports: [FormsModule, RowMenuComponent],
  template: `
    <div class="ad ph-page" data-testid="settings-page">
      @if (error() && !loaded()) {
        <section class="ph-card set-wide"><p data-testid="set-error">{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (!loaded()) {
        <section class="ph-card set-wide"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else {
        @if (message()) { <p class="ph-good set-wide" data-testid="set-message">{{ message() }}</p> }
        @if (error()) { <p class="ph-bad set-wide" data-testid="set-problem">{{ error() }}</p> }

        <!-- every setting is a row: what it is, what it does, its value (a switch or a field), and Save under the three dots -->
        <div class="table-scroll-container fit-page set-wide">
          <table class="grid-table g-grid" data-testid="set-table">
            <thead><tr>
              <th class="no-col">#</th><th>{{ i18n.t('set.col.setting') }}</th><th>{{ i18n.t('set.col.about') }}</th><th>{{ i18n.t('set.col.value') }}</th><th class="text-right">{{ i18n.t('g.actions') }}</th>
            </tr></thead>
            <tbody>
              <tr class="set-group"><td colspan="5">{{ i18n.t('set.texts') }}</td></tr>
              @for (sw of group('texts'); track sw.field) {
                <tr><td class="no-col">{{ $index + 1 }}</td><td class="font-bold">{{ i18n.t(sw.title) }}</td><td class="ph-muted">{{ i18n.t(sw.sub) }}</td>
                  <td><label class="set-switch"><input type="checkbox" [checked]="isOn(sw.field)" (change)="toggle(sw.field, $any($event.target).checked)" [attr.data-testid]="'set-' + sw.field" /><span>{{ isOn(sw.field) ? i18n.t('set.on') : i18n.t('set.off') }}</span></label></td>
                  <td class="text-right">—</td></tr>
              }

              <tr class="set-group"><td colspan="5">{{ i18n.t('set.owner') }}</td></tr>
              @for (sw of group('owner'); track sw.field) {
                <tr><td class="no-col">{{ $index + 1 }}</td><td class="font-bold">{{ i18n.t(sw.title) }}</td><td class="ph-muted">{{ i18n.t(sw.sub) }}</td>
                  <td><label class="set-switch"><input type="checkbox" [checked]="isOn(sw.field)" (change)="toggle(sw.field, $any($event.target).checked)" [attr.data-testid]="'set-' + sw.field" /><span>{{ isOn(sw.field) ? i18n.t('set.on') : i18n.t('set.off') }}</span></label></td>
                  <td class="text-right">—</td></tr>
              }

              <tr class="set-group"><td colspan="5">{{ i18n.t('set.deposits') }}</td></tr>
              <tr><td class="no-col">1</td><td class="font-bold">{{ i18n.t('set.cancel.short') }}</td><td class="ph-muted">{{ i18n.t('set.cancel.hours') }}</td>
                <td><input class="modal-input set-input" inputmode="numeric" [ngModel]="cancelHours()" (ngModelChange)="cancelHours.set($event)" data-testid="set-cancel" name="setCancel" /></td>
                <td class="text-right"><app-row-menu [items]="saveMenu('set-cancel-save')" [testid]="'set-cancel-menu'" (picked)="save({ cancel_hours: toInt(cancelHours()) })" /></td></tr>

              <tr class="set-group"><td colspan="5">{{ i18n.t('set.booking') }}</td></tr>
              @for (sw of group('online'); track sw.field) {
                <tr><td class="no-col">{{ $index + 1 }}</td><td class="font-bold">{{ i18n.t(sw.title) }}</td><td class="ph-muted">{{ i18n.t(sw.sub) }}</td>
                  <td><label class="set-switch"><input type="checkbox" [checked]="isOn(sw.field)" (change)="toggle(sw.field, $any($event.target).checked)" [attr.data-testid]="'set-' + sw.field" /><span>{{ isOn(sw.field) ? i18n.t('set.on') : i18n.t('set.off') }}</span></label></td>
                  <td class="text-right">—</td></tr>
              }
              <tr><td class="no-col">2</td><td class="font-bold">{{ i18n.t('set.address') }}</td><td class="ph-muted">{{ i18n.t('set.slug') }}</td>
                <td><input class="modal-input set-input" [ngModel]="slug()" (ngModelChange)="slug.set($event)" data-testid="set-slug" name="setSlug" /></td>
                <td class="text-right"><app-row-menu [items]="saveMenu('set-slug-save')" [testid]="'set-slug-menu'" (picked)="save({ booking_slug: slug().trim().toLowerCase() })" /></td></tr>
              @if (bookingUrl()) {
                <tr><td class="no-col">3</td><td class="font-bold">{{ i18n.t('set.link') }}</td><td class="g-long" [title]="bookingUrl()"><a [href]="bookingUrl()" target="_blank" rel="noopener" data-testid="set-url">{{ bookingUrl() }}</a></td>
                  <td>—</td>
                  <td class="text-right"><app-row-menu [items]="copyMenu()" [testid]="'set-copy-menu'" (picked)="copy()" /></td></tr>
              }

              <tr class="set-group"><td colspan="5">{{ i18n.t('set.categories') }}</td></tr>
              <tr><td class="no-col">1</td><td class="font-bold">{{ i18n.t('set.presets') }}</td><td class="g-long ph-muted" [title]="i18n.t('set.presets.sub')">{{ i18n.t('set.presets.sub') }}</td>
                <td>—</td>
                <td class="text-right"><app-row-menu [items]="presetMenu()" [testid]="'set-presets-menu'" (picked)="presets()" /></td></tr>

              @if (loyaltyKnown()) {
                <tr class="set-group"><td colspan="5">{{ i18n.t('set.loyalty') }}</td></tr>
                <tr><td class="no-col">1</td><td class="font-bold">{{ i18n.t('set.loyalty.on') }}</td><td class="ph-muted">{{ i18n.t('set.loyalty') }}</td>
                  <td><label class="set-switch"><input type="checkbox" [checked]="loyaltyOn()" (change)="saveLoyalty({ on: $any($event.target).checked })" data-testid="set-loyalty" /><span>{{ loyaltyOn() ? i18n.t('set.on') : i18n.t('set.off') }}</span></label></td>
                  <td class="text-right">—</td></tr>
                <tr><td class="no-col">2</td><td class="font-bold">{{ i18n.t('set.per') }}</td><td class="ph-muted">{{ i18n.t('set.points.about') }}</td>
                  <td><input class="modal-input set-input" inputmode="numeric" [ngModel]="per()" (ngModelChange)="per.set($event)" data-testid="set-per" name="setPer" /></td>
                  <td class="text-right"><app-row-menu [items]="saveMenu('set-loyalty-save')" [testid]="'set-per-menu'" (picked)="saveLoyalty(loyaltyForm())" /></td></tr>
                <tr><td class="no-col">3</td><td class="font-bold">{{ i18n.t('set.value') }}</td><td class="ph-muted">{{ i18n.t('set.points.about') }}</td>
                  <td><input class="modal-input set-input" inputmode="numeric" [ngModel]="pointValue()" (ngModelChange)="pointValue.set($event)" data-testid="set-value" name="setValue" /></td>
                  <td class="text-right"><app-row-menu [items]="saveMenu()" [testid]="'set-value-menu'" (picked)="saveLoyalty(loyaltyForm())" /></td></tr>
                <tr><td class="no-col">4</td><td class="font-bold">{{ i18n.t('set.referral') }}</td><td class="ph-muted">{{ i18n.t('set.points.about') }}</td>
                  <td><input class="modal-input set-input" inputmode="numeric" [ngModel]="referral()" (ngModelChange)="referral.set($event)" data-testid="set-referral" name="setReferral" /></td>
                  <td class="text-right"><app-row-menu [items]="saveMenu()" [testid]="'set-referral-menu'" (picked)="saveLoyalty(loyaltyForm())" /></td></tr>
              }
            </tbody>
          </table>
        </div>
      }
    </div>
  `,
  styles: [
    `
      .set-wide { grid-column: 1 / -1; }
      tr.set-group td { background: rgba(32, 184, 206, 0.22) !important; font-weight: 900; text-transform: uppercase; letter-spacing: 0.06em; font-size: 12px; }
      .set-switch { display: inline-flex; align-items: center; gap: 8px; cursor: pointer; }
      .set-switch input { width: 18px; height: 18px; accent-color: #20b8ce; }
      .set-input { height: 34px; padding: 4px 10px; width: 200px; font-size: 14px; }
    `,
  ],
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

  protected saveMenu(testid?: string): MenuItem[] {
    return [{ id: 'save', label: this.i18n.t('common.save'), primary: true, ...(testid ? { testid } : {}) }];
  }

  protected copyMenu(): MenuItem[] {
    return [{ id: 'copy', label: this.i18n.t('set.copy'), testid: 'set-copy' }];
  }

  protected presetMenu(): MenuItem[] {
    return [{ id: 'presets', label: this.i18n.t('set.presets'), primary: true, testid: 'set-presets' }];
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
