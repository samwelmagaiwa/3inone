import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { AccountantApi } from '../../core/accountant-api.service';
import { dayLabel, offline, parseAmount, serverMessage, today, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { Debt, DebtKind, DebtPayment, DebtsListing } from '../../core/models';
import { ConfirmService } from '../../core/services/confirm.service';
import { MotionService } from '../../core/services/motion.service';
import { ToastService } from '../../core/services/toast.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { TablePaginationComponent } from '../../shared/components/table-pagination/table-pagination';
import { TableToolbarComponent } from '../../shared/components/table-toolbar/table-toolbar';
import { BsDateDirective } from '../../shared/ui/bs-date.directive';
import { CountUpDirective } from '../../shared/ui/count-up.directive';

/**
 * Every debt in one place, in two tabs: what customers owe me and what I owe. Debts from before the app are written here; they
 * join the debtors ageing, a customer's credit balance and the monthly report. Part payments are taken here; a debt that has
 * payments stays as a record (only a wrong entry nobody paid on can be deleted).
 */
@Component({
  selector: 'app-debts',
  imports: [FormsModule, ModalDialogComponent, TableToolbarComponent, TablePaginationComponent, BsDateDirective, CountUpDirective],
  templateUrl: './debts.html',
})
export class DebtsPage implements OnInit {
  private readonly api = inject(AccountantApi);
  private readonly toast = inject(ToastService);
  private readonly confirm = inject(ConfirmService);
  protected readonly i18n = inject(I18nService);
  protected readonly motion = inject(MotionService);

  protected readonly kind = signal<DebtKind>('receivable');
  protected readonly data = signal<Partial<Record<DebtKind, DebtsListing>>>({});
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);

  protected readonly query = signal('');
  protected readonly page = signal(1);
  protected readonly pageSize = signal(10);

  protected readonly tsh = tsh;
  protected readonly dayLabel = dayLabel;

  protected readonly current = computed(() => this.data()[this.kind()] ?? null);
  protected readonly rows = computed(() => {
    const q = this.query().toLowerCase().trim();
    const all = this.current()?.debts ?? [];
    return q ? all.filter((d) => `${d.name} ${d.phone ?? ''} ${d.note ?? ''}`.toLowerCase().includes(q)) : all;
  });
  protected readonly pageRows = computed(() => {
    const size = this.pageSize();
    const start = (this.page() - 1) * size;
    return this.rows().slice(start, start + size);
  });
  protected readonly noun = computed(() => this.i18n.t(this.rows().length === 1 ? 'debts.noun.one' : 'debts.noun.many'));

  // ------------------------------------------------------------------ the "add" window
  protected readonly addOpen = signal(false);
  protected name = '';
  protected phone = '';
  protected amountText = '';
  protected startedOn = today();
  protected dueOn = '';
  protected note = '';
  protected readonly addError = signal('');
  protected readonly saving = signal(false);

  // ------------------------------------------------------------------ the "payment" window
  protected readonly payFor = signal<Debt | null>(null);
  protected payText = '';
  protected readonly payError = signal('');
  protected readonly payments = signal<DebtPayment[] | null>(null);

  ngOnInit(): void {
    void this.load();
  }

  protected async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      const [receivable, payable] = await Promise.all([firstValueFrom(this.api.debts('receivable')), firstValueFrom(this.api.debts('payable'))]);
      this.data.set({ receivable, payable });
      this.motion.tick.update((n) => n + 1);
    } catch (err) {
      this.error.set(offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic')));
    } finally {
      this.loading.set(false);
    }
  }

  protected setKind(kind: DebtKind): void {
    this.kind.set(kind);
    this.query.set('');
    this.page.set(1);
  }

  protected setQuery(q: string): void {
    this.query.set(q);
    this.page.set(1);
  }

  protected late(d: Debt): boolean {
    return d.days_late > 0;
  }

  protected paidShare(d: Debt): number {
    return d.amount <= 0 ? 0 : Math.max(0, Math.min(100, ((d.amount - d.left) / d.amount) * 100));
  }

  // ------------------------------------------------------------------ add
  protected openAdd(): void {
    this.name = '';
    this.phone = '';
    this.amountText = '';
    this.startedOn = today();
    this.dueOn = '';
    this.note = '';
    this.addError.set('');
    this.addOpen.set(true);
  }

  protected async saveDebt(): Promise<void> {
    const t = (k: string) => this.i18n.t(k);
    const receivable = this.kind() === 'receivable';
    const amount = parseAmount(this.amountText);
    if (!this.name.trim()) return this.addError.set(t(receivable ? 'debts.err.name.owed' : 'debts.err.name.owe'));
    if (Number.isNaN(amount) || amount <= 0) return this.addError.set(t('debts.err.amount'));
    if (this.dueOn && this.dueOn < this.startedOn) return this.addError.set(t('debts.err.due'));

    this.saving.set(true);
    this.addError.set('');
    try {
      await firstValueFrom(
        this.api.addDebt({
          kind: this.kind(),
          name: this.name.trim(),
          phone: this.phone.trim() || undefined,
          amount,
          started_on: this.startedOn || undefined,
          due_on: this.dueOn || undefined,
          note: this.note.trim() || undefined,
        }),
      );
      this.addOpen.set(false);
      this.toast.success(this.i18n.t('debts.saved', this.name.trim()), t('common.done'));
      await this.load();
    } catch (err) {
      this.addError.set(offline(err) ? t('error.offline') : (serverMessage(err) ?? t('error.generic')));
    } finally {
      this.saving.set(false);
    }
  }

  // ------------------------------------------------------------------ pay
  protected async openPay(d: Debt): Promise<void> {
    this.payFor.set(d);
    this.payText = String(Math.round(d.left));
    this.payError.set('');
    this.payments.set(null);
    try {
      this.payments.set(await firstValueFrom(this.api.debtPayments(d.id)));
    } catch {
      this.payments.set([]);
    }
  }

  protected closePay(): void {
    this.payFor.set(null);
  }

  protected async savePayment(): Promise<void> {
    const d = this.payFor();
    if (!d) return;
    const amount = parseAmount(this.payText);
    if (Number.isNaN(amount) || amount <= 0 || amount > d.left + 0.001) {
      this.payError.set(this.i18n.t('debts.err.pay', tsh(d.left)));
      return;
    }
    this.saving.set(true);
    this.payError.set('');
    try {
      await firstValueFrom(this.api.payDebt(d.id, amount));
      this.payFor.set(null);
      const left = d.left - amount;
      this.toast.success(this.i18n.t(left <= 0.001 ? 'debts.paid.full' : 'debts.paid.part', d.name, tsh(left)), this.i18n.t('common.done'));
      await this.load();
    } catch (err) {
      this.payError.set(offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic')));
    } finally {
      this.saving.set(false);
    }
  }

  // ------------------------------------------------------------------ delete
  protected async remove(d: Debt): Promise<void> {
    const yes = await this.confirm.ask({
      title: this.i18n.t('debts.delete.title'),
      message: this.i18n.t('debts.delete.message', d.name, tsh(d.amount)),
      confirmLabel: this.i18n.t('common.delete'),
      cancelLabel: this.i18n.t('common.keep'),
      danger: true,
    });
    if (!yes) return;
    try {
      await firstValueFrom(this.api.deleteDebt(d.id));
      this.payFor.set(null);
      this.toast.success(this.i18n.t('debts.deleted'), this.i18n.t('common.done'));
      await this.load();
    } catch (err) {
      this.toast.error(offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic')), this.i18n.t('error.title'));
    }
  }
}
