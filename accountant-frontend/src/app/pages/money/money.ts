import { HttpClient } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { dayLabel, dayOf, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';

type Period = 'today' | 'yesterday' | 'last7' | 'thisWeek' | 'lastWeek' | 'thisMonth' | 'lastMonth' | 'thisYear' | 'custom';

const PERIODS: Period[] = ['today', 'yesterday', 'last7', 'thisWeek', 'lastWeek', 'thisMonth', 'lastMonth', 'thisYear', 'custom'];

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

const rows = (v: unknown): Record<string, unknown>[] => (Array.isArray(v) ? (v as Record<string, unknown>[]) : []);

/** The salon's profit and loss, as the phone shows it (the same server answer, read the same way). */
export interface ProfitLossData {
  serviceRevenue: number;
  goodsRevenue: number;
  revenue: number;
  discounts: number;
  costOfGoods: number;
  goodsCost: number;
  goodsProfit: number;
  servicesProfit: number;
  grossProfit: number;
  expenses: number;
  expensesByCategory: { category: string; total: number }[];
  commissions: number;
  salaries: number;
  operatingCosts: number;
  netProfit: number;
  collections: { method: string; amount: number }[];
  collected: number;
  outstanding: number;
  cancelledCount: number;
  cancelledTotal: number;
  sales: number;
  clients: number;
  vatTotal: number;
  vatByRate: { rate: number; taxable: number; vat: number }[];
  otherIncome: number;
  depositsHeld: number;
  profitHidden: boolean;
}

export function readProfitLoss(j: Record<string, unknown>): ProfitLossData {
  const cancelled = (j['cancelled'] && typeof j['cancelled'] === 'object' ? j['cancelled'] : {}) as Record<string, unknown>;
  const vat = (j['vat'] && typeof j['vat'] === 'object' ? j['vat'] : {}) as Record<string, unknown>;

  return {
    serviceRevenue: num(j['service_revenue']),
    goodsRevenue: num(j['goods_revenue']),
    revenue: num(j['revenue']),
    discounts: num(j['discounts']),
    costOfGoods: num(j['cost_of_goods']),
    goodsCost: num(j['goods_cost']),
    goodsProfit: num(j['goods_profit']),
    servicesProfit: num(j['services_profit']),
    grossProfit: num(j['gross_profit']),
    expenses: num(j['expenses']),
    expensesByCategory: rows(j['expenses_by_category']).map((r) => ({ category: String(r['category'] ?? ''), total: num(r['total']) })),
    commissions: num(j['commissions']),
    salaries: num(j['salaries']),
    operatingCosts: num(j['operating_costs']),
    netProfit: num(j['net_profit']),
    collections: rows(j['collections']).map((r) => ({ method: String(r['method'] ?? ''), amount: num(r['amount']) })),
    collected: num(j['collected']),
    outstanding: num(j['outstanding']),
    cancelledCount: num(cancelled['count']),
    cancelledTotal: num(cancelled['total']),
    sales: num(j['sales']),
    clients: num(j['clients']),
    vatTotal: num(vat['total']),
    vatByRate: rows(vat['by_rate']).map((r) => ({ rate: num(r['rate']), taxable: num(r['taxable']), vat: num(r['vat']) })),
    otherIncome: num(j['other_income']),
    depositsHeld: num(j['deposits_held']),
    profitHidden: j['profit_hidden'] === true,
  };
}

/** The first and last day of a period as of `now` (weeks run Monday to Sunday), the same rule as the phone's. */
export function periodRange(p: Period, now: Date, from = '', to = ''): [string, string] {
  const t = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const back = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() - n);
  const monday = back(t, (t.getDay() + 6) % 7);

  switch (p) {
    case 'today':
      return [dayOf(t), dayOf(t)];
    case 'yesterday':
      return [dayOf(back(t, 1)), dayOf(back(t, 1))];
    case 'last7':
      return [dayOf(back(t, 6)), dayOf(t)];
    case 'thisWeek':
      return [dayOf(monday), dayOf(t)];
    case 'lastWeek':
      return [dayOf(back(monday, 7)), dayOf(back(monday, 1))];
    case 'thisMonth':
      return [dayOf(new Date(t.getFullYear(), t.getMonth(), 1)), dayOf(t)];
    case 'lastMonth':
      return [dayOf(new Date(t.getFullYear(), t.getMonth() - 1, 1)), dayOf(new Date(t.getFullYear(), t.getMonth(), 0))];
    case 'thisYear':
      return [dayOf(new Date(t.getFullYear(), 0, 1)), dayOf(t)];
    case 'custom':
      return from && to ? [from <= to ? from : to, from <= to ? to : from] : [dayOf(back(t, 6)), dayOf(t)];
  }
}

