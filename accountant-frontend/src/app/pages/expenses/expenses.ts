import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { AccountantApi } from '../../core/accountant-api.service';
import { AuthService } from '../../core/auth.service';
import { dayLabel, dayOf, offline, parseAmount, serverMessage, today, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { Expense, ExpenseSummary } from '../../core/models';
import { PAYMENT_CHANNELS } from '../../core/till.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { MotionService } from '../../core/services/motion.service';
import { ToastService } from '../../core/services/toast.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { TablePaginationComponent } from '../../shared/components/table-pagination/table-pagination';
import { TableToolbarComponent } from '../../shared/components/table-toolbar/table-toolbar';
import { BsDateDirective } from '../../shared/ui/bs-date.directive';
import { BsSelectDirective } from '../../shared/ui/bs-select.directive';
import { CountUpDirective } from '../../shared/ui/count-up.directive';

type Period = 'today' | 'week' | 'month' | 'year';

/** The categories the server knows, in the order people look for them; personal ones are always personal. */
const PERSONAL_CATEGORIES = ['drawings', 'family'];

/**
 * What the business spent, and what the owner took out for themselves (kept apart, never taken off the profit). Pick a period, see
 * the totals and the list, and write down a new expense with a few clear fields.
 */
@Component({
  selector: 'app-expenses',
  imports: [FormsModule, ModalDialogComponent, TableToolbarComponent, TablePaginationComponent, BsDateDirective, BsSelectDirective, CountUpDirective],
  templateUrl: './expenses.html',
})
export class ExpensesPage implements OnInit {
  private readonly api = inject(AccountantApi);
  private readonly toast = inject(ToastService);
  private readonly confirm = inject(ConfirmService);
  protected readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);
  protected readonly motion = inject(MotionService);

  protected readonly period = signal<Period>('month');
  protected readonly periods: Period[] = ['today', 'week', 'month', 'year'];
  protected readonly rowsAll = signal<Expense[]>([]);
  protected readonly summary = signal<ExpenseSummary | null>(null);
  protected readonly categories = signal<string[]>(['rent', 'salaries', 'transport', 'utilities', 'supplies', 'maintenance', 'marketing', 'licences', 'loan_repayment', 'drawings', 'family', 'other']);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);

  protected readonly query = signal('');
  protected readonly page = signal(1);
  protected readonly pageSize = signal(10);

  protected readonly tsh = tsh;
  protected readonly dayLabel = dayLabel;
  protected readonly today = today;

  protected readonly canAdd = computed(() => this.auth.can('inv_manage_expenses'));
  /** The owner, a manager or the accountant decide what others recorded (the server checks this too). */
  protected readonly canDecide = computed(() => this.auth.canAny('inv_manage_settings', 'inv_manage_sales') || this.auth.can('__all__'));
  protected readonly channels = PAYMENT_CHANNELS;

  protected readonly rows = computed(() => {
    const q = this.query().toLowerCase().trim();
    const all = this.rowsAll();
    return q ? all.filter((e) => `${e.description} ${this.categoryName(e.category)} ${e.created_by_name ?? ''}`.toLowerCase().includes(q)) : all;
  });
  protected readonly pageRows = computed(() => {
    const size = this.pageSize();
    const start = (this.page() - 1) * size;
    return this.rows().slice(start, start + size);
  });
  protected readonly noun = computed(() => this.i18n.t(this.rows().length === 1 ? 'exp.noun.one' : 'exp.noun.many'));

  // the "record an expense" window
  protected readonly addOpen = signal(false);
  protected category = 'other';
  protected description = '';
  protected amountText = '';
  protected date = today();
  protected personal = false;
  protected supplier = '';
  protected method = 'cash';
  /** The expense being changed; null when a new one is written. */
  protected readonly editing = signal<Expense | null>(null);
  protected receiptFile: File | null = null;
  protected readonly addError = signal('');
  protected readonly saving = signal(false);

  ngOnInit(): void {
    void this.loadCategories();
    void this.load();
  }

  /** The dates the period covers, on this computer's calendar. */
  private range(p: Period): [string, string] {
    const now = new Date();
    const to = dayOf(now);
    if (p === 'today') return [to, to];
    if (p === 'week') {
      const monday = new Date(now);
      monday.setDate(now.getDate() - ((now.getDay() + 6) % 7));
      return [dayOf(monday), to];
    }
    if (p === 'month') return [dayOf(new Date(now.getFullYear(), now.getMonth(), 1)), to];
    return [dayOf(new Date(now.getFullYear(), 0, 1)), to];
  }

  protected setPeriod(p: Period): void {
    this.period.set(p);
    this.page.set(1);
    void this.load();
  }

  protected async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    const [from, to] = this.range(this.period());
    try {
      const [rows, summary] = await Promise.all([firstValueFrom(this.api.expenses(from, to)), firstValueFrom(this.api.expenseSummary(from, to))]);
      this.rowsAll.set(rows);
      this.summary.set(summary);
      this.motion.tick.update((n) => n + 1);
    } catch (err) {
      this.error.set(offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic')));
    } finally {
      this.loading.set(false);
    }
  }

  private async loadCategories(): Promise<void> {
    try {
      const list = await firstValueFrom(this.api.expenseCategories());
      if (list.length) this.categories.set(list);
    } catch {
      // the usual list is already there
    }
  }

  protected categoryName(c: string): string {
    const key = `cat.${c}`;
    const label = this.i18n.t(key);
    return label === key ? c : label;
  }

  protected isPersonal(e: Expense): boolean {
    return e.is_personal === true || e.is_personal === 1;
  }

  protected barWidth(part: number, whole: number): number {
    return whole <= 0 ? 0 : Math.max(2, Math.min(100, (part / whole) * 100));
  }

  protected setQuery(q: string): void {
    this.query.set(q);
    this.page.set(1);
  }

  // ------------------------------------------------------------------ record an expense
  protected openAdd(): void {
    this.editing.set(null);
    this.supplier = '';
    this.method = 'cash';
    this.receiptFile = null;
    this.category = 'other';
    this.description = '';
    this.amountText = '';
    this.date = today();
    this.personal = false;
    this.addError.set('');
    this.addOpen.set(true);
  }

  protected openEdit(e: Expense): void {
    this.editing.set(e);
    this.category = e.category;
    this.description = e.description;
    this.amountText = String(e.amount);
    this.date = e.expense_date.slice(0, 10);
    this.personal = this.isPersonal(e);
    this.supplier = e.supplier ?? '';
    this.method = e.payment_method ?? 'cash';
    this.receiptFile = null;
    this.addError.set('');
    this.addOpen.set(true);
  }

  protected pickReceipt(ev: Event): void {
    this.receiptFile = (ev.target as HTMLInputElement).files?.[0] ?? null;
  }

  protected async decide(e: Expense, decision: 'approve' | 'reject'): Promise<void> {
    try {
      await firstValueFrom(this.api.decideExpense(e.id, decision));
      const said = decision === 'approve' ? 'exp.approved' : 'exp.rejected';
      this.toast.success(this.i18n.t(said), this.i18n.t('common.done'));
      await this.load();
    } catch (err) {
      this.toast.error(offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic')), this.i18n.t('error.title'));
    }
  }

  protected forcedPersonal(): boolean {
    return PERSONAL_CATEGORIES.includes(this.category);
  }

  protected async saveExpense(): Promise<void> {
    const t = (k: string) => this.i18n.t(k);
    const amount = parseAmount(this.amountText);
    if (!this.description.trim()) return this.addError.set(t('exp.err.desc'));
    if (Number.isNaN(amount) || amount <= 0) return this.addError.set(t('exp.err.amount'));
    if (!this.date) return this.addError.set(t('exp.err.date'));

    this.saving.set(true);
    this.addError.set('');
    try {
      const body = {
        category: this.category,
        description: this.description.trim(),
        amount,
        expense_date: this.date,
        is_personal: this.personal || this.forcedPersonal(),
        supplier: this.supplier.trim() || null,
        payment_method: this.method,
      };
      const current = this.editing();
      const saved = await firstValueFrom(current ? this.api.updateExpense(current.id, body) : this.api.addExpense(body));
      if (this.receiptFile) {
        try {
          await firstValueFrom(this.api.attachReceipt(saved?.id ?? current!.id, this.receiptFile));
        } catch (err) {
          this.toast.warning(serverMessage(err) ?? this.i18n.t('exp.receipt.failed'), this.i18n.t('exp.receipt'));
        }
      }
      this.addOpen.set(false);
      this.toast.success(this.i18n.t('exp.saved', tsh(amount)), t('common.done'));
      await this.load();
    } catch (err) {
      this.addError.set(offline(err) ? t('error.offline') : (serverMessage(err) ?? t('error.generic')));
    } finally {
      this.saving.set(false);
    }
  }

  protected async remove(e: Expense): Promise<void> {
    const yes = await this.confirm.ask({
      title: this.i18n.t('exp.delete.title'),
      message: this.i18n.t('exp.delete.message', e.description, tsh(e.amount)),
      confirmLabel: this.i18n.t('common.delete'),
      cancelLabel: this.i18n.t('common.keep'),
      danger: true,
    });
    if (!yes) return;
    try {
      await firstValueFrom(this.api.deleteExpense(e.id));
      this.toast.success(this.i18n.t('exp.deleted'), this.i18n.t('common.done'));
      await this.load();
    } catch (err) {
      this.toast.error(offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic')), this.i18n.t('error.title'));
    }
  }
}
