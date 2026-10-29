import { Component, OnDestroy, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { firstValueFrom } from 'rxjs';

import { AccountantApi } from '../../core/accountant-api.service';
import { AuthService } from '../../core/auth.service';
import { CapabilitiesService } from '../../core/capabilities.service';
import { dayOf, eatDateTime, offline, parseAmount, serverMessage, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { SaleRow } from '../../core/models';
import { printReceipt } from '../../core/receipt';
import { MotionService } from '../../core/services/motion.service';
import { ToastService } from '../../core/services/toast.service';
import { PAYMENT_CHANNELS } from '../../core/till.service';
import { SaleDetail, SaleReturn, TillApi } from '../../core/till-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { TablePaginationComponent } from '../../shared/components/table-pagination/table-pagination';
import { TableToolbarComponent } from '../../shared/components/table-toolbar/table-toolbar';
import { CountUpDirective } from '../../shared/ui/count-up.directive';
import { MoneyDirective } from '../../shared/ui/money.directive';

type Period = 'today' | 'week' | 'month' | 'year';
type Status = '' | 'paid' | 'partial' | 'debt';

/**
 * The sales that were made, for a period: how many, how much was billed, how much came in and how much is still owed, then each sale
 * with what was in it and how it was paid. Reading only: sales are rung up at the till (the mobile app).
 */
@Component({
  selector: 'app-sales',
  imports: [FormsModule, RouterLink, ModalDialogComponent, TableToolbarComponent, TablePaginationComponent, CountUpDirective, MoneyDirective],
  templateUrl: './sales.html',
})
export class SalesPage implements OnInit, OnDestroy {
  private readonly api = inject(AccountantApi);
  private readonly till = inject(TillApi);
  private readonly toast = inject(ToastService);
  protected readonly auth = inject(AuthService);
  private readonly caps = inject(CapabilitiesService);
  protected readonly i18n = inject(I18nService);
  protected readonly motion = inject(MotionService);

  protected readonly period = signal<Period>('today');
  protected readonly periods: Period[] = ['today', 'week', 'month', 'year'];
  protected readonly status = signal<Status>('');
  protected readonly statuses: Status[] = ['', 'paid', 'partial', 'debt'];
  protected readonly query = signal('');

  protected readonly rows = signal<SaleRow[]>([]);
  protected readonly total = signal(0); // sales matching, across all pages
  protected readonly page = signal(1);
  protected readonly perPage = 20;
  protected readonly summary = signal<{ count: number; total: number; paid: number; debt: number } | null>(null);
  protected readonly open = signal<number | null>(null);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);

  protected readonly tsh = tsh;
  protected readonly channels = PAYMENT_CHANNELS;
  protected readonly canSell = computed(() => this.auth.can('inv_create_sales'));
  protected readonly canManage = computed(() => this.auth.can('inv_manage_sales'));

  // ---- what can be done to a sale
  protected readonly payFor = signal<SaleRow | null>(null);
  protected payText = '';
  protected payMethod = 'cash';
  protected payReference = '';
  protected readonly cancelFor = signal<SaleRow | null>(null);
  protected cancelReason = '';
  protected readonly returnFor = signal<SaleDetail | null>(null);
  protected readonly returnQty = signal<Record<number, number>>({});
  protected returnReason = '';
  protected returnRestock = true;
  protected readonly busy = signal(false);
  protected readonly actionError = signal('');
  protected readonly returns = signal<SaleReturn[]>([]);
  private timer: ReturnType<typeof setTimeout> | null = null;

  ngOnInit(): void {
    void this.load();
    void this.loadReturns();
  }

  ngOnDestroy(): void {
    if (this.timer) clearTimeout(this.timer);
  }

  private range(p: Period): { from: string; to: string } {
    const now = new Date();
    const to = dayOf(now);
    if (p === 'today') return { from: to, to };
    if (p === 'week') {
      const monday = new Date(now);
      monday.setDate(now.getDate() - ((now.getDay() + 6) % 7));
      return { from: dayOf(monday), to };
    }
    if (p === 'month') return { from: dayOf(new Date(now.getFullYear(), now.getMonth(), 1)), to };
    return { from: dayOf(new Date(now.getFullYear(), 0, 1)), to };
  }

  protected setPeriod(p: Period): void {
    this.period.set(p);
    this.page.set(1);
    void this.load();
  }

  protected setStatus(s: Status): void {
    this.status.set(s);
    this.page.set(1);
    void this.load();
  }

  /** Searching waits for a pause in typing, so it does not ask the server on every letter. */
  protected setQuery(q: string): void {
    this.query.set(q);
    this.page.set(1);
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => void this.load(), 350);
  }

  protected goTo(page: number): void {
    this.page.set(page);
    void this.load();
  }

  protected async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    this.open.set(null);
    const filters = { ...this.range(this.period()), status: this.status(), q: this.query().trim() };
    try {
      const [list, summary] = await Promise.all([firstValueFrom(this.api.sales({ ...filters, page: this.page() })), firstValueFrom(this.api.salesSummary(filters))]);
      this.rows.set(list.data);
      this.total.set(list.meta?.total ?? list.data.length);
      this.summary.set(summary);
      this.motion.tick.update((n) => n + 1);
    } catch (err) {
      this.error.set(offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic')));
    } finally {
      this.loading.set(false);
    }
  }

  protected toggle(id: number): void {
    this.open.update((o) => (o === id ? null : id));
  }

  /** When a sale was made, as the clock in Tanzania showed it. */
  protected whenText(iso: string): string {
    return eatDateTime(iso);
  }

  protected itemsText(s: SaleRow): string {
    const items = s.items ?? [];
    if (!items.length) return '';
    const first = items.slice(0, 2).map((i) => `${i.product_name} ×${i.qty ?? 1}`).join(', ');
    return items.length > 2 ? `${first} +${items.length - 2}` : first;
  }

  protected noun(): string {
    return this.i18n.t(this.total() === 1 ? 'sales.noun.one' : 'sales.noun.many');
  }

  protected cancelled(s: SaleRow): boolean {
    return !!s.cancelled_at;
  }

  protected paymentMethod(m: string | null): string {
    const key = `pay.${m ?? 'cash'}`;
    const label = this.i18n.t(key);
    return label === key ? (m ?? '') : label;
  }

  // ------------------------------------------------------------------ actions on a sale
  private fail(err: unknown): string {
    return offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic'));
  }

  protected owing(s: SaleRow): number {
    return this.cancelled(s) ? 0 : Math.max(0, s.total - s.paid_total);
  }

  protected openPay(s: SaleRow): void {
    this.payText = String(this.owing(s));
    this.payMethod = 'cash';
    this.payReference = '';
    this.actionError.set('');
    this.payFor.set(s);
  }

  protected async savePayment(): Promise<void> {
    const s = this.payFor();
    const amount = parseAmount(this.payText);
    if (!s) return;
    if (Number.isNaN(amount) || amount <= 0) return this.actionError.set(this.i18n.t('sales.pay.err'));
    if (amount > this.owing(s)) return this.actionError.set(this.i18n.t('sales.pay.toomuch', tsh(this.owing(s))));
    if (this.payMethod !== 'cash' && !this.payReference.trim()) return this.actionError.set(this.i18n.t('till.err.reference_required'));
    this.busy.set(true);
    try {
      await firstValueFrom(this.till.recordPayment(s.id, amount, this.payMethod, this.payMethod === 'cash' ? undefined : this.payReference.trim()));
      this.payFor.set(null);
      this.toast.success(this.i18n.t('sales.pay.saved', tsh(amount)), this.i18n.t('common.done'));
      await this.load();
    } catch (err) {
      this.actionError.set(this.fail(err));
    } finally {
      this.busy.set(false);
    }
  }

  protected openCancel(s: SaleRow): void {
    this.cancelReason = '';
    this.actionError.set('');
    this.cancelFor.set(s);
  }

  protected async saveCancel(): Promise<void> {
    const s = this.cancelFor();
    if (!s) return;
    if (!this.cancelReason.trim()) return this.actionError.set(this.i18n.t('sales.cancel.err'));
    this.busy.set(true);
    try {
      await firstValueFrom(this.till.cancelSale(s.id, this.cancelReason.trim()));
      this.cancelFor.set(null);
      this.toast.success(this.i18n.t('sales.cancel.done', s.number), this.i18n.t('common.done'));
      await this.load();
    } catch (err) {
      this.actionError.set(this.fail(err));
    } finally {
      this.busy.set(false);
    }
  }

  protected async receipt(s: SaleRow): Promise<void> {
    try {
      printReceipt(await firstValueFrom(this.till.sale(s.id)), this.caps.receiptHeader(), (k) => this.i18n.t(k));
    } catch (err) {
      this.toast.error(this.fail(err), this.i18n.t('error.title'));
    }
  }

  protected async openReturn(s: SaleRow): Promise<void> {
    this.actionError.set('');
    this.returnReason = '';
    this.returnRestock = true;
    try {
      const d = await firstValueFrom(this.till.sale(s.id));
      this.returnQty.set(Object.fromEntries(d.items.map((i) => [i.product_id, 0])));
      this.returnFor.set(d);
    } catch (err) {
      this.toast.error(this.fail(err), this.i18n.t('error.title'));
    }
  }

  protected setReturnQty(productId: number, max: number, text: string): void {
    const n = Math.min(max, Math.max(0, Math.floor(Number(text)) || 0));
    this.returnQty.update((q) => ({ ...q, [productId]: n }));
  }

  protected async saveReturn(): Promise<void> {
    const d = this.returnFor();
    if (!d) return;
    const lines = d.items
      .filter((i) => (this.returnQty()[i.product_id] ?? 0) > 0)
      .map((i) => ({ product_id: i.product_id, quantity: this.returnQty()[i.product_id], unit_price: i.unit_price, restock: this.returnRestock }));
    if (!lines.length) return this.actionError.set(this.i18n.t('sales.return.err'));
    this.busy.set(true);
    try {
      await firstValueFrom(this.till.createReturn({ sale_id: d.id, type: 'return', reason: this.returnReason.trim() || undefined, lines }));
      this.returnFor.set(null);
      this.toast.success(this.i18n.t('sales.return.sent'), this.i18n.t('common.done'));
      await this.loadReturns();
    } catch (err) {
      this.actionError.set(this.fail(err));
    } finally {
      this.busy.set(false);
    }
  }

  protected async loadReturns(): Promise<void> {
    if (!this.canSell()) return;
    try {
      this.returns.set(await firstValueFrom(this.till.returns('pending')));
    } catch {
      this.returns.set([]);
    }
  }

  protected async decide(r: SaleReturn, decision: 'approved' | 'rejected'): Promise<void> {
    try {
      await firstValueFrom(this.till.decideReturn(r.id, decision));
      const said = decision === 'approved' ? 'sales.return.approved' : 'sales.return.rejected';
      this.toast.success(this.i18n.t(said), this.i18n.t('common.done'));
      await Promise.all([this.loadReturns(), this.load()]);
    } catch (err) {
      this.toast.error(this.fail(err), this.i18n.t('error.title'));
    }
  }

  protected channelName(c: string): string {
    return this.i18n.t(`pay.${c}`);
  }
}