@Component({
  selector: 'app-money',
  imports: [FormsModule],
  template: `
    <div class="ad pl" data-testid="money-page">
      <div class="pl-chips" role="tablist">
        @for (p of periods; track p) {
          <button type="button" class="pill-tab" [class.is-active]="period() === p" [attr.data-testid]="'pl-period-' + p" (click)="pick(p)">{{ periodName(p) }}</button>
        }
      </div>
      @if (period() === 'custom') {
        <div class="pl-dates glass">
          <label>{{ i18n.t('ad.from') }} <input type="date" [ngModel]="from()" (ngModelChange)="from.set($event)" data-testid="pl-from" /></label>
          <label>{{ i18n.t('ad.to') }} <input type="date" [ngModel]="to()" (ngModelChange)="to.set($event)" data-testid="pl-to" /></label>
          <button type="button" class="btn-primary" (click)="load()" data-testid="pl-apply">{{ i18n.t('ad.apply') }}</button>
        </div>
      }
      <p class="pl-range">{{ rangeLabel() }}</p>

      @if (error()) {
        <section class="glass pl-card"><p data-testid="pl-error">{{ error() }}</p><button type="button" class="btn-outline" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (!data()) {
        <section class="glass pl-card"><p class="pl-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else {
        @let d = data()!;
        <div class="pl-tiles">
          <div class="glass pl-tile"><span class="pl-muted">{{ i18n.t('pl.revenue') }}</span><b class="pl-good" data-testid="pl-t-revenue">{{ tsh(d.revenue) }}</b></div>
          <div class="glass pl-tile"><span class="pl-muted">{{ i18n.t('pl.costs') }}</span><b class="pl-warn">{{ tsh(d.profitHidden ? d.expenses : d.operatingCosts + d.costOfGoods) }}</b></div>
          @if (!d.profitHidden) {
            <div class="glass pl-tile"><span class="pl-muted">{{ d.netProfit >= 0 ? i18n.t('pl.profit') : i18n.t('pl.loss') }}</span><b [class.pl-good]="d.netProfit >= 0" [class.pl-bad]="d.netProfit < 0" data-testid="pl-t-profit">{{ tsh(d.netProfit) }}</b></div>
          }
        </div>

        @if (!d.profitHidden) {
          <section class="glass pl-card">
            <div class="pl-line"><span>{{ i18n.t('pl.service.revenue') }}</span><b>{{ tsh(d.serviceRevenue) }}</b></div>
            <div class="pl-line"><span>{{ i18n.t('pl.goods.revenue') }}</span><b>{{ tsh(d.goodsRevenue) }}</b></div>
            @if (d.discounts > 0) { <p class="pl-muted">{{ i18n.t('pl.discounts', tsh(d.discounts)) }}</p> }
            <div class="pl-line"><span>{{ i18n.t('pl.cogs') }}</span><b>− {{ tsh(d.costOfGoods) }}</b></div>
            <hr />
            <div class="pl-line pl-strong"><span>{{ i18n.t('pl.gross') }}</span><b data-testid="pl-gross">{{ tsh(d.grossProfit) }}</b></div>
          </section>

          <section class="glass pl-card">
            <h3>{{ i18n.t('pl.where') }}</h3>
            <p class="pl-muted">{{ i18n.t('pl.where.hint') }}</p>
            <h4>{{ i18n.t('pl.goods') }}</h4>
            <div class="pl-line"><span>{{ i18n.t('pl.sold.for') }}</span><b>{{ tsh(d.goodsRevenue) }}</b></div>
            <div class="pl-line"><span>{{ i18n.t('pl.bought.for') }}</span><b>− {{ tsh(d.goodsCost) }}</b></div>
            <div class="pl-line pl-strong"><span>{{ i18n.t('pl.goods.profit') }}</span><b [class.pl-good]="d.goodsProfit >= 0" [class.pl-bad]="d.goodsProfit < 0">{{ tsh(d.goodsProfit) }}</b></div>
            <hr />
            <h4>{{ i18n.t('pl.services') }}</h4>
            <div class="pl-line"><span>{{ i18n.t('pl.service.revenue') }}</span><b>{{ tsh(d.serviceRevenue) }}</b></div>
            @if (d.servicesProfit !== d.serviceRevenue) {
              <div class="pl-line"><span>{{ i18n.t('pl.service.costs') }}</span><b>{{ tsh(d.servicesProfit - d.serviceRevenue) }}</b></div>
            }
            <div class="pl-line pl-strong"><span>{{ i18n.t('pl.services.profit') }}</span><b [class.pl-good]="d.servicesProfit >= 0" [class.pl-bad]="d.servicesProfit < 0">{{ tsh(d.servicesProfit) }}</b></div>
          </section>
        }

        <section class="glass pl-card">
          <h3>{{ i18n.t('pl.running') }}</h3>
          @for (g of d.expensesByCategory; track g.category) {
            <div class="pl-line"><span>{{ g.category }}</span><b>− {{ tsh(g.total) }}</b></div>
          } @empty {
            <div class="pl-line"><span>{{ i18n.t('pl.expenses') }}</span><b>{{ tsh(0) }}</b></div>
          }
          @if (!d.profitHidden) {
            <div class="pl-line"><span>{{ i18n.t('pl.commissions') }}</span><b>− {{ tsh(d.commissions) }}</b></div>
            <div class="pl-line"><span>{{ i18n.t('pl.salaries') }}</span><b>− {{ tsh(d.salaries) }}</b></div>
            <hr />
            <div class="pl-line pl-strong"><span>{{ d.netProfit >= 0 ? i18n.t('pl.net.profit') : i18n.t('pl.net.loss') }}</span><b [class.pl-good]="d.netProfit >= 0" [class.pl-bad]="d.netProfit < 0" data-testid="pl-net">{{ tsh(d.netProfit) }}</b></div>
          }
        </section>

        <section class="glass pl-card">
          <h3>{{ i18n.t('pl.received') }}</h3>
          @for (c of d.collections; track c.method) {
            <div class="pl-line"><span>{{ channel(c.method) }}</span><b>{{ tsh(c.amount) }}</b></div>
          } @empty {
            <p class="pl-muted">{{ i18n.t('pl.received.none') }}</p>
          }
          <hr />
          <div class="pl-line pl-strong"><span>{{ i18n.t('pl.received.total') }}</span><b data-testid="pl-collected">{{ tsh(d.collected) }}</b></div>
          <div class="pl-line"><span>{{ i18n.t('pl.owed') }}</span><b [class.pl-warn]="d.outstanding > 0">{{ tsh(d.outstanding) }}</b></div>
          @if (d.otherIncome > 0) { <div class="pl-line"><span>{{ i18n.t('pl.other.income') }}</span><b>{{ tsh(d.otherIncome) }}</b></div> }
          @if (d.depositsHeld > 0) { <div class="pl-line"><span class="pl-muted">{{ i18n.t('pl.deposits') }}</span><b>{{ tsh(d.depositsHeld) }}</b></div> }
        </section>

        @if (d.vatTotal > 0) {
          <section class="glass pl-card">
            <h3>{{ i18n.t('pl.vat') }}</h3>
            @for (r of d.vatByRate; track r.rate) {
              <div class="pl-line"><span>{{ r.rate }}% ({{ i18n.t('pl.taxable') }} {{ tsh(r.taxable) }})</span><b>{{ tsh(r.vat) }}</b></div>
            }
            <hr />
            <div class="pl-line pl-strong"><span>{{ i18n.t('pl.vat.total') }}</span><b>{{ tsh(d.vatTotal) }}</b></div>
          </section>
        }

        <p class="pl-muted" data-testid="pl-footer">{{ footer() }}</p>
        <p class="pl-muted"><i>{{ i18n.t('pl.note') }}</i></p>
      }
    </div>
  `,
  styles: [
    `
      .pl { display: grid; gap: 10px; max-width: 760px; margin: 0 auto; }
      .pl-chips { display: flex; flex-wrap: wrap; gap: 6px; }
      .pl-chips .pill-tab { padding: 6px 12px; border-radius: 99px; font-size: 12.5px; font-weight: 800; cursor: pointer; }
      .pl-dates { display: flex; flex-wrap: wrap; gap: 10px; align-items: end; padding: 10px 12px; border-radius: 14px; }
      .pl-dates label { display: grid; gap: 3px; font-size: 11px; font-weight: 800; text-transform: uppercase; }
      .pl-dates input { padding: 6px 8px; border-radius: 8px; }
      .pl-dates .btn-primary { padding: 8px 14px; border-radius: 10px; font-weight: 900; }
      .pl-range { font-size: 13px; font-weight: 700; opacity: .8; }
      .glass { background: rgba(255, 255, 255, 0.1); border: 1px solid rgba(255, 255, 255, 0.18); border-radius: 16px; }
      .pl-tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 8px; }
      .pl-tile { display: grid; gap: 2px; padding: 10px 12px; }
      .pl-tile b { font-size: 18px; font-weight: 900; }
      .pl-card { padding: 12px 14px; }
      .pl-card h3 { font-size: 15px; font-weight: 900; margin-bottom: 4px; }
      .pl-card h4 { margin: 8px 0 2px; font-size: 13px; font-weight: 800; color: #20b8ce; }
      .pl-card hr { border: 0; border-top: 1px solid rgba(255, 255, 255, 0.2); margin: 6px 0; }
      .pl-line { display: flex; justify-content: space-between; gap: 12px; padding: 3px 0; font-size: 14px; }
      .pl-line b { font-weight: 700; white-space: nowrap; }
      .pl-strong span, .pl-strong b { font-weight: 900; }
      .pl-muted { font-size: 12px; opacity: 0.7; }
      .pl-good { color: #86efac !important; }
      .pl-bad { color: #fca5a5 !important; }
      .pl-warn { color: #fcd34d !important; }
    `,
  ],
})
export class MoneyPage implements OnInit {
  private readonly http = inject(HttpClient);
  protected readonly i18n = inject(I18nService);
  protected readonly tsh = tsh;
  protected readonly periods = PERIODS;

