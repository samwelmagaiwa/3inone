import { Component, OnDestroy, OnInit, TemplateRef, ViewChild, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { CreditApi } from '../../core/credit-api.service';
import { CustomerReport } from '../../core/credit.models';
import { dayLabel, dayOf, eatDay, monthName, offline, serverMessage, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { HeaderSlotService } from '../../core/services/header-slot.service';
import { MotionService } from '../../core/services/motion.service';
import { BsDateDirective } from '../../shared/ui/bs-date.directive';

type Period = 'week' | 'month' | 'quarter' | 'year' | 'custom';
type Group = 'day' | 'week' | 'month';
type View = 'period' | 'products' | 'recent' | 'history';

/**
 * One customer's story for any period, as in the mobile app: what they bought, paid, the profit they brought (shown only to people
 * who may see profit: the server leaves it out for everyone else), what they buy most, how it moved day by day, week by week or month
 * by month, and what they owe now.
 */
@Component({
  selector: 'app-customer-report',
  imports: [FormsModule, RouterLink, BsDateDirective],
  templateUrl: './customer-report.html',
})
export class CustomerReportPage implements OnInit, OnDestroy {
  private readonly api = inject(CreditApi);
  private readonly route = inject(ActivatedRoute);
  protected readonly i18n = inject(I18nService);
  protected readonly motion = inject(MotionService);
  private readonly slot = inject(HeaderSlotService);
  @ViewChild('periodBar', { static: true }) private periodBar!: TemplateRef<unknown>;

  protected readonly tsh = tsh;
  protected readonly eatDay = eatDay;
  protected readonly periods: Period[] = ['week', 'month', 'quarter', 'year', 'custom'];
  protected readonly groups: Group[] = ['day', 'week', 'month'];

  private readonly id = Number(this.route.snapshot.paramMap.get('id'));
  protected readonly period = signal<Period>('month');
  protected readonly group = signal<Group>('week');
  protected from = '';
  protected to = '';
  protected readonly report = signal<CustomerReport | null>(null);
  /** What the one card shows ("Sort by"): over time, goods, recent purchases or the whole history. Only the ones that have something. */
  protected readonly view = signal<View>('period');
  protected readonly groupOpen = signal(false);
  protected readonly views = computed<View[]>(() => {
    const r = this.report();
    const out: View[] = [];
    if (r?.by_period.length) out.push('period');
    if (r?.top_products.length) out.push('products');
    if (r?.recent_sales.length) out.push('recent');
    out.push('history');
    return out;
  });
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);

  protected readonly profit = computed(() => this.report()?.profit_visible === true);
  protected readonly maxSales = computed(() => Math.max(1, ...(this.report()?.by_period ?? []).map((p) => p.sales)));

  ngOnInit(): void {
    this.choose('month');
    queueMicrotask(() => this.slot.show(this.periodBar));
  }

  ngOnDestroy(): void {
    this.slot.clear(this.periodBar);
  }

  /** A preset period: its days, and the grouping that reads best for it (days for a week, weeks for a month, months for more). */
  protected choose(p: Period): void {
    const now = new Date();
    const today = dayOf(now);
    this.period.set(p);
    if (p !== 'custom') {
      this.to = today;
      this.from =
        p === 'week' ? dayOf(new Date(now.getFullYear(), now.getMonth(), now.getDate() - ((now.getDay() + 6) % 7)))
        : p === 'month' ? dayOf(new Date(now.getFullYear(), now.getMonth(), 1))
        : p === 'quarter' ? dayOf(new Date(now.getFullYear(), now.getMonth() - 2, 1))
        : dayOf(new Date(now.getFullYear(), 0, 1));
      this.group.set(p === 'week' ? 'day' : p === 'month' ? 'week' : 'month');
    } else if (!this.from) {
      this.from = dayOf(new Date(now.getFullYear(), now.getMonth(), 1));
      this.to = today;
    }
    void this.load();
  }

  /** The two days picked on the calendar: they become the period, grouped by what reads best for their length. */
  protected applyDates(): void {
    if (!this.from || !this.to || this.from > this.to) {
      this.error.set(this.i18n.t('crr.err.dates'));
      return;
    }
    const days = (new Date(this.to).getTime() - new Date(this.from).getTime()) / 86_400_000 + 1;
    this.period.set('custom');
    this.group.set(days <= 14 ? 'day' : days <= 92 ? 'week' : 'month');
    this.groupOpen.set(false);
    void this.load();
  }

  protected setGroup(g: Group): void {
    this.group.set(g);
    void this.load();
  }

  protected async load(): Promise<void> {
    if (!this.from || !this.to || this.from > this.to) {
      this.error.set(this.i18n.t('crr.err.dates'));
      return;
    }
    this.loading.set(true);
    this.error.set(null);
    try {
      this.report.set(await firstValueFrom(this.api.report(this.id, this.from, this.to, this.group())));
      if (!this.views().includes(this.view())) this.view.set(this.views()[0]);
    } catch (err) {
      this.error.set(offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic')));
    } finally {
      this.loading.set(false);
    }
  }

  /** The name of one row of "by period": a day, the Monday a week starts on, or a month. */
  protected periodName(key: string): string {
    const g = this.report()?.group ?? this.group();
    if (g === 'month') return monthName(key, this.i18n.locale());
    if (g === 'week') return this.i18n.t('crr.weekof', dayLabel(key));

    return dayLabel(key);
  }

  protected barWidth(sales: number): number {
    return Math.round((sales / this.maxSales()) * 100);
  }
}
