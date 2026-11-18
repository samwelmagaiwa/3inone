import { HttpClient } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { dayLabel, dayOf, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';

type Period = 'today' | 'week' | 'month' | 'year';
const PERIODS: Period[] = ['today', 'week', 'month', 'year'];

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const text = (v: unknown): string => (v === null || v === undefined ? '' : String(v));
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {});
const list = (v: unknown): Record<string, unknown>[] => (Array.isArray(v) ? v.map(obj) : []);

/** The salon's whole report for a period, read the way the phone reads it (every part may be missing: the server leaves out what a person may not see). */
export interface SalonReport {
  hidden: boolean;
  summary: Record<string, unknown>;
  byService: { name: string; times: number; revenue: number; commission: number; materials: number; profit: number }[];
  goodsSold: { name: string; qty: number; revenue: number; cost: number; profit: number }[];
  byStylist: { name: string; services: number; clients: number; revenue: number }[];
  byMethod: { method: string; amount: number }[];
  byBranch: { name: string; sales: number; revenue: number }[];
  expenses: { category: string; total: number }[];
  diary: Record<string, unknown>;
  clients: Record<string, unknown>;
  topSpenders: { name: string; visits: number; spent: number }[];
  owedTotal: number;
  owed: { client: string; days: number; due: number }[];
  stock: Record<string, unknown>;
  /** The sub-totals: what the services and the goods each sold for and earned in the period (profit only for someone who may see it). */
  totals: ReportTotals;
}

export interface ReportTotals {
  services: { times: number; revenue: number; profit: number };
  goods: { qty: number; revenue: number; cost: number; profit: number };
  /** The share of the profit of goods and services together that each earned, in whole percent (0 when there is no profit to share). */
  goodsShare: number;
  servicesShare: number;
}

export function reportTotals(byService: SalonReport['byService'], goodsSold: SalonReport['goodsSold']): ReportTotals {
  const services = byService.reduce((a, r) => ({ times: a.times + r.times, revenue: a.revenue + r.revenue, profit: a.profit + r.profit }), { times: 0, revenue: 0, profit: 0 });
  const goods = goodsSold.reduce((a, r) => ({ qty: a.qty + r.qty, revenue: a.revenue + r.revenue, cost: a.cost + r.cost, profit: a.profit + r.profit }), { qty: 0, revenue: 0, cost: 0, profit: 0 });
  const both = goods.profit + services.profit;

  return {
    services,
    goods,
    goodsShare: both > 0 ? Math.round((goods.profit / both) * 100) : 0,
    servicesShare: both > 0 ? Math.round((services.profit / both) * 100) : 0,
  };
}

export function readSalonReport(j: Record<string, unknown>): SalonReport {
  const clients = obj(j['clients']);
  const owed = obj(j['owed']);
  const byService = list(j['by_service']).map((r) => ({ name: text(r['name']), times: num(r['times']), revenue: num(r['revenue']), commission: num(r['commission']), materials: num(r['materials_cost']), profit: num(r['profit']) }));
  const goodsSold = list(j['goods_sold']).map((r) => ({ name: text(r['name']), qty: num(r['qty']), revenue: num(r['revenue']), cost: num(r['cost']), profit: num(r['profit']) }));

  return {
    hidden: j['profit_hidden'] === true,
    summary: obj(j['summary']),
    byService,
    goodsSold,
    totals: reportTotals(byService, goodsSold),
    byStylist: list(j['by_stylist']).map((r) => ({ name: text(r['name']), services: num(r['services']), clients: num(r['clients']), revenue: num(r['revenue']) })),
    byMethod: list(j['by_method']).map((r) => ({ method: text(r['method']), amount: num(r['amount']) })),
    byBranch: list(j['by_branch']).map((r) => ({ name: text(r['name']), sales: num(r['sales']), revenue: num(r['revenue']) })),
    expenses: list(j['expenses_by_category']).map((r) => ({ category: text(r['category']), total: num(r['total']) })),
    diary: obj(j['diary']),
    clients,
    topSpenders: list(clients['top_spenders']).map((r) => ({ name: text(r['name']), visits: num(r['visits']), spent: num(r['spent']) })),
    owedTotal: num(owed['total']),
    owed: list(owed['list']).map((r) => ({ client: text(r['client']), days: num(r['days']), due: num(r['due']) })),
    stock: obj(j['stock']),
  };
}

