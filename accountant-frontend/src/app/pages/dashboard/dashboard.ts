import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { AccountantApi } from '../../core/accountant-api.service';
import { AuthService } from '../../core/auth.service';
import { dayLabel, monthKey, monthName, offline, parseAmount, serverMessage, shiftMonth, shortMoney, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { Advice, Comparison, MonthlyReport } from '../../core/models';
import { MotionService } from '../../core/services/motion.service';
import { ToastService } from '../../core/services/toast.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { CountUpDirective } from '../../shared/ui/count-up.directive';
import { MoneyDirective } from '../../shared/ui/money.directive';

/**
 * The month on one page, from the same report the mobile app shows: is it better or worse than last month, how close the profit
 * target is, the money figures, where the business stands (stock, debts, capital), spending, the products and customers behind
 * the numbers, and advice on where to do better.
 */
@Component({
  selector: 'app-dashboard',
  imports: [FormsModule, RouterLink, ModalDialogComponent, CountUpDirective, MoneyDirective],
  templateUrl: './dashboard.html',
})
export class DashboardPage implements OnInit {
  private readonly api = inject(AccountantApi);
  private readonly toast = inject(ToastService);
  protected readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);
  protected readonly motion = inject(MotionService);

  protected readonly month = signal(monthKey(new Date()));
  protected readonly report = signal<MonthlyReport | null>(null);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly lastUpdated = signal('');

  protected readonly advice = signal<Advice | null>(null);
  protected readonly adviceLoading = signal(false);
  protected readonly adviceError = signal<string | null>(null);

  // the profit target window
  protected readonly targetOpen = signal(false);
  protected targetText = '';
  protected readonly targetError = signal('');
  protected readonly targetSaving = signal(false);

  protected readonly Math = Math;
  protected readonly tsh = tsh;
  protected readonly shortMoney = shortMoney;
  protected readonly dayLabel = dayLabel;

  /** The latest month the page can show: the month after this one, so a target can be set before it begins. */
  private readonly lastMonth = shiftMonth(monthKey(new Date()), 1);
  protected readonly canNext = computed(() => this.month() < this.lastMonth);

  protected readonly canSetTarget = computed(() => this.auth.can('inv_manage_settings'));
  protected readonly monthTitle = computed(() => monthName(this.month(), this.i18n.locale()));

  protected readonly greeting = computed(() => {
    const h = new Date().getHours();
    return this.i18n.t(h < 12 ? 'greet.morning' : h < 17 ? 'greet.afternoon' : 'greet.evening');
  });

  ngOnInit(): void {
    void this.load();
  }

  protected move(by: number): void {
    this.month.set(shiftMonth(this.month(), by));
    void this.load();
  }

  protected async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    this.advice.set(null);
    try {
      const r = await firstValueFrom(this.api.monthlyReport(this.month()));
      this.report.set(r);
      this.lastUpdated.set(new Date().toLocaleTimeString(this.i18n.locale(), { hour: '2-digit', minute: '2-digit' }));
      this.motion.tick.update((n) => n + 1);
      this.loading.set(false);
      if (!r.is_future) void this.loadAdvice(false);
    } catch (err) {
      this.error.set(offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic')));
      this.loading.set(false);
    }
  }

  protected async loadAdvice(refresh: boolean): Promise<void> {
    this.adviceLoading.set(true);
    this.adviceError.set(null);
    try {
      this.advice.set(await firstValueFrom(this.api.advice(this.month(), this.i18n.lang(), refresh)));
    } catch (err) {
      this.adviceError.set(offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic')));
    } finally {
      this.adviceLoading.set(false);
    }
  }

  // ------------------------------------------------------------------ words built from numbers
  protected percent(c: Comparison): string {
    if (c.direction === 'same') return this.i18n.t('trend.same');
    if (c.percent === null) return this.i18n.t('trend.new');
    return `${c.percent > 0 ? '+' : '-'}${Math.abs(c.percent).toFixed(Math.abs(c.percent) >= 10 ? 0 : 1)}%`;
  }

  protected headline(r: MonthlyReport): string {
    const prev = monthName(r.previous.month, this.i18n.locale());
    const p = r.overall.percent;
    const pct = p === null ? '' : ` ${Math.abs(p).toFixed(Math.abs(p) >= 10 ? 0 : 1)}%`;
    const key = r.overall.direction === 'up' ? 'headline.up' : r.overall.direction === 'down' ? 'headline.down' : 'headline.same';
    return this.i18n.t(key, prev, pct);
  }

  protected categoryName(c: string): string {
    const key = `cat.${c}`;
    const label = this.i18n.t(key);
    return label === key ? c : label;
  }

  protected barWidth(part: number, whole: number): number {
    return whole <= 0 ? 0 : Math.max(2, Math.min(100, (part / whole) * 100));
  }

  protected targetBar(r: MonthlyReport): number {
    return Math.max(0, Math.min(100, r.target?.progress_percent ?? 0));
  }

  protected targetMarker(r: MonthlyReport): number {
    const t = r.target;
    return t && t.profit_target > 0 ? Math.max(0, Math.min(100, (t.expected_by_today / t.profit_target) * 100)) : 0;
  }

  protected targetSentence(r: MonthlyReport): string {
    const t = r.target!;
    if (t.status === 'reached') return this.i18n.t('target.reached.line', tsh(t.over_by));
    if (t.status === 'missed') return this.i18n.t('target.missed.line', tsh(t.left));
    const parts = [this.i18n.t('target.togo', tsh(t.left))];
    if (t.days_left > 0) parts.push(this.i18n.t('target.days', t.days_left));
    if (r.is_current) parts.push(this.i18n.t('target.pace', tsh(t.expected_by_today)));
    return parts.join('  ·  ');
  }

  protected kpis = computed(() => {
    const r = this.report();
    if (!r) return [];
    const c = r.compare;
    return [
      { label: this.i18n.t('kpi.sales'), value: tsh(c.sales.now), cmp: c.sales, tone: 'primary', icon: 'M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-8 2a2 2 0 11-4 0 2 2 0 014 0z', hint: this.i18n.t('kpi.sales.hint', r.figures.sales_count) },
      { label: this.i18n.t('kpi.gross'), value: tsh(c.gross_profit.now), cmp: c.gross_profit, tone: 'success', icon: 'M13 7h8m0 0v8m0-8l-8 8-4-4-6 6', hint: r.figures.margin_percent === null ? this.i18n.t('kpi.gross.hint') : this.i18n.t('kpi.margin', r.figures.margin_percent) },
      { label: this.i18n.t('kpi.expenses'), value: tsh(c.expenses.now), cmp: c.expenses, tone: 'warning', icon: 'M9 14l6-6m-5.5.5h.01m4.99 5h.01M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16l3.5-2 3.5 2 3.5-2 3.5 2z', hint: this.i18n.t('kpi.expenses.hint') },
      { label: this.i18n.t('kpi.net'), value: tsh(c.net_profit.now), cmp: c.net_profit, tone: c.net_profit.now < 0 ? 'danger' : 'purple', icon: 'M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z', hint: this.i18n.t('kpi.net.hint') },
    ];
  });

  protected adviceIcon(level: string): string {
    return level === 'warning'
      ? 'M12 9v2m0 4h.01M5.07 19h13.86c1.54 0 2.5-1.67 1.73-3L13.73 4c-.77-1.33-2.69-1.33-3.46 0L3.34 16c-.77 1.33.19 3 1.73 3z'
      : level === 'good'
        ? 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z'
        : 'M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z';
  }

  // ------------------------------------------------------------------ the profit target
  protected openTarget(): void {
    const t = this.report()?.target;
    this.targetText = t ? String(Math.round(t.profit_target)) : '';
    this.targetError.set('');
    this.targetOpen.set(true);
  }

  protected async saveTarget(): Promise<void> {
    const value = this.targetText.trim() === '' ? 0 : parseAmount(this.targetText);
    if (Number.isNaN(value)) {
      this.targetError.set(this.i18n.t('target.invalid'));
      return;
    }
    this.targetSaving.set(true);
    this.targetError.set('');
    try {
      await firstValueFrom(this.api.setTarget(this.month(), value));
      this.targetOpen.set(false);
      this.toast.success(this.i18n.t(value > 0 ? 'target.saved' : 'target.cleared'), this.i18n.t('common.done'));
      await this.load();
    } catch (err) {
      this.targetError.set(offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic')));
    } finally {
      this.targetSaving.set(false);
    }
  }
}
