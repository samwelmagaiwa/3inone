import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { BranchSales, BranchesService } from '../../core/branches.service';
import { dayOf, offline, serverMessage, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { MotionService } from '../../core/services/motion.service';
import { SortState, nextSort, sortArrow, sorted } from '../../core/sort';

type Period = 'week' | 'month' | 'quarter' | 'year';

/**
 * What each branch sold and what each person sold, for a week, a month, three months or a year (Tanzania days). Profit appears only
 * when the server sends it: it is left out for people who may not see profit.
 */
@Component({
  selector: 'app-branch-sales',
  templateUrl: './branch-sales.html',
})
export class BranchSalesPage implements OnInit {
  private readonly api = inject(BranchesService);
  protected readonly i18n = inject(I18nService);
  protected readonly motion = inject(MotionService);

  protected readonly tsh = tsh;
  protected readonly periods: Period[] = ['week', 'month', 'quarter', 'year'];
  protected readonly period = signal<Period>('month');
  protected readonly data = signal<BranchSales | null>(null);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);

  // Each table sorts by the header that was clicked; profit is shown only when the server sent it (people who may not see profit never get it).
  protected readonly branchSort = signal<SortState | null>(null);
  protected readonly staffSort = signal<SortState | null>(null);
  protected readonly arrow = sortArrow;
  protected readonly hasProfit = computed(() => (this.data()?.by_branch ?? []).some((b) => b.profit !== null) || (this.data()?.by_staff ?? []).some((s) => s.profit !== null));
  protected readonly branches = computed(() =>
    sorted(this.data()?.by_branch ?? [], this.branchSort(), (b, k) => (k === 'name' ? (b.name ?? this.i18n.t('bsl.nobranch')) : k === 'count' ? b.sales_count : k === 'paid' ? b.paid : k === 'profit' ? b.profit : b.sales)),
  );
  protected readonly people = computed(() =>
    sorted(this.data()?.by_staff ?? [], this.staffSort(), (s, k) => (k === 'name' ? s.name : k === 'count' ? s.sales_count : k === 'paid' ? s.paid : k === 'profit' ? s.profit : s.sales)),
  );

  protected sortBranches(key: string): void {
    this.branchSort.update((c) => nextSort(c, key));
  }

  protected sortPeople(key: string): void {
    this.staffSort.update((c) => nextSort(c, key));
  }

  ngOnInit(): void {
    void this.choose('month');
  }

  protected async choose(p: Period): Promise<void> {
    const now = new Date();
    this.period.set(p);
    const from =
      p === 'week' ? new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() + 6) % 7))
      : p === 'month' ? new Date(now.getFullYear(), now.getMonth(), 1)
      : p === 'quarter' ? new Date(now.getFullYear(), now.getMonth() - 2, 1)
      : new Date(now.getFullYear(), 0, 1);
    this.loading.set(true);
    this.error.set(null);
    try {
      this.data.set(await firstValueFrom(this.api.branchSales(dayOf(from), dayOf(now))));
    } catch (err) {
      this.error.set(offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic')));
    } finally {
      this.loading.set(false);
    }
  }

  protected retry(): void {
    void this.choose(this.period());
  }
}
