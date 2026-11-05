import { Injectable, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, map } from 'rxjs';

import { environment } from '../../environments/environment';

const API = environment.apiUrl;

/** One period's figures on the home page. `net_profit` is left out by the server for anyone without the profit right. */
export interface PeriodFigures {
  revenue: number;
  expenses: number;
  net_profit?: number | null;
  clients: number;
  sales: number;
}

export interface RankedItem {
  name: string;
  revenue: number;
  times?: number;
}

export interface SalonOverview {
  periods: { today: PeriodFigures; week: PeriodFigures; month: PeriodFigures; year: PeriodFigures };
  month: { collections: { method: string; amount: number }[]; outstanding: number };
  top_services: RankedItem[];
  top_staff: RankedItem[];
  bookings: { today: number; upcoming: number };
  profit_hidden: boolean;
}

/** The figures of today the mobile app's dashboard opens with (the same server answer). */
export interface TodayKpis {
  total: number;
  cash: number;
  expenses: number;
  outstanding_debt: number;
}

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};

const period = (j: unknown): PeriodFigures => {
  const m = (j && typeof j === 'object' ? j : {}) as Record<string, unknown>;
  return {
    revenue: num(m['revenue']),
    expenses: num(m['expenses']),
    net_profit: m['net_profit'] === undefined || m['net_profit'] === null ? null : num(m['net_profit']),
    clients: num(m['clients']),
    sales: num(m['sales']),
  };
};

const ranked = (rows: unknown): RankedItem[] =>
  (Array.isArray(rows) ? rows : []).map((r) => {
    const m = r as Record<string, unknown>;
    return { name: String(m['name'] ?? ''), revenue: num(m['revenue']), times: num(m['times']) };
  });

/** The server calls behind the home page: the same ones the mobile app's salon dashboard makes. */
@Injectable({ providedIn: 'root' })
export class SalonHomeApi {
  private readonly http = inject(HttpClient);

  overview(): Observable<SalonOverview> {
    return this.http.get<{ data: Record<string, unknown> }>(`${API}/inventory/salon/overview`).pipe(
      map(({ data: d }) => {
        const periods = (d['periods'] ?? {}) as Record<string, unknown>;
        const month = (d['month'] ?? {}) as Record<string, unknown>;
        const bookings = (d['bookings'] ?? {}) as Record<string, unknown>;

        return {
          periods: { today: period(periods['today']), week: period(periods['week']), month: period(periods['month']), year: period(periods['year']) },
          month: {
            collections: (Array.isArray(month['collections']) ? (month['collections'] as Record<string, unknown>[]) : []).map((c) => ({ method: String(c['method'] ?? ''), amount: num(c['amount']) })),
            outstanding: num(month['outstanding']),
          },
          top_services: ranked(d['top_services']),
          top_staff: ranked(d['top_staff']),
          bookings: { today: num(bookings['today']), upcoming: num(bookings['upcoming']) },
          profit_hidden: d['profit_hidden'] === true || (periods['today'] as Record<string, unknown> | undefined)?.['net_profit'] === undefined,
        };
      }),
    );
  }

  kpis(): Observable<TodayKpis> {
    return this.http.get<{ data: Record<string, unknown> }>(`${API}/inventory/kpis`).pipe(
      map(({ data: d }) => {
        const t = (d['today'] ?? {}) as Record<string, unknown>;

        return { total: num(t['total']), cash: num(t['cash']), expenses: num(t['expenses']), outstanding_debt: num(d['outstanding_debt']) };
      }),
    );
  }

  /** How many services, goods, or goods running low there are: the total of a one-row page. */
  count(filter: { kind?: 'services' | 'goods'; low?: boolean }): Observable<number> {
    const params: Record<string, string> = { page: '1' };
    if (filter.kind) params['is_service'] = filter.kind === 'services' ? '1' : '0';
    if (filter.low) {
      params['low_stock'] = '1';
      params['is_service'] = '0';
    }

    return this.http.get<{ data?: unknown[]; meta?: { total?: number } }>(`${API}/inventory/products`, { params }).pipe(map((r) => r.meta?.total ?? r.data?.length ?? 0));
  }
}
