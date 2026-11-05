import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { BranchSales, BranchesService } from '../../core/branches.service';
import { dayOf, offline, serverMessage, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { TableToolbarComponent } from '../../shared/components/table-toolbar/table-toolbar';
import { MotionService } from '../../core/services/motion.service';
import { SortState, nextSort, sortArrow, sorted } from '../../core/sort';

type Period = 'week' | 'month' | 'quarter' | 'year';
interface Row {
  id: string;
  name: string;
  sales: number;
  paid: number;
  sales_count: number;
  profit: number | null;
}
interface Group extends Row {
  children: Row[];
}

/**
 * What each branch sold and what each person sold, for a week, a month, three months or a year (Tanzania days). Profit appears only
 * when the server sends it: it is left out for people who may not see profit.
 */
@Component({
  selector: 'app-branch-sales',
  imports: [TableToolbarComponent],
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

  // One table that can be read two ways: by branch (each branch with the people who sold there) or by person (each person with the
  // branches they sold in). A header sorts the groups, and what is inside each group the same way. Profit is shown only when the server
  // sent it (people who may not see profit never get it).
  protected readonly group = signal<'branch' | 'staff'>('branch');
  protected readonly branchSort = signal<SortState | null>(null);
  protected readonly arrow = sortArrow;
  protected readonly hasProfit = computed(() => (this.data()?.by_branch ?? []).some((b) => b.profit !== null));

  private value(row: Row, key: string): string | number | null {
    return key === 'name' ? row.name : key === 'count' ? row.sales_count : key === 'paid' ? row.paid : key === 'profit' ? row.profit : row.sales;
  }

  /** The groups of the chosen reading, each with its own rows under it, all sorted by the chosen header. */
  protected readonly groups = computed<Group[]>(() => {
    const d = this.data();
    if (!d) return [];
    const none = this.i18n.t('bsl.nobranch');
    const cell = (c: { sales: number; paid: number; sales_count: number; profit: number | null }) => ({ sales: c.sales, paid: c.paid, sales_count: c.sales_count, profit: c.profit });
    const sort = this.branchSort();
    const rows: Group[] =
      this.group() === 'branch'
        ? d.by_branch.map((b) => ({ id: `b${b.branch_id ?? 0}`, name: b.name ?? none, ...cell(b), children: b.staff.map((s) => ({ id: s.staff_id, name: s.name, ...cell(s) })) }))
        : d.by_staff.map((p) => ({ id: p.staff_id, name: p.name, ...cell(p), children: p.branches.map((b) => ({ id: `b${b.branch_id ?? 0}`, name: b.name ?? none, ...cell(b) })) }));

    return sorted(rows, sort, (r, k) => this.value(r, k)).map((r) => ({ ...r, children: sorted(r.children, sort, (c, k) => this.value(c, k)) }));
  });

  protected setGroup(g: 'branch' | 'staff'): void {
    this.group.set(g);
  }

  protected sortBranches(key: string): void {
    this.branchSort.update((c) => nextSort(c, key));
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
