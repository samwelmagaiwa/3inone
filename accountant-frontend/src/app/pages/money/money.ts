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
    <div class="ad ph-page" data-testid="money-page">
      <!-- the dates and the main figures stay pinned while the statements scroll -->
      <div class="g-pin">
        <div class="g-toolbar pl-dates" data-testid="pl-dates">
          <label class="pl-field">{{ i18n.t('pl.quick') }}
            <select class="g-select" [ngModel]="period()" (ngModelChange)="pick($event)" data-testid="pl-quick">
              @for (p of periods; track p) { <option [value]="p">{{ periodName(p) }}</option> }
            </select>
          </label>
          <label class="pl-field">{{ i18n.t('ad.from') }} <input class="g-select" type="date" [ngModel]="from()" (ngModelChange)="setFrom($event)" data-testid="pl-from" /></label>
          <label class="pl-field">{{ i18n.t('ad.to') }} <input class="g-select" type="date" [ngModel]="to()" (ngModelChange)="setTo($event)" data-testid="pl-to" /></label>
          <span class="ph-muted pl-range">{{ rangeLabel() }}</span>
        </div>
        @if (data(); as d) {
          <div class="ph-tiles g-tiles-row" data-testid="pl-tiles">
            <div class="ph-tile g-t-green"><span class="ph-muted">{{ i18n.t('pl.revenue') }}</span><b class="ph-good" data-testid="pl-t-revenue">{{ tsh(d.revenue) }}</b></div>
            <div class="ph-tile g-t-yellow"><span class="ph-muted">{{ i18n.t('pl.costs') }}</span><b class="ph-warn">{{ tsh(d.profitHidden ? d.expenses : d.operatingCosts + d.costOfGoods) }}</b></div>
            @if (!d.profitHidden) {
              <div class="ph-tile" [class.g-t-green]="d.netProfit >= 0" [class.g-t-red]="d.netProfit < 0"><span class="ph-muted">{{ d.netProfit >= 0 ? i18n.t('pl.profit') : i18n.t('pl.loss') }}</span><b [class.ph-good]="d.netProfit >= 0" [class.ph-bad]="d.netProfit < 0" data-testid="pl-t-profit">{{ tsh(d.netProfit) }}</b></div>
              <div class="ph-tile g-t-purple"><span class="ph-muted">{{ i18n.t('pl.gross') }}</span><b>{{ tsh(d.grossProfit) }}</b></div>
            }
            <div class="ph-tile g-t-teal"><span class="ph-muted">{{ i18n.t('pl.received.total') }}</span><b class="ph-accent">{{ tsh(d.collected) }}</b></div>
            <div class="ph-tile" [class.g-t-red]="d.outstanding > 0" [class.g-t-gray]="d.outstanding <= 0"><span class="ph-muted">{{ i18n.t('pl.owed') }}</span><b [class.ph-bad]="d.outstanding > 0">{{ tsh(d.outstanding) }}</b></div>
            @if (d.vatTotal > 0) { <div class="ph-tile g-t-blue"><span class="ph-muted">{{ i18n.t('pl.vat.total') }}</span><b>{{ tsh(d.vatTotal) }}</b></div> }
          </div>
        }
      </div>

      @if (error()) {
        <section class="ph-card pl-wide"><p data-testid="pl-error">{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (!data()) {
        <section class="ph-card pl-wide"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else {
        @let d = data()!;
        <div class="pl-grid pl-wide" data-testid="pl-joined">
          <!-- the statement: what came in, what it cost, what is left -->
          <section class="pl-block" data-testid="pl-statement">
            <h3 class="pl-title">{{ d.profitHidden ? i18n.t('pl.running') : i18n.t('pl.statement') }}</h3>
            <div class="table-scroll-container fit-page">
              <table class="grid-table g-grid">
                <thead><tr><th>{{ i18n.t('pl.item') }}</th><th class="text-right">{{ i18n.t('g.amount') }}</th></tr></thead>
                <tbody>
                  @if (!d.profitHidden) {
                    <tr><td>{{ i18n.t('pl.service.revenue') }}</td><td class="text-right">{{ tsh(d.serviceRevenue) }}</td></tr>
                    <tr><td>{{ i18n.t('pl.goods.revenue') }}</td><td class="text-right">{{ tsh(d.goodsRevenue) }}</td></tr>
                    @if (d.discounts > 0) { <tr><td class="ph-muted">{{ i18n.t('pl.discounts', tsh(d.discounts)) }}</td><td></td></tr> }
                    <tr><td>{{ i18n.t('pl.cogs') }}</td><td class="text-right ph-bad">− {{ tsh(d.costOfGoods) }}</td></tr>
                    <tr class="pl-sum"><td>{{ i18n.t('pl.gross') }}</td><td class="text-right" data-testid="pl-gross">{{ tsh(d.grossProfit) }}</td></tr>
                  }
                  @for (g of d.expensesByCategory; track g.category) {
                    <tr><td class="g-long" [title]="g.category">{{ g.category }}</td><td class="text-right ph-bad">− {{ tsh(g.total) }}</td></tr>
                  } @empty {
                    <tr><td>{{ i18n.t('pl.expenses') }}</td><td class="text-right">{{ tsh(0) }}</td></tr>
                  }
                  @if (!d.profitHidden) {
                    <tr><td>{{ i18n.t('pl.commissions') }}</td><td class="text-right ph-bad">− {{ tsh(d.commissions) }}</td></tr>
                    <tr><td>{{ i18n.t('pl.salaries') }}</td><td class="text-right ph-bad">− {{ tsh(d.salaries) }}</td></tr>
                  }
                </tbody>
                @if (!d.profitHidden) {
                  <tfoot><tr><td class="font-bold">{{ d.netProfit >= 0 ? i18n.t('pl.net.profit') : i18n.t('pl.net.loss') }}</td>
                    <td class="text-right"><b [class.ph-good]="d.netProfit >= 0" [class.ph-bad]="d.netProfit < 0" data-testid="pl-net">{{ tsh(d.netProfit) }}</b></td></tr></tfoot>
                }
              </table>
            </div>
          </section>

          <div class="pl-col">
            @if (!d.profitHidden) {
              <!-- where the profit came from: goods and services side by side -->
              <section class="pl-block" data-testid="pl-where">
                <h3 class="pl-title">{{ i18n.t('pl.where') }}</h3>
                <div class="table-scroll-container fit-page">
                  <table class="grid-table g-grid">
                    <thead><tr><th>{{ i18n.t('g.kind') }}</th><th class="text-right">{{ i18n.t('pl.sold.for') }}</th><th class="text-right">{{ i18n.t('pl.cost') }}</th><th class="text-right">{{ i18n.t('pl.profit') }}</th></tr></thead>
                    <tbody>
                      <tr><td class="font-bold">{{ i18n.t('pl.goods') }}</td><td class="text-right">{{ tsh(d.goodsRevenue) }}</td><td class="text-right">− {{ tsh(d.goodsCost) }}</td>
                        <td class="text-right"><b [class.ph-good]="d.goodsProfit >= 0" [class.ph-bad]="d.goodsProfit < 0">{{ tsh(d.goodsProfit) }}</b></td></tr>
                      <tr><td class="font-bold">{{ i18n.t('pl.services') }}</td><td class="text-right">{{ tsh(d.serviceRevenue) }}</td><td class="text-right">− {{ tsh(d.serviceRevenue - d.servicesProfit) }}</td>
                        <td class="text-right"><b [class.ph-good]="d.servicesProfit >= 0" [class.ph-bad]="d.servicesProfit < 0">{{ tsh(d.servicesProfit) }}</b></td></tr>
                    </tbody>
                  </table>
                </div>
                <p class="ph-muted pl-hint">{{ i18n.t('pl.where.hint') }}</p>
              </section>
            }

            <!-- the money that actually came in, by how it was paid -->
            <section class="pl-block" data-testid="pl-received">
              <h3 class="pl-title">{{ i18n.t('pl.received') }}</h3>
              <div class="table-scroll-container fit-page">
                <table class="grid-table g-grid">
                  <thead><tr><th>{{ i18n.t('pr.paid.by') }}</th><th class="text-right">{{ i18n.t('g.amount') }}</th></tr></thead>
                  <tbody>
                    @for (c of d.collections; track c.method) {
                      <tr><td>{{ channel(c.method) }}</td><td class="text-right">{{ tsh(c.amount) }}</td></tr>
                    } @empty {
                      <tr><td colspan="2" class="ph-muted">{{ i18n.t('pl.received.none') }}</td></tr>
                    }
                    <tr><td>{{ i18n.t('pl.owed') }}</td><td class="text-right"><span [class.ph-warn]="d.outstanding > 0">{{ tsh(d.outstanding) }}</span></td></tr>
                    @if (d.otherIncome > 0) { <tr><td>{{ i18n.t('pl.other.income') }}</td><td class="text-right">{{ tsh(d.otherIncome) }}</td></tr> }
                    @if (d.depositsHeld > 0) { <tr><td class="ph-muted">{{ i18n.t('pl.deposits') }}</td><td class="text-right">{{ tsh(d.depositsHeld) }}</td></tr> }
                  </tbody>
                  <tfoot><tr><td class="font-bold">{{ i18n.t('pl.received.total') }}</td><td class="text-right"><b data-testid="pl-collected">{{ tsh(d.collected) }}</b></td></tr></tfoot>
                </table>
              </div>
            </section>

            @if (d.vatTotal > 0) {
              <section class="pl-block" data-testid="pl-vat">
                <h3 class="pl-title">{{ i18n.t('pl.vat') }}</h3>
                <div class="table-scroll-container fit-page">
                  <table class="grid-table g-grid">
                    <thead><tr><th>{{ i18n.t('pl.rate') }}</th><th class="text-right">{{ i18n.t('pl.taxable.col') }}</th><th class="text-right">{{ i18n.t('pl.vat') }}</th></tr></thead>
                    <tbody>
                      @for (r of d.vatByRate; track r.rate) {
                        <tr><td>{{ r.rate }}%</td><td class="text-right">{{ tsh(r.taxable) }}</td><td class="text-right">{{ tsh(r.vat) }}</td></tr>
                      }
                    </tbody>
                    <tfoot><tr><td class="font-bold" colspan="2">{{ i18n.t('pl.vat.total') }}</td><td class="text-right"><b>{{ tsh(d.vatTotal) }}</b></td></tr></tfoot>
                  </table>
                </div>
              </section>
            }
          </div>
        </div>

        <p class="ph-muted pl-wide" data-testid="pl-footer">{{ footer() }}</p>
        <p class="ph-muted pl-wide"><i>{{ i18n.t('pl.note') }}</i></p>
      }
    </div>
  `,
  styles: [
    `
      .pl-wide { grid-column: 1 / -1; }
      .pl-dates { align-items: end; }
      .pl-field { display: grid; gap: 3px; font-size: 11px; font-weight: 800; text-transform: uppercase; }
      .pl-range { align-self: center; margin-left: 6px; font-weight: 700; }
      .pl-grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 14px; align-items: start; }
      .pl-col { display: grid; gap: 14px; }
      .pl-block { min-width: 0; }
      h3.pl-title { margin: 4px 0 8px; font-size: 16px; font-weight: 900; }
      .pl-sum td { font-weight: 900; }
      .pl-hint { margin: 6px 0 0; font-size: 12px; }
      @media (max-width: 1100px) { .pl-grid { grid-template-columns: 1fr; } }
    `,
  ],
})
export class MoneyPage implements OnInit {
  private readonly http = inject(HttpClient);
  protected readonly i18n = inject(I18nService);
  protected readonly tsh = tsh;
  protected readonly periods = PERIODS;

  protected readonly period = signal<Period>('thisMonth');
  protected readonly from = signal(periodRange('thisMonth', new Date())[0]);
  protected readonly to = signal(periodRange('thisMonth', new Date())[1]);
  protected readonly data = signal<ProfitLossData | null>(null);
  protected readonly error = signal('');
  private asked = 0;

  protected readonly range = computed(() => periodRange('custom', new Date(), this.from(), this.to()));
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

  /** A quick pick fills in the two dates and shows the report; "Pick dates" leaves them for the person to set. */
  protected pick(p: Period): void {
    this.period.set(p);
    if (p === 'custom') return;
    const [a, b] = periodRange(p, new Date());
    this.from.set(a);
    this.to.set(b);
    void this.load();
  }

  protected setFrom(v: string): void {
    this.from.set(v);
    this.changed();
  }

  protected setTo(v: string): void {
    this.to.set(v);
    this.changed();
  }

  /** Dates written by hand: the report follows once both are real days. */
  private changed(): void {
    this.period.set('custom');
    if (/^\d{4}-\d{2}-\d{2}$/.test(this.from()) && /^\d{4}-\d{2}-\d{2}$/.test(this.to())) void this.load();
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
