import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { AuthService } from '../../core/auth.service';
import { CreditApi } from '../../core/credit-api.service';
import { AgeingListing, CreditCustomer, CreditSettingsBody, CreditState, Statement, StatementSale, creditState } from '../../core/credit.models';
import { dayLabel, dayOf, eatDay, offline, parseAmount, serverMessage, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { MotionService } from '../../core/services/motion.service';
import { ToastService } from '../../core/services/toast.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { TablePaginationComponent } from '../../shared/components/table-pagination/table-pagination';
import { TableToolbarComponent } from '../../shared/components/table-toolbar/table-toolbar';
import { BsDateDirective } from '../../shared/ui/bs-date.directive';
import { MoneyDirective } from '../../shared/ui/money.directive';

type Tab = 'customers' | 'ageing';
type Method = 'cash' | 'mobile_money' | 'bank_transfer' | 'cheque';

/** One unpaid sale in the "receive payment" window: ticked, and how much of it is being paid now (text while typed). */
interface Allocation {
  sale: StatementSale;
  owing: number;
  picked: boolean;
  amount: string;
}

const METHODS: Method[] = ['cash', 'mobile_money', 'bank_transfer', 'cheque'];

/**
 * Customers who buy on credit, as in the mobile app's "Customers & credit": who owes what and how close they are to their limit,
 * their account statement, their credit settings (limit, days to pay, blocked), receiving a payment against chosen sales, and the
 * debtors by age. Anyone who may see credit reads it; receiving money needs the cash right, as on the server.
 */
@Component({
  selector: 'app-credit',
  imports: [FormsModule, RouterLink, ModalDialogComponent, TableToolbarComponent, TablePaginationComponent, BsDateDirective, MoneyDirective],
  templateUrl: './credit.html',
})
export class CreditPage implements OnInit {
  private readonly api = inject(CreditApi);
  private readonly toast = inject(ToastService);
  protected readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);
  protected readonly motion = inject(MotionService);

  protected readonly tsh = tsh;
  protected readonly dayLabel = dayLabel;
  protected readonly eatDay = eatDay;
  protected readonly methods = METHODS;

  protected readonly canReceive = computed(() => this.auth.can('inv_view_cash'));

  protected readonly tab = signal<Tab>('customers');
  protected readonly customers = signal<CreditCustomer[]>([]);
  protected readonly ageing = signal<AgeingListing | null>(null);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly query = signal('');
  protected readonly only = signal<'all' | 'owing' | 'limit'>('all');
  protected readonly page = signal(1);
  protected readonly pageSize = signal(10);

  protected readonly rows = computed(() => {
    const q = this.query().toLowerCase().trim();
    const only = this.only();

    return this.customers().filter((c) => {
      if (q && !`${c.name} ${c.phone}`.toLowerCase().includes(q)) return false;
      if (only === 'owing') return c.balance > 0;
      if (only === 'limit') return ['over', 'near', 'blocked'].includes(creditState(c));

      return true;
    });
  });
  protected readonly pageRows = computed(() => {
    const size = this.pageSize();
    const start = (this.page() - 1) * size;

    return this.rows().slice(start, start + size);
  });
  protected readonly noun = computed(() => this.i18n.t(this.rows().length === 1 ? 'cr.noun.one' : 'cr.noun.many'));
  protected readonly totalOwed = computed(() => this.customers().reduce((sum, c) => sum + c.balance, 0));
  protected readonly owingCount = computed(() => this.customers().filter((c) => c.balance > 0).length);
  protected readonly watchCount = computed(() => this.customers().filter((c) => ['over', 'blocked'].includes(creditState(c))).length);

  // ---- the statement window
  protected readonly statementFor = signal<CreditCustomer | null>(null);
  protected readonly statement = signal<Statement | null>(null);
  protected readonly statementLoading = signal(false);
  protected readonly statementError = signal('');
  protected from = dayOf(new Date(new Date().getFullYear(), new Date().getMonth(), 1));
  protected to = dayOf(new Date());

  // ---- the credit settings window
  protected readonly settingsFor = signal<CreditCustomer | null>(null);
  protected limitText = '';
  protected termsText = '';
  protected blocked = false;
  protected blockReason = '';
  protected readonly settingsError = signal('');
  protected readonly settingsSaving = signal(false);

  // ---- the receive-payment window
  protected readonly payFor = signal<CreditCustomer | null>(null);
  protected readonly allocations = signal<Allocation[]>([]);
  protected readonly payLoading = signal(false);
  protected method: Method = 'cash';
  protected reference = '';
  protected readonly payError = signal('');
  protected readonly paySaving = signal(false);
  protected readonly payTotal = computed(() => this.allocations().filter((a) => a.picked).reduce((sum, a) => sum + (parseAmount(a.amount) || 0), 0));

  ngOnInit(): void {
    void this.load();
  }

  protected state(c: CreditCustomer): CreditState {
    return creditState(c);
  }

  /** How much of the limit is used, 0 to 100, for the little bar. */
  protected used(c: CreditCustomer): number {
    return c.credit_limit > 0 ? Math.min(100, Math.round((c.balance / c.credit_limit) * 100)) : 0;
  }

  protected setQuery(q: string): void {
    this.query.set(q);
    this.page.set(1);
  }

  protected setOnly(v: 'all' | 'owing' | 'limit'): void {
    this.only.set(v);
    this.page.set(1);
  }

  // ------------------------------------------------------------------ loading
  protected async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      const [customers, ageing] = await Promise.all([firstValueFrom(this.api.customers()), firstValueFrom(this.api.ageing())]);
      this.customers.set(customers);
      this.ageing.set(ageing);
    } catch (err) {
      this.error.set(this.messageOf(err));
    } finally {
      this.loading.set(false);
    }
  }

  // ------------------------------------------------------------------ statement
  protected async openStatement(c: CreditCustomer): Promise<void> {
    this.statementFor.set(c);
    this.statement.set(null);
    await this.loadStatement();
  }

  protected async loadStatement(): Promise<void> {
    const c = this.statementFor();
    if (!c) return;
    this.statementLoading.set(true);
    this.statementError.set('');
    try {
      this.statement.set(await firstValueFrom(this.api.statement(c.id, this.from, this.to)));
    } catch (err) {
      this.statementError.set(this.messageOf(err));
    } finally {
      this.statementLoading.set(false);
    }
  }

  // ------------------------------------------------------------------ credit settings
  protected openSettings(c: CreditCustomer): void {
    this.settingsFor.set(c);
    this.limitText = c.credit_limit ? String(c.credit_limit) : '';
    this.termsText = String(c.payment_terms_days);
    this.blocked = c.is_blocked;
    this.blockReason = c.block_reason ?? '';
    this.settingsError.set('');
  }

  protected async saveSettings(): Promise<void> {
    const c = this.settingsFor();
    if (!c) return;
    const limit = this.limitText.trim() === '' ? 0 : parseAmount(this.limitText);
    const terms = this.termsText.trim() === '' ? 0 : /^\d+$/.test(this.termsText.trim()) ? Number(this.termsText.trim()) : NaN;
    if (Number.isNaN(limit)) return this.settingsError.set(this.i18n.t('cr.err.limit'));
    if (Number.isNaN(terms) || terms > 365) return this.settingsError.set(this.i18n.t('cr.err.terms'));

    const body: CreditSettingsBody = { credit_limit: limit, payment_terms_days: terms, is_blocked: this.blocked, block_reason: this.blocked ? this.blockReason.trim() || null : null };
    this.settingsSaving.set(true);
    this.settingsError.set('');
    try {
      await firstValueFrom(this.api.saveSettings(c.id, body));
      this.toast.success(this.i18n.t('cr.settings.saved'), this.i18n.t('common.done'));
      this.settingsFor.set(null);
      await this.load();
    } catch (err) {
      this.settingsError.set(this.messageOf(err));
    } finally {
      this.settingsSaving.set(false);
    }
  }

  // ------------------------------------------------------------------ receiving a payment
  /** The sales this customer has not finished paying, all time (the server lists them in a statement). */
  protected async openPay(c: CreditCustomer): Promise<void> {
    this.payFor.set(c);
    this.allocations.set([]);
    this.method = 'cash';
    this.reference = '';
    this.payError.set('');
    this.payLoading.set(true);
    try {
      const s = await firstValueFrom(this.api.statement(c.id, '2000-01-01', dayOf(new Date())));
      this.allocations.set(
        s.sales
          .filter((x) => x.payment_status === 'debt' || x.payment_status === 'partial')
          .map((x) => ({ sale: x, owing: Math.max(0, x.total - x.paid_total), picked: false, amount: '' }))
          .filter((a) => a.owing > 0),
      );
    } catch (err) {
      this.payError.set(this.messageOf(err));
    } finally {
      this.payLoading.set(false);
    }
  }

  /** Ticking a sale fills in everything it still owes; unticking clears it. */
  protected pick(i: number, picked: boolean): void {
    this.allocations.update((all) => all.map((a, k) => (k === i ? { ...a, picked, amount: picked ? String(a.owing) : '' } : a)));
  }

  protected setAmount(i: number, amount: string): void {
    this.allocations.update((all) => all.map((a, k) => (k === i ? { ...a, amount } : a)));
  }

  protected async savePayment(): Promise<void> {
    const c = this.payFor();
    if (!c) return;
    const chosen = this.allocations().filter((a) => a.picked);
    if (!chosen.length) return this.payError.set(this.i18n.t('cr.err.pick'));
    const allocations: { sale_id: number; amount: number }[] = [];
    for (const a of chosen) {
      const amount = parseAmount(a.amount);
      if (Number.isNaN(amount) || amount <= 0) return this.payError.set(this.i18n.t('cr.err.amount'));
      if (amount > a.owing) return this.payError.set(this.i18n.t('cr.err.toomuch', a.sale.number, tsh(a.owing)));
      allocations.push({ sale_id: a.sale.id, amount });
    }

    this.paySaving.set(true);
    this.payError.set('');
    try {
      await firstValueFrom(
        this.api.receivePayment({ customer_id: c.id, amount: allocations.reduce((s, a) => s + a.amount, 0), method: this.method, ...(this.reference.trim() ? { reference: this.reference.trim() } : {}), allocations }),
      );
      this.toast.success(this.i18n.t('cr.paid', tsh(allocations.reduce((s, a) => s + a.amount, 0)), c.name), this.i18n.t('common.done'));
      this.payFor.set(null);
      await this.load();
    } catch (err) {
      this.payError.set(this.messageOf(err));
    } finally {
      this.paySaving.set(false);
    }
  }

  private messageOf(err: unknown): string {
    return offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic'));
  }
}
