import { Component, OnInit, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { BranchSales, BranchesService } from '../../core/branches.service';
import { dayOf, offline, serverMessage, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { MotionService } from '../../core/services/motion.service';

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
