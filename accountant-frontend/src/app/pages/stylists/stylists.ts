import { HttpClient } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { dayLabel, dayOf, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { periodRange } from '../money/money';

type Period = 'today' | 'yesterday' | 'last7' | 'thisWeek' | 'lastWeek' | 'thisMonth' | 'lastMonth' | 'thisYear' | 'custom';
const PERIODS: Period[] = ['today', 'yesterday', 'last7', 'thisWeek', 'lastWeek', 'thisMonth', 'lastMonth', 'thisYear', 'custom'];

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const numOrNull = (v: unknown): number | null => (v === null || v === undefined || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {});

export interface StylistTargetView {
  amount: number;
  percent: number;
  pace: string;
}

export interface StylistRowView {
  staffId: string | null;
  name: string;
  services: number;
  revenue: number;
  commission: number;
  discount: number;
  visits: number;
  clients: number;
  avgTicket: number;
  returnRate: number | null;
  share: number;
  rank: number | null;
  revenueChange: number | null;
  target: StylistTargetView | null;
}

export interface StylistReportView {
  stylists: StylistRowView[];
  services: number;
  revenue: number;
  commission: number;
  visits: number;
  avgTicket: number;
  previousRevenue: number;
  revenueChange: number | null;
  seesEveryone: boolean;
}

/** The stylists' report as the server sends it, read the way the phone reads it. */
export function readStylistReport(j: Record<string, unknown>): StylistReportView {
  const totals = obj(j['totals']);
  const change = obj(totals['change']);
  const rows = Array.isArray(j['stylists']) ? (j['stylists'] as unknown[]) : [];

  return {
    stylists: rows.map((r) => {
      const o = obj(r);
      const t = o['target'] && typeof o['target'] === 'object' ? obj(o['target']) : null;

      return {
        staffId: o['staff_id'] === null || o['staff_id'] === undefined ? null : String(o['staff_id']),
        name: String(o['name'] ?? ''),
        services: num(o['services']),
        revenue: num(o['revenue']),
        commission: num(o['commission']),
        discount: num(o['discount']),
        visits: num(o['visits']),
        clients: num(o['clients']),
        avgTicket: num(o['avg_ticket']),
        returnRate: numOrNull(o['return_rate']),
        share: num(o['share']),
        rank: numOrNull(o['rank']),
        revenueChange: numOrNull(obj(o['change'])['revenue']),
        target: t ? { amount: num(t['amount']), percent: num(t['percent']), pace: String(t['pace'] ?? '') } : null,
      };
    }),
    services: num(totals['services']),
    revenue: num(totals['revenue']),
    commission: num(totals['commission']),
    visits: num(totals['visits']),
    avgTicket: num(totals['avg_ticket']),
    previousRevenue: num(obj(totals['previous'])['revenue']),
    revenueChange: numOrNull(change['revenue']),
    seesEveryone: j['sees_everyone'] === true || j['sees_everyone'] === 1,
  };
}

@Component({
  selector: 'app-stylists',
  imports: [FormsModule],
  template: `
    <div class="ad ph-page" data-testid="stylists-page">
      <!-- the periods and the figures stay pinned at the top while the table scrolls under them -->
      <div class="g-pin" data-testid="st-pin">
        <div class="ph-chips">
          @for (p of periods; track p) {
            <button type="button" class="pill-tab" [class.is-active]="period() === p" [attr.data-testid]="'st-period-' + p" (click)="pick(p)">{{ periodName(p) }}</button>
          }
          <span class="ph-muted st-range" data-testid="st-range">{{ rangeLabel() }}</span>
        </div>
        @if (period() === 'custom') {
          <div class="ph-row" style="flex-wrap: wrap; align-items: end; gap: 8px">
            <label class="ph-field">{{ i18n.t('ad.from') }} <input type="date" [ngModel]="from()" (ngModelChange)="from.set($event)" /></label>
            <label class="ph-field">{{ i18n.t('ad.to') }} <input type="date" [ngModel]="to()" (ngModelChange)="to.set($event)" /></label>
            <button type="button" class="btn-primary ph-btn" (click)="load()">{{ i18n.t('ad.apply') }}</button>
          </div>
        }
        @if (data(); as d) {
          <div class="ph-tiles g-tiles-row" data-testid="st-tiles">
            <div class="ph-tile g-t-green"><span class="ph-muted">{{ i18n.t('pl.revenue') }}</span><b class="ph-good">{{ tsh(d.revenue) }}</b></div>
            <div class="ph-tile g-t-blue"><span class="ph-muted">{{ i18n.t('st.services') }}</span><b>{{ d.services }}</b></div>
            <div class="ph-tile g-t-purple"><span class="ph-muted">{{ i18n.t('st.visits') }}</span><b>{{ d.visits }}</b></div>
            <div class="ph-tile g-t-teal"><span class="ph-muted">{{ i18n.t('st.avg') }}</span><b class="ph-accent">{{ tsh(d.avgTicket) }}</b></div>
            @if (d.commission > 0) { <div class="ph-tile g-t-yellow"><span class="ph-muted">{{ i18n.t('pl.commissions') }}</span><b class="ph-warn">{{ tsh(d.commission) }}</b></div> }
            @if (d.revenueChange !== null) {
              <div class="ph-tile" [class.g-t-green]="d.revenueChange >= 0" [class.g-t-red]="d.revenueChange < 0">
                <span class="ph-muted">{{ i18n.t('st.vs.before') }}</span>
                <b [class.ph-good]="d.revenueChange >= 0" [class.ph-bad]="d.revenueChange < 0" [title]="tsh(d.previousRevenue)">{{ change(d.revenueChange) }}</b>
              </div>
            }
          </div>
        }
      </div>

      @if (error()) {
        <section class="ph-card"><p data-testid="st-error">{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (!data()) {
        <section class="ph-card"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else {
        @let d = data()!;
        @let hasTarget = hasAny(d, 'target');
        @let hasDiscount = hasAny(d, 'discount');
        @let hasCommission = hasAny(d, 'commission');
        <!-- every stylist is one row; the figures are the columns, in clean grid lines -->
        <div class="table-scroll-container fit-page st-wide" data-testid="st-joined">
          <table class="grid-table g-grid" data-testid="st-table">
            <thead><tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('st.col.name') }}</th>
              <th class="text-right">{{ i18n.t('pl.revenue') }}</th>
              <th class="text-right">{{ i18n.t('st.services') }}</th>
              <th class="text-right">{{ i18n.t('st.visits') }}</th>
              <th class="text-right">{{ i18n.t('st.clients') }}</th>
              <th class="text-right">{{ i18n.t('st.avg') }}</th>
              <th class="text-right">{{ i18n.t('st.came.back') }}</th>
              @if (d.seesEveryone) { <th class="text-right">{{ i18n.t('st.share') }}</th> }
              @if (hasDiscount) { <th class="text-right">{{ i18n.t('st.discount') }}</th> }
              @if (hasCommission) { <th class="text-right">{{ i18n.t('st.commission') }}</th> }
              @if (hasTarget) { <th>{{ i18n.t('st.target') }}</th> }
            </tr></thead>
            <tbody>
              @for (r of d.stylists; track r.staffId ?? 'none'; let i = $index) {
                <tr [attr.data-testid]="'st-row-' + (r.staffId ?? 'none')">
                  <td class="no-col">{{ d.seesEveryone && r.rank ? r.rank : i + 1 }}</td>
                  <td class="font-bold">{{ r.staffId === null || !r.name.trim() ? i18n.t('st.nobody') : r.name }}</td>
                  <td class="text-right"><b class="ph-accent">{{ tsh(r.revenue) }}</b></td>
                  <td class="text-right">{{ r.services }}</td>
                  <td class="text-right">{{ r.visits }}</td>
                  <td class="text-right">{{ r.clients }}</td>
                  <td class="text-right">{{ r.visits > 0 ? tsh(r.avgTicket) : '—' }}</td>
                  <td class="text-right">{{ r.returnRate === null ? '—' : Math.round(r.returnRate) + '%' }}</td>
                  @if (d.seesEveryone) { <td class="text-right">{{ Math.round(r.share) }}%</td> }
                  @if (hasDiscount) { <td class="text-right">{{ r.discount > 0 ? tsh(r.discount) : '—' }}</td> }
                  @if (hasCommission) { <td class="text-right">{{ r.commission > 0 ? tsh(r.commission) : '—' }}</td> }
                  @if (hasTarget) {
                    <td>
                      @if (r.target; as t) {
                        <div class="st-target"><div class="st-bar"><i [style.width.%]="Math.min(100, t.percent)"></i></div><b [class]="paceClass(t.pace)">{{ Math.round(t.percent) }}% · {{ paceName(t.pace) }}</b></div>
                        <span class="ph-muted st-small">{{ tsh(t.amount) }}</span>
                      } @else { — }
                    </td>
                  }
                </tr>
              } @empty {
                <tr><td colspan="12" class="ph-muted" data-testid="st-empty">{{ i18n.t('st.empty') }}</td></tr>
              }
            </tbody>
            @if (d.stylists.length) {
              <tfoot><tr data-testid="st-total">
                <td class="no-col"></td>
                <td class="font-bold">{{ i18n.t('st.total') }}</td>
                <td class="text-right"><b>{{ tsh(d.revenue) }}</b></td>
                <td class="text-right"><b>{{ d.services }}</b></td>
                <td class="text-right"><b>{{ d.visits }}</b></td>
                <td class="text-right">—</td>
                <td class="text-right"><b>{{ tsh(d.avgTicket) }}</b></td>
                <td class="text-right">—</td>
                @if (d.seesEveryone) { <td class="text-right"><b>100%</b></td> }
                @if (hasDiscount) { <td class="text-right"><b>{{ tsh(totalOf(d, 'discount')) }}</b></td> }
                @if (hasCommission) { <td class="text-right"><b>{{ tsh(d.commission) }}</b></td> }
                @if (hasTarget) { <td></td> }
              </tr></tfoot>
            }
          </table>
        </div>
      }
    </div>
  `,
  styles: [
    `
      .st-wide { grid-column: 1 / -1; }
      .st-range { margin-left: 8px; align-self: center; }
      .st-target { display: flex; align-items: center; gap: 8px; }
      .st-bar { width: 80px; height: 8px; border-radius: 99px; background: rgba(255, 255, 255, 0.18); overflow: hidden; flex: none; }
      .st-bar i { display: block; height: 100%; background: linear-gradient(90deg, #1ba3c7, #20b8ce); }
      .st-small { font-size: 12px; }
    `,
  ],
})
export class StylistsPage implements OnInit {
  private readonly http = inject(HttpClient);
  protected readonly i18n = inject(I18nService);
  protected readonly tsh = tsh;
  protected readonly Math = Math;
  protected readonly periods = PERIODS;

  protected readonly period = signal<Period>('thisMonth');
  protected readonly from = signal(dayOf(new Date()));
  protected readonly to = signal(dayOf(new Date()));
  protected readonly data = signal<StylistReportView | null>(null);
  protected readonly error = signal('');
  private asked = 0;

  protected readonly range = computed(() => periodRange(this.period(), new Date(), this.from(), this.to()));
  protected readonly rangeLabel = computed(() => {
    const [a, b] = this.range();

    return a === b ? dayLabel(a) : `${dayLabel(a)} – ${dayLabel(b)}`;
  });

  ngOnInit(): void {
    void this.load();
  }

  protected periodName(p: Period): string {
    switch (p) {
      case 'today': return this.i18n.t('pl.p.today');
      case 'yesterday': return this.i18n.t('pl.p.yesterday');
      case 'last7': return this.i18n.t('pl.p.last7');
      case 'thisWeek': return this.i18n.t('pl.p.thisWeek');
      case 'lastWeek': return this.i18n.t('pl.p.lastWeek');
      case 'thisMonth': return this.i18n.t('pl.p.thisMonth');
      case 'lastMonth': return this.i18n.t('pl.p.lastMonth');
      case 'thisYear': return this.i18n.t('pl.p.thisYear');
      case 'custom': return this.i18n.t('ad.custom');
    }
  }

  protected change(pct: number): string {
    return `${pct >= 0 ? '+' : '-'}${Math.abs(Math.round(pct))}%`;
  }

  protected paceName(pace: string): string {
    switch (pace) {
      case 'reached': return this.i18n.t('st.pace.reached');
      case 'ahead': return this.i18n.t('st.pace.ahead');
      case 'on_track': return this.i18n.t('st.pace.track');
      default: return this.i18n.t('st.pace.behind');
    }
  }

  /** Whether any stylist has this figure, so its column shows only when it says something. */
  protected hasAny(d: StylistReportView, what: 'target' | 'discount' | 'commission'): boolean {
    return d.stylists.some((r) => (what === 'target' ? r.target !== null : r[what] > 0));
  }

  protected totalOf(d: StylistReportView, what: 'discount'): number {
    return d.stylists.reduce((a, r) => a + r[what], 0);
  }

  protected paceClass(pace: string): string {
    return pace === 'reached' || pace === 'ahead' ? 'ph-good' : pace === 'on_track' ? 'ph-warn' : 'ph-bad';
  }

  protected pick(p: Period): void {
    this.period.set(p);
    if (p !== 'custom') void this.load();
  }

  async load(): Promise<void> {
    const [from, to] = this.range();
    const ticket = ++this.asked;
    this.error.set('');
    try {
      const r = await firstValueFrom(this.http.get<{ data: Record<string, unknown> }>(`${environment.apiUrl}/inventory/salon/stylists`, { params: { from, to } }));
      if (ticket !== this.asked) return;
      this.data.set(readStylistReport(r.data ?? {}));
    } catch {
      if (ticket !== this.asked) return;
      this.data.set(null);
      this.error.set(this.i18n.t('pl.error'));
    }
  }
}