  protected readonly period = signal<Period>('thisMonth');
  protected readonly from = signal(dayOf(new Date()));
  protected readonly to = signal(dayOf(new Date()));
  protected readonly data = signal<ProfitLossData | null>(null);
  protected readonly error = signal('');
  private asked = 0;

  protected readonly range = computed(() => periodRange(this.period(), new Date(), this.from(), this.to()));
  protected readonly rangeLabel = computed(() => {
    const [a, b] = this.range();

    return a === b ? dayLabel(a) : `${dayLabel(a)} – ${dayLabel(b)}`;
  });

  protected readonly footer = computed(() => {
    const d = this.data();
    if (!d) return '';
    const base = this.i18n.t('pl.footer', d.clients, d.sales);

    return d.cancelledCount > 0 ? `${base} • ${this.i18n.t('pl.cancelled', d.cancelledCount, tsh(d.cancelledTotal))}` : base;
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
    if (p !== 'custom') void this.load();
  }

  async load(): Promise<void> {
    const [from, to] = this.range();
    const ticket = ++this.asked;
    this.error.set('');
    try {
      const r = await firstValueFrom(this.http.get<{ data: Record<string, unknown> }>(`${environment.apiUrl}/inventory/salon/profit-loss`, { params: { from, to } }));
      if (ticket !== this.asked) return;
      this.data.set(readProfitLoss(r.data ?? {}));
    } catch {
      if (ticket !== this.asked) return;
      this.data.set(null);
      this.error.set(this.i18n.t('pl.error'));
    }
  }
}
