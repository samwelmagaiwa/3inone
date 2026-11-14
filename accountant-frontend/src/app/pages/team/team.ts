import { HttpClient } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AuthService } from '../../core/auth.service';
import { dayLabel, monthKey, monthName, serverMessage, shiftMonth } from '../../core/format';
import { I18nService } from '../../core/i18n.service';

const API = environment.apiUrl;

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const text = (v: unknown): string => (v === null || v === undefined ? '' : String(v));
const flag = (v: unknown): boolean => v === true || v === 1 || v === '1' || v === 'true';
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {});

export interface AttendanceRecordView {
  date: string;
  clockIn: string;
  clockOut: string | null;
  hours: number | null;
}

export interface AttendancePersonView {
  staffId: string;
  name: string;
  days: number;
  hours: number;
  atWork: boolean;
  records: AttendanceRecordView[];
}

/** "2026-11-14 09:05:00" or an ISO stamp -> "09:05". */
export function hm(stamp: string | null): string {
  const m = stamp ? /[T ](\d{2}):(\d{2})/.exec(stamp) : null;

  return m ? `${m[1]}:${m[2]}` : '';
}

export function readAttendance(j: Record<string, unknown>): AttendancePersonView[] {
  return (Array.isArray(j['staff']) ? (j['staff'] as unknown[]) : []).map((p) => {
    const o = obj(p);

    return {
      staffId: text(o['staff_id']),
      name: text(o['name']),
      days: num(o['days']),
      hours: num(o['hours']),
      atWork: flag(o['at_work']),
      records: (Array.isArray(o['records']) ? (o['records'] as unknown[]) : []).map((r) => {
        const x = obj(r);

        return { date: text(x['date']), clockIn: text(x['clock_in']), clockOut: x['clock_out'] ? text(x['clock_out']) : null, hours: x['hours'] === null || x['hours'] === undefined ? null : num(x['hours']) };
      }),
    };
  });
}

/** The hours as the phone shows them: 8 or 7.5. */
export const hoursText = (h: number): string => (h % 1 === 0 ? String(Math.trunc(h)) : h.toFixed(1));

@Component({
  selector: 'app-team',
  template: `
    <div class="ad ph-page" data-testid="team-page">
      <div class="ph-row">
        <button type="button" class="btn-outline ph-btn" (click)="go(-1)" data-testid="tm-prev" [attr.aria-label]="i18n.t('tm.prev')">‹</button>
        <b data-testid="tm-month">{{ monthTitle() }}</b>
        <button type="button" class="btn-outline ph-btn" (click)="go(1)" data-testid="tm-next" [attr.aria-label]="i18n.t('tm.next')">›</button>
      </div>
      <p class="ph-muted">{{ i18n.t('tm.explain') }}</p>

      @if (error()) {
        <section class="ph-card"><p data-testid="tm-error">{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (loading()) {
        <section class="ph-card"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else {
        @for (p of people(); track p.staffId) {
          <section class="ph-card" [attr.data-testid]="'tm-' + p.staffId">
            <div class="ph-row"><h3>{{ p.name }}</h3>@if (p.atWork) { <span class="ph-badge ph-good">{{ i18n.t('tm.at.work') }}</span> }</div>
            <p class="ph-muted">{{ i18n.t('tm.summary', p.days, hoursText(p.hours)) }}</p>
            @for (r of last(p); track $index) {
              <p class="ph-muted">{{ dayLabel(r.date) }}  {{ hm(r.clockIn) }}–{{ r.clockOut ? hm(r.clockOut) : '…' }}@if (r.hours !== null) { ({{ hoursText(r.hours) }} h) }</p>
            }
            @if (canManage() && p.atWork) {
              <button type="button" class="btn-outline ph-btn" (click)="finish(p)" [disabled]="busy()" [attr.data-testid]="'tm-out-' + p.staffId">{{ i18n.t('tm.finish') }}</button>
            }
          </section>
        } @empty {
          <section class="ph-card"><p class="ph-muted" data-testid="tm-empty">{{ i18n.t('tm.none') }}</p></section>
        }
      }
    </div>
  `,
})
export class TeamPage implements OnInit {
  private readonly http = inject(HttpClient);
  private readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);
  protected readonly dayLabel = dayLabel;
  protected readonly hm = hm;
  protected readonly hoursText = hoursText;

  protected readonly month = signal(monthKey(new Date()));
  protected readonly people = signal<AttendancePersonView[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal('');
  protected readonly busy = signal(false);
  private asked = 0;

  /** The owner and managers can finish someone's day for them; the server checks again. */
  protected readonly canManage = computed(() => this.auth.can('inv_salon_team'));
  protected readonly monthTitle = computed(() => monthName(this.month(), this.i18n.lang() === 'sw' ? 'sw-TZ' : 'en-GB'));

  ngOnInit(): void {
    void this.load();
  }

  protected go(by: number): void {
    this.month.set(shiftMonth(this.month(), by));
    void this.load();
  }

  protected last(p: AttendancePersonView): AttendanceRecordView[] {
    return p.records.slice(-5).reverse();
  }

  async load(): Promise<void> {
    const ticket = ++this.asked;
    this.loading.set(true);
    this.error.set('');
    try {
      const r = await firstValueFrom(this.http.get<{ data: Record<string, unknown> }>(`${API}/inventory/salon/attendance`, { params: { month: this.month() } }));
      if (ticket !== this.asked) return;
      this.people.set(readAttendance(r.data ?? {}));
    } catch (e) {
      if (ticket !== this.asked) return;
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
    if (ticket === this.asked) this.loading.set(false);
  }

  protected async finish(p: AttendancePersonView): Promise<void> {
    this.busy.set(true);
    this.error.set('');
    try {
      await firstValueFrom(this.http.post(`${API}/inventory/salon/attendance/clock-out`, { staff_id: p.staffId }));
      await this.load();
    } catch (e) {
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
    this.busy.set(false);
  }
}