/** The first and last day of the phone's four report periods (weeks start on Monday). */
export function reportRange(p: Period, now: Date): [string, string] {
  const t = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  switch (p) {
    case 'today':
      return [dayOf(t), dayOf(t)];
    case 'week':
      return [dayOf(new Date(t.getFullYear(), t.getMonth(), t.getDate() - ((t.getDay() + 6) % 7))), dayOf(t)];
    case 'year':
      return [dayOf(new Date(t.getFullYear(), 0, 1)), dayOf(t)];
    default:
      return [dayOf(new Date(t.getFullYear(), t.getMonth(), 1)), dayOf(t)];
  }
}

@Component({
  selector: 'app-reports',
  template: `
    <div class="ad ph-page" data-testid="reports-page">
      <div class="ph-chips">
        @for (p of periods; track p) {
          <button type="button" class="pill-tab" [class.is-active]="period() === p" [attr.data-testid]="'rp-period-' + p" (click)="pick(p)">{{ periodName(p) }}</button>
        }
      </div>
      <p class="ph-muted">{{ rangeLabel() }}</p>

      @if (error()) {
        <section class="ph-card"><p data-testid="rp-error">{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (!data()) {
        <section class="ph-card"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else {
        @let d = data()!;
        <!-- One card, its sections told apart by the glowing lines (as on the phone) -->
        <div class="ph-card ph-joined ph-cols" data-testid="rp-joined">
          <section class="ph-sec" data-testid="rp-summary">
            <h3>{{ i18n.t('rp.summary') }}</h3>
            <div class="ph-line"><span>{{ i18n.t('pl.revenue') }}</span><b data-testid="rp-revenue">{{ money(d.summary['revenue']) }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('st.services') }}</span><b>{{ money(d.summary['service_revenue']) }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('rp.goods') }}</span><b>{{ money(d.summary['goods_revenue']) }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('rp.discounts') }}</span><b>{{ money(d.summary['discounts']) }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('pl.expenses') }}</span><b>{{ money(d.summary['expenses']) }}</b></div>
            @if (!d.hidden) {
              <div class="ph-line"><span>{{ i18n.t('rp.commissions') }}</span><b>{{ money(d.summary['commissions']) }}</b></div>
              <div class="ph-line"><b>{{ i18n.t('pl.net.profit') }}</b><b data-testid="rp-profit">{{ money(d.summary['net_profit']) }}</b></div>
            }
            <div class="ph-line"><span>{{ i18n.t('rp.sales.clients') }}</span><b>{{ d.summary['sales'] ?? 0 }} / {{ d.summary['clients'] ?? 0 }}</b></div>
          </section>

          @if (!d.hidden && (d.byService.length || d.goodsSold.length)) {
            <section class="ph-sec" data-testid="rp-versus">
              <h3>{{ i18n.t('rp.versus') }}</h3>
              <div class="ph-line"><span>{{ i18n.t('rp.goods.profit') }}</span><b>{{ tsh(d.totals.goods.profit) }} <span class="ph-muted">({{ d.totals.goodsShare }}%)</span></b></div>
              <div class="ph-line"><span>{{ i18n.t('rp.services.profit') }}</span><b>{{ tsh(d.totals.services.profit) }} <span class="ph-muted">({{ d.totals.servicesShare }}%)</span></b></div>
              <div class="ph-line"><b>{{ i18n.t('rp.both.profit') }}</b><b data-testid="rp-both-profit">{{ tsh(d.totals.goods.profit + d.totals.services.profit) }}</b></div>
              <p class="ph-muted">{{ i18n.t('rp.versus.note') }}</p>
            </section>
          }

          <section class="ph-sec">
            <h3>{{ i18n.t('rp.by.service') }}</h3>
            @for (r of d.byService; track r.name) {
              <div class="ph-line"><span>{{ r.name }} ×{{ r.times }}</span><b>{{ tsh(r.revenue) }}</b></div>
              @if (!d.hidden) { <p class="ph-muted">@if (r.commission > 0 || r.materials > 0) { − @if (r.commission > 0) { {{ i18n.t('st.commission') }} {{ tsh(r.commission) }} } @if (r.materials > 0) { · {{ i18n.t('rp.goods.used') }} {{ tsh(r.materials) }} } · } <span class="ph-good">{{ i18n.t('pl.profit') }} {{ tsh(r.profit) }}</span></p> }
            } @empty { <p class="ph-muted">{{ i18n.t('rp.none') }}</p> }
            @if (d.byService.length) {
              <hr class="ph-rule" />
              <div class="ph-line" data-testid="rp-services-total"><b>{{ i18n.t('rp.services.total') }}</b><b>{{ tsh(d.totals.services.revenue) }}</b></div>
              @if (!d.hidden) { <div class="ph-line" data-testid="rp-services-profit"><b>{{ i18n.t('rp.services.profit') }}</b><b class="ph-good">{{ tsh(d.totals.services.profit) }}</b></div> }
            }
          </section>

          @if (d.goodsSold.length) {
            <section class="ph-sec">
              <h3>{{ i18n.t('rp.goods.sold') }}</h3>
              @for (r of d.goodsSold; track r.name) {
                <div class="ph-line"><span>{{ r.name }} ×{{ r.qty }}</span><b>{{ tsh(r.revenue) }}</b></div>
                @if (!d.hidden) { <p class="ph-muted">{{ i18n.t('rp.cost') }} {{ tsh(r.cost) }} · <span class="ph-good">{{ i18n.t('pl.profit') }} {{ tsh(r.profit) }}</span></p> }
              }
              <hr class="ph-rule" />
              <div class="ph-line" data-testid="rp-goods-total"><b>{{ i18n.t('rp.goods.total') }}</b><b>{{ tsh(d.totals.goods.revenue) }}</b></div>
              @if (!d.hidden) {
                <div class="ph-line"><span class="ph-muted">{{ i18n.t('rp.cost') }}</span><b>{{ tsh(d.totals.goods.cost) }}</b></div>
                <div class="ph-line" data-testid="rp-goods-profit"><b>{{ i18n.t('rp.goods.profit') }}</b><b class="ph-good">{{ tsh(d.totals.goods.profit) }}</b></div>
              }
            </section>
          }

          <section class="ph-sec">
            <h3>{{ i18n.t('rp.by.stylist') }}</h3>
            @for (r of d.byStylist; track r.name) { <div class="ph-line"><span>{{ r.name }} ({{ r.services }} · {{ r.clients }} {{ i18n.t('st.clients') }})</span><b>{{ tsh(r.revenue) }}</b></div> } @empty { <p class="ph-muted">{{ i18n.t('rp.none') }}</p> }
          </section>

          <section class="ph-sec">
            <h3>{{ i18n.t('rp.by.method') }}</h3>
            @for (r of d.byMethod; track r.method) { <div class="ph-line"><span>{{ channel(r.method) }}</span><b>{{ tsh(r.amount) }}</b></div> } @empty { <p class="ph-muted">{{ i18n.t('rp.none') }}</p> }
          </section>

          @if (d.byBranch.length) {
            <section class="ph-sec">
              <h3>{{ i18n.t('rp.by.branch') }}</h3>
              @for (r of d.byBranch; track r.name) { <div class="ph-line"><span>{{ r.name }} ({{ r.sales }} {{ i18n.t('rp.sales') }})</span><b>{{ tsh(r.revenue) }}</b></div> }
            </section>
          }

          <section class="ph-sec">
            <h3>{{ i18n.t('rp.by.category') }}</h3>
            @for (r of d.expenses; track r.category) { <div class="ph-line"><span>{{ r.category }}</span><b>{{ tsh(r.total) }}</b></div> } @empty { <p class="ph-muted">{{ i18n.t('rp.none') }}</p> }
          </section>

          <section class="ph-sec" data-testid="rp-diary">
            <h3>{{ i18n.t('nav.ph.appointments') }}</h3>
            <div class="ph-line"><span>{{ i18n.t('rp.booked') }}</span><b>{{ d.diary['booked'] ?? 0 }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('ap.s.done') }}</span><b>{{ d.diary['done'] ?? 0 }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('rp.noshows') }}</span><b>{{ d.diary['no_show'] ?? 0 }}@if (d.diary['no_show_rate'] !== null && d.diary['no_show_rate'] !== undefined) { ({{ d.diary['no_show_rate'] }}%) }</b></div>
            <div class="ph-line"><span>{{ i18n.t('ap.s.cancelled') }}</span><b>{{ d.diary['cancelled'] ?? 0 }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('rp.open') }}</span><b>{{ d.diary['still_open'] ?? 0 }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('rp.online') }}</span><b>{{ d.diary['online'] ?? 0 }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('rp.deposits.kept') }}</span><b>{{ money(d.diary['deposits_kept']) }}</b></div>
          </section>

          <section class="ph-sec">
            <h3>{{ i18n.t('st.clients') }}</h3>
            <div class="ph-line"><span>{{ i18n.t('rp.came') }}</span><b>{{ d.clients['active'] ?? 0 }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('rp.new') }}</span><b>{{ d.clients['new'] ?? 0 }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('rp.returning') }}</span><b>{{ d.clients['returning'] ?? 0 }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('rp.not.seen', weeks(d)) }}</span><b>{{ d.clients['stopped_coming'] ?? 0 }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('rp.birthdays') }}</span><b>{{ d.clients['birthdays_this_month'] ?? 0 }}</b></div>
            @if (d.topSpenders.length) {
              <h4 class="ph-accent">{{ i18n.t('rp.best') }}</h4>
              @for (r of d.topSpenders; track r.name) { <div class="ph-line"><span>{{ r.name }} ({{ r.visits }})</span><b>{{ tsh(r.spent) }}</b></div> }
            }
          </section>

          <section class="ph-sec">
            <h3>{{ i18n.t('pl.owed') }}</h3>
            <div class="ph-line"><b>{{ i18n.t('rp.total') }}</b><b data-testid="rp-owed">{{ tsh(d.owedTotal) }}</b></div>
            @for (r of d.owed; track r.client) { <div class="ph-line"><span>{{ r.client }} · {{ r.days }} {{ i18n.t('rp.days') }}</span><b>{{ tsh(r.due) }}</b></div> }
          </section>

          <section class="ph-sec">
            <h3>{{ i18n.t('rp.shelves') }}</h3>
            <div class="ph-line"><span>{{ i18n.t('rp.items') }}</span><b>{{ d.stock['items'] ?? 0 }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('rp.at.cost') }}</span><b>{{ money(d.stock['at_cost']) }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('rp.at.price') }}</span><b>{{ money(d.stock['at_price']) }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('rp.low') }}</span><b>{{ d.stock['low'] ?? 0 }}</b></div>
          </section>
        </div>
      }
    </div>
  `,
})
export class ReportsPage implements OnInit {
  private readonly http = inject(HttpClient);
  protected readonly i18n = inject(I18nService);
  protected readonly tsh = tsh;
  protected readonly periods = PERIODS;

