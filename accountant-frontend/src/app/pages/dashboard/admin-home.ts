import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { AccountantApi } from '../../core/accountant-api.service';
import { AuthService } from '../../core/auth.service';
import { dayLabel, dayOf, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { MonthlyReport } from '../../core/models';
import { Product } from '../../core/products.models';
import { ProductsApi } from '../../core/products-api.service';
import { SalonHomeApi, SalonOverview, TodayKpis } from '../../core/salon-home.service';

type Period = 'today' | 'week' | 'month' | 'year' | 'custom';

/**
 * The business admin's dashboard in a salon, as the phone shows it and in the phone's own look (dark teal glass cards): today's sales with
 * the filter, cash, credit and expenses, services and goods, the month against the last (and the target), the business overview, the sales
 * by day, the best earners and the services. Each part is read on its own and only for what the person may see, so a part the server
 * refuses is simply left out. It is one column, so it reads the same on a phone as on a computer.
 */
@Component({
  selector: 'app-admin-home',
  imports: [FormsModule, RouterLink],
  templateUrl: './admin-home.html',
})
export class AdminHomeComponent implements OnInit {
  private readonly api = inject(SalonHomeApi);
  private readonly accountant = inject(AccountantApi);
  private readonly products = inject(ProductsApi);
  protected readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);

  protected readonly tsh = tsh;
  protected readonly dayLabel = dayLabel;
  protected readonly Math = Math;

  protected readonly kpis = signal<TodayKpis | null>(null);
  protected readonly overview = signal<SalonOverview | null>(null);
  protected readonly report = signal<MonthlyReport | null>(null);
  protected readonly yesterday = signal<number | null>(null);
  protected readonly services = signal<number | null>(null);
  protected readonly goods = signal<number | null>(null);
  protected readonly low = signal<number | null>(null);
  protected readonly serviceList = signal<Product[]>([]);
  protected readonly days = signal<number[]>([]);
  protected readonly chartLoading = signal(false);
  protected readonly custom = signal<{ total: number; count: number } | null>(null);

  // the filter
  protected readonly period = signal<Period>('today');
  protected readonly sheet = signal(false);
  protected from = dayOf(new Date());
  protected to = dayOf(new Date());
  protected readonly todayIso = dayOf(new Date());

  // the chart's month (this year)
  protected readonly year = new Date().getFullYear();
  protected readonly month = signal(new Date().getMonth() + 1);

  protected readonly periods: Period[] = ['today', 'week', 'month', 'year'];

  protected readonly can = (k: string): boolean => this.auth.can(k);
  protected readonly name = computed(() => this.auth.user()?.name ?? '');

  /** The figures of the chosen period: the overview's own periods, or the sales of the dates picked. */
  protected readonly figures = computed(() => {
    const p = this.period();
    const o = this.overview();
    if (p === 'custom') {
      const c = this.custom();

      return c ? { sales: c.total, count: c.count, profit: null as number | null } : null;
    }
    const f = o?.periods[p];
    if (f) return { sales: f.revenue, count: f.sales, profit: f.net_profit ?? null };
    // The overview is refused for some people: today's total still comes from the till's own figures.
    if (p === 'today' && this.kpis()) return { sales: this.kpis()!.total, count: null as number | null, profit: null as number | null };

    return null;
  });

  /** Today against yesterday, for the bar and its words ("↑", "↓ 40%", "0%"). */
  protected readonly versus = computed(() => {
    if (this.period() !== 'today') return null;
    const y = this.yesterday();
    const today = this.figures()?.sales ?? 0;
    if (y === null) return null;
    const pct = y === 0 ? (today > 0 ? 1 : 0) : Math.max(0, Math.min(1, today / y));
    const ahead = today >= y;
    const label = y === 0 ? (today > 0 ? '↑' : '0%') : `${ahead ? '↑' : '↓'} ${Math.round(pct * 100)}%`;

    return { pct: pct * 100, ahead, label };
  });

  protected readonly periodLabel = computed(() => {
    const p = this.period();
    if (p === 'custom') return `${dayLabel(this.from)} – ${dayLabel(this.to)}`;

    return this.i18n.t(`period.${p}`);
  });

  /** The month's profit against the last month: the owner's own card on the phone (only with the profit right). */
  protected readonly monthCard = computed(() => {
    const r = this.report();
    if (!r || r.owner_figures === false) return null;
    const c = r.compare.net_profit;
    const sign = c.direction === 'same' ? '' : c.direction === 'up' ? '▲' : '▼';
    const pct = c.direction === 'same' ? this.i18n.t('trend.same') : c.percent === null ? this.i18n.t('trend.new') : `${Math.abs(c.percent).toFixed(Math.abs(c.percent) >= 10 ? 0 : 1)}%`;

    return { profit: c.now, before: c.before, sign, pct, good: c.good, target: r.target };
  });

  /** The four periods of the overview, in the order the phone shows them. */
  protected readonly periodTiles = computed(() => {
    const o = this.overview();
    if (!o) return [];
    const row = (key: 'today' | 'week' | 'month' | 'year') => ({ key, revenue: o.periods[key].revenue, profit: o.periods[key].net_profit ?? null });

    return [row('today'), row('week'), row('month'), row('year')];
  });

  protected readonly maxDay = computed(() => Math.max(1, ...this.days()));
  protected readonly chartTotal = computed(() => this.days().reduce((s, v) => s + v, 0));
  protected readonly monthName = computed(() => new Date(this.year, this.month() - 1, 1).toLocaleString(this.i18n.locale(), { month: 'long' }));

  /** The best earners of the month (the report's list: profit for the owner, sales for anyone else). */
  protected readonly top = computed(() => {
    const r = this.report();
    if (!r) return { profit: false, rows: [] as { name: string; value: number }[] };
    const owner = r.owner_figures !== false;
    const rows = (r.top_products ?? [])
      .map((p) => ({ name: p.name, value: owner ? p.profit : p.sales }))
      .filter((p) => p.value > 0)
      .slice(0, 6);

    return { profit: owner, rows };
  });

  ngOnInit(): void {
    void this.load();
  }

  /** Each part on its own: one that is refused or fails leaves the others standing. */
  private async load(): Promise<void> {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const day = dayOf(yesterday);
    const month = `${this.year}-${String(this.month()).padStart(2, '0')}`;
    await Promise.all([
      this.part(() => firstValueFrom(this.api.kpis()), (v) => this.kpis.set(v)),
      this.part(() => firstValueFrom(this.api.overview()), (v) => this.overview.set(v)),
      this.part(() => firstValueFrom(this.accountant.salesSummary({ from: day, to: day })), (v) => this.yesterday.set(v.total)),
      this.part(() => firstValueFrom(this.api.count({ kind: 'services' })), (v) => this.services.set(v)),
      this.part(() => firstValueFrom(this.api.count({ kind: 'goods' })), (v) => this.goods.set(v)),
      this.part(() => firstValueFrom(this.api.count({ low: true })), (v) => this.low.set(v)),
      this.part(() => firstValueFrom(this.accountant.monthlyReport(month)), (v) => this.report.set(v)),
      this.part(() => firstValueFrom(this.products.products({ q: '', status: 'active', kind: 'services', lowStock: false, categoryId: null, page: 1 })), (v) => this.serviceList.set(v.items.slice(0, 5))),
      this.loadChart(),
    ]);
  }

  private async loadChart(): Promise<void> {
    this.chartLoading.set(true);
    await this.part(() => firstValueFrom(this.api.monthlyChart(this.year, this.month())), (v) => this.days.set(v));
    this.chartLoading.set(false);
  }

  private async part<T>(read: () => Promise<T>, put: (v: T) => void): Promise<void> {
    try {
      put(await read());
    } catch {
      // not allowed, or not reachable: this part is left out
    }
  }

  // ------------------------------------------------------------------ the filter
  protected pick(p: Period): void {
    this.period.set(p);
    if (p !== 'custom') this.sheet.set(false);
  }

  protected async applyCustom(): Promise<void> {
    if (!this.from || !this.to) return;
    if (this.to < this.from) [this.from, this.to] = [this.to, this.from];
    this.period.set('custom');
    this.sheet.set(false);
    await this.part(
      () => firstValueFrom(this.accountant.salesSummary({ from: this.from, to: this.to })),
      (v) => this.custom.set({ total: v.total, count: v.count }),
    );
  }

  protected async moveMonth(by: number): Promise<void> {
    const next = this.month() + by;
    if (next < 1 || next > 12) return;
    this.month.set(next);
    await this.loadChart();
  }

  protected canNextMonth(): boolean {
    return this.month() < new Date().getMonth() + 1;
  }

  /** Where a day's bar sits, as a share of the tallest day (never invisible when there was a sale). */
  protected bar(v: number): number {
    return v <= 0 ? 0 : Math.max(3, (v / this.maxDay()) * 100);
  }

  protected barOf(value: number, best: number): number {
    return best <= 0 ? 0 : Math.max(4, Math.min(100, (value / best) * 100));
  }

  protected channel(method: string): string {
    const key = `pay.${method}`;
    const label = this.i18n.t(key);

    return label === key ? method : label;
  }

  protected top3<T>(rows: T[]): T[] {
    return rows.slice(0, 3);
  }
}
