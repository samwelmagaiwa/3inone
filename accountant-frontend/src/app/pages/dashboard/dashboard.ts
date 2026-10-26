import { Component, OnInit, inject, signal } from '@angular/core';

import { errorMessage, monthKey, monthName, shiftMonth, tsh } from '../../core/format';
import { Comparison, MonthlyReport } from '../../core/models';
import { MoneyApiService } from '../../core/money-api.service';

/** The month on one page, from the same report the mobile app shows: how it compares with last month, the target, the figures. */
@Component({
  selector: 'app-dashboard',
  templateUrl: './dashboard.html',
})
export class DashboardPage implements OnInit {
  private readonly api = inject(MoneyApiService);

  protected readonly month = signal(monthKey(new Date()));
  protected readonly report = signal<MonthlyReport | null>(null);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);

  protected readonly tsh = tsh;
  protected readonly monthName = monthName;

  ngOnInit(): void {
    this.load();
  }

  protected move(by: number): void {
    this.month.set(shiftMonth(this.month(), by));
    this.load();
  }

  protected load(): void {
    this.loading.set(true);
    this.error.set(null);
    this.api.monthlyReport(this.month()).subscribe({
      next: (r) => {
        this.report.set(r);
        this.loading.set(false);
      },
      error: (err) => {
        this.error.set(errorMessage(err));
        this.loading.set(false);
      },
    });
  }

  /** "+50%", "-30%", or "new" when there was nothing to compare with. */
  protected percent(c: Comparison): string {
    if (c.direction === 'same') return 'same';
    if (c.percent === null) return 'new';
    return `${c.percent > 0 ? '+' : '-'}${Math.abs(c.percent).toFixed(Math.abs(c.percent) >= 10 ? 0 : 1)}%`;
  }

  /** The width of a progress bar: 0 to 100. */
  protected bar(percent: number | null): number {
    return Math.max(0, Math.min(100, percent ?? 0));
  }

  protected headline(r: MonthlyReport): string {
    const prev = monthName(r.previous.month);
    const pct = r.overall.percent === null ? '' : ` ${Math.abs(r.overall.percent).toFixed(Math.abs(r.overall.percent) >= 10 ? 0 : 1)}%`;
    if (r.overall.direction === 'up') return `Better than ${prev}${pct}`;
    if (r.overall.direction === 'down') return `Below ${prev}${pct}`;
    return `The same as ${prev}`;
  }
}