  protected readonly period = signal<Period>('month');
  protected readonly data = signal<SalonReport | null>(null);
  protected readonly error = signal('');
  private asked = 0;

  protected readonly range = computed(() => reportRange(this.period(), new Date()));
  protected readonly rangeLabel = computed(() => {
    const [a, b] = this.range();

    return a === b ? dayLabel(a) : `${dayLabel(a)} – ${dayLabel(b)}`;
  });

  ngOnInit(): void {
    void this.load();
  }

  protected weeks(d: SalonReport): number {
    return num(d.clients['stopped_after_weeks']) || 8;
  }

  protected money(v: unknown): string {
    return tsh(num(v));
  }

  protected periodName(p: Period): string {
    switch (p) {
      case 'today': return this.i18n.t('pl.p.today');
      case 'week': return this.i18n.t('pl.p.thisWeek');
      case 'year': return this.i18n.t('pl.p.thisYear');
      default: return this.i18n.t('pl.p.thisMonth');
    }
  }

  protected channel(method: string): string {
    switch (method) {
      case 'cash': return this.i18n.t('pl.ch.cash');
      case 'mpesa': return 'M-Pesa';
      case 'airtel_money': return 'Airtel Money';
      case 'tigo_pesa': return 'Tigo Pesa';
      case 'halopesa': return 'HaloPesa';
      case 'bank': return this.i18n.t('pl.ch.bank');
      case 'card': return this.i18n.t('pl.ch.card');
      default: return method.replace(/_/g, ' ');
    }
  }

  protected pick(p: Period): void {
    this.period.set(p);
    void this.load();
  }

  async load(): Promise<void> {
    const [from, to] = this.range();
    const ticket = ++this.asked;
    this.error.set('');
    try {
      const r = await firstValueFrom(this.http.get<{ data: Record<string, unknown> }>(`${environment.apiUrl}/inventory/salon/reports`, { params: { from, to } }));
      if (ticket !== this.asked) return;
      this.data.set(readSalonReport(r.data ?? {}));
    } catch {
      if (ticket !== this.asked) return;
      this.data.set(null);
      this.error.set(this.i18n.t('pl.error'));
    }
  }
}
