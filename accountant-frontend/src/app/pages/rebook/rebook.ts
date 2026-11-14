import { HttpClient } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { dayLabel, serverMessage } from '../../core/format';
import { I18nService } from '../../core/i18n.service';

const API = environment.apiUrl;

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const text = (v: unknown): string => (v === null || v === undefined ? '' : String(v));
const flag = (v: unknown): boolean => v === true || v === 1 || v === '1' || v === 'true';
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {});

export interface RebookClientView {
  customerId: number;
  name: string;
  phone: string;
  visitOn: string;
  weeksWaited: number;
  service: string;
  sent: boolean;
  canText: boolean;
  skipReason: string | null;
}

export interface RebookView {
  enabled: boolean;
  weeks: number;
  maxWeeks: number;
  clients: RebookClientView[];
}

/** The "come back" answer as the server sends it, read the way the phone reads it. */
export function readRebook(j: Record<string, unknown>): RebookView {
  const s = obj(j['settings']);
  const weeks = num(s['rebook_weeks']);
  const max = num(s['max_weeks']);

  return {
    enabled: flag(s['rebook_enabled']),
    weeks: weeks <= 0 ? 4 : weeks,
    maxWeeks: max <= 0 ? 52 : max,
    clients: (Array.isArray(j['clients']) ? (j['clients'] as unknown[]) : []).map((c) => {
      const o = obj(c);

      return {
        customerId: num(o['customer_id']),
        name: text(o['name']),
        phone: text(o['phone']),
        visitOn: text(o['visit_on']),
        weeksWaited: num(o['weeks_waited']),
        service: text(o['service']),
        sent: flag(o['sent']),
        canText: flag(o['can_text']),
        skipReason: o['skip_reason'] === null || o['skip_reason'] === undefined ? null : text(o['skip_reason']),
      };
    }),
  };
}

/** What to say of a client: texted, will be texted, off, opted out or without a phone (and the colour that goes with it). */
export function clientStatus(c: RebookClientView, remindersOn: boolean): { key: string; tone: 'good' | 'accent' | 'warn' | 'muted' } {
  if (!c.canText) return { key: c.skipReason === 'opted_out' ? 'rb.opted.out' : 'rb.no.phone', tone: 'warn' };
  if (c.sent) return { key: 'rb.texted', tone: 'good' };
  if (!remindersOn) return { key: 'rb.off', tone: 'muted' };

  return { key: 'rb.will', tone: 'accent' };
}

@Component({
  selector: 'app-rebook',
  template: `
    <div class="ad ph-page" data-testid="rebook-page">
      @if (error() && !view()) {
        <section class="ph-card"><p data-testid="rb-error">{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (!view()) {
        <section class="ph-card"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else {
        @let v = view()!;
        <section class="ph-card">
          <div class="ph-row"><h3>{{ i18n.t('rb.title') }}</h3><input type="checkbox" [checked]="v.enabled" [disabled]="saving()" (change)="save({ enabled: $any($event.target).checked })" data-testid="rb-switch" /></div>
          <p class="ph-muted">{{ i18n.t('rb.explain') }}</p>
          <div class="ph-row" style="margin-top: 8px">
            <span>{{ i18n.t('rb.usual') }}</span>
            <span class="ph-row" style="gap: 6px">
              <button type="button" class="btn-outline ph-btn" [disabled]="saving() || v.weeks <= 1" (click)="save({ weeks: v.weeks - 1 })" data-testid="rb-minus">−</button>
              <b data-testid="rb-weeks" style="min-width: 80px; text-align: center">{{ weeksLabel(v.weeks) }}</b>
              <button type="button" class="btn-outline ph-btn" [disabled]="saving() || v.weeks >= v.maxWeeks" (click)="save({ weeks: v.weeks + 1 })" data-testid="rb-plus">+</button>
            </span>
          </div>
          @if (!v.enabled) { <p class="ph-warn" data-testid="rb-off-note">{{ i18n.t('rb.off.note') }}</p> }
          @if (error()) { <p class="ph-bad">{{ error() }}</p> }
        </section>

        <h3 data-testid="rb-due-title">{{ i18n.t('rb.due', v.clients.length) }}</h3>
        @for (c of v.clients; track c.customerId) {
          <section class="ph-card" [attr.data-testid]="'rb-client-' + c.customerId">
            <div class="ph-row"><b>{{ c.name }}</b><span class="ph-badge" [class]="tone(status(c, v.enabled).tone)">{{ i18n.t(status(c, v.enabled).key) }}</span></div>
            <p class="ph-muted">{{ c.phone || '—' }}</p>
            <p class="ph-muted">{{ c.service || i18n.t('rb.service') }} • {{ dayLabel(c.visitOn) }} • {{ weeksAgo(c.weeksWaited) }}</p>
          </section>
        } @empty {
          <section class="ph-card"><p class="ph-muted" data-testid="rb-empty">{{ i18n.t('rb.none') }}</p></section>
        }
      }
    </div>
  `,
})
export class RebookPage implements OnInit {
  private readonly http = inject(HttpClient);
  protected readonly i18n = inject(I18nService);
  protected readonly dayLabel = dayLabel;
  protected readonly status = clientStatus;

  protected readonly view = signal<RebookView | null>(null);
  protected readonly error = signal('');
  protected readonly saving = signal(false);

  ngOnInit(): void {
    void this.load();
  }

  protected tone(t: string): string {
    return t === 'good' ? 'ph-good' : t === 'accent' ? 'ph-accent' : t === 'warn' ? 'ph-warn' : '';
  }

  protected weeksLabel(w: number): string {
    return w === 1 ? this.i18n.t('rb.one.week') : this.i18n.t('rb.n.weeks', w);
  }

  protected weeksAgo(w: number): string {
    if (w <= 0) return this.i18n.t('rb.this.week');

    return w === 1 ? this.i18n.t('rb.one.ago') : this.i18n.t('rb.n.ago', w);
  }

  async load(): Promise<void> {
    this.error.set('');
    try {
      const r = await firstValueFrom(this.http.get<{ data: Record<string, unknown> }>(`${API}/inventory/salon/rebook/due`));
      this.view.set(readRebook(r.data ?? {}));
    } catch (e) {
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
  }

  protected async save(change: { enabled?: boolean; weeks?: number }): Promise<void> {
    const before = this.view();
    if (!before || this.saving()) return;
    this.saving.set(true);
    this.error.set('');
    this.view.set({ ...before, enabled: change.enabled ?? before.enabled, weeks: change.weeks ?? before.weeks });
    try {
      await firstValueFrom(
        this.http.put(`${API}/inventory/salon/settings`, {
          ...(change.enabled !== undefined ? { rebook_enabled: change.enabled } : {}),
          ...(change.weeks !== undefined ? { rebook_weeks: change.weeks } : {}),
        }),
      );
      this.saving.set(false);
      await this.load(); // switching it on or changing the wait changes who is due
    } catch (e) {
      this.view.set(before);
      this.saving.set(false);
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
  }
}
