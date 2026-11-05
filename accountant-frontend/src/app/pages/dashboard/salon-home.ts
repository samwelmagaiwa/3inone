import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { AccountantApi } from '../../core/accountant-api.service';
import { AuthService } from '../../core/auth.service';
import { dayOf, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { SalonHomeApi, SalonOverview, TodayKpis } from '../../core/salon-home.service';

/**
 * What the mobile app's salon dashboard shows, on the web: who is signed in with the places they can go, today's sales against
 * yesterday, the cash, credit and expenses of the day, how many services and goods there are and how many are running low, then the
 * business overview (today, week, month, year, the diary, clients, debts, the best stylists and services, the money received).
 * Each part is read on its own, so what a person may not see (the server answers 403) is simply left out.
 */
@Component({
  selector: 'app-salon-home',
  imports: [RouterLink],
  templateUrl: './salon-home.html',
})
export class SalonHomeComponent implements OnInit {
  private readonly api = inject(SalonHomeApi);
  private readonly accountant = inject(AccountantApi);
  protected readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);

  protected readonly tsh = tsh;

  protected readonly kpis = signal<TodayKpis | null>(null);
  protected readonly overview = signal<SalonOverview | null>(null);
  protected readonly yesterday = signal<number | null>(null);
  protected readonly services = signal<number | null>(null);
  protected readonly goods = signal<number | null>(null);
  protected readonly low = signal<number | null>(null);
  protected readonly loaded = signal(false);

  protected readonly name = computed(() => this.auth.user()?.name ?? '');
  protected readonly role = computed(() => this.auth.user()?.roleLabel ?? '');

  /** The places the mobile app's quick buttons lead to, for what the person may do. */
  protected readonly links = computed(() => {
    const out: { label: string; to: string; icon: string }[] = [];
    if (this.auth.can('inv_create_sales')) out.push({ label: 'home.sell', to: '/sales/new', icon: 'M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17' });
    if (this.auth.can('inv_view_products')) out.push({ label: 'home.products', to: '/products', icon: 'M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4' });
    if (this.auth.can('inv_view_credit')) out.push({ label: 'home.credit', to: '/customers', icon: 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z' });
    if (this.auth.can('inv_view_expenses')) out.push({ label: 'home.expenses', to: '/expenses', icon: 'M9 14l6-6m-5.5.5h.01m4.99 5h.01M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16l3.5-2 3.5 2 3.5-2 3.5 2z' });

    return out;
  });

  /** Today against yesterday: a bar filled to the share of yesterday reached, and its words ("↑", "↓ 40%", "0%"). */
  protected readonly versus = computed(() => {
    const today = this.kpis()?.total ?? this.overview()?.periods.today.revenue ?? 0;
    const y = this.yesterday();
    if (y === null) return null;
    const pct = y === 0 ? (today > 0 ? 1 : 0) : Math.max(0, Math.min(1, today / y));
    const ahead = today >= y;
    const label = y === 0 ? (today > 0 ? '↑' : '0%') : `${ahead ? '↑' : '↓'} ${Math.round(pct * 100)}%`;

    return { pct: pct * 100, ahead, label };
  });

  protected readonly todaySales = computed(() => this.kpis()?.total ?? this.overview()?.periods.today.revenue ?? 0);
  protected readonly todayCount = computed(() => this.overview()?.periods.today.sales ?? null);

  /** The four periods in the order the mobile app shows them. */
  protected readonly periods = computed(() => {
    const o = this.overview();
    if (!o) return [];

    return [
      { key: 'home.today', f: o.periods.today },
      { key: 'home.week', f: o.periods.week },
      { key: 'home.month', f: o.periods.month },
      { key: 'home.year', f: o.periods.year },
    ];
  });

  ngOnInit(): void {
    void this.load();
  }

  /** Each part on its own: one that is refused or fails leaves the others standing. */
  private async load(): Promise<void> {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const day = dayOf(yesterday);
    await Promise.all([
      this.part(() => firstValueFrom(this.api.kpis()), (v) => this.kpis.set(v)),
      this.part(() => firstValueFrom(this.api.overview()), (v) => this.overview.set(v)),
      this.part(() => firstValueFrom(this.accountant.salesSummary({ from: day, to: day })), (v) => this.yesterday.set(v.total)),
      this.part(() => firstValueFrom(this.api.count({ kind: 'services' })), (v) => this.services.set(v)),
      this.part(() => firstValueFrom(this.api.count({ kind: 'goods' })), (v) => this.goods.set(v)),
      this.part(() => firstValueFrom(this.api.count({ low: true })), (v) => this.low.set(v)),
    ]);
    this.loaded.set(true);
  }

  private async part<T>(read: () => Promise<T>, put: (v: T) => void): Promise<void> {
    try {
      put(await read());
    } catch {
      // not allowed, or not reachable: this part is left out
    }
  }

  protected channel(method: string): string {
    const key = `pay.${method}`;
    const label = this.i18n.t(key);

    return label === key ? method : label;
  }

  /** How wide a league-table bar is against the best one. */
  protected bar(value: number, best: number): number {
    return best <= 0 ? 0 : Math.max(4, Math.min(100, (value / best) * 100));
  }

  protected top<T>(rows: T[]): T[] {
    return rows.slice(0, 3);
  }
}
