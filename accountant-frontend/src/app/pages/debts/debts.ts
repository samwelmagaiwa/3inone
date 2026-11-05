import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { AccountantApi } from '../../core/accountant-api.service';
import { dayLabel, offline, parseAmount, serverMessage, today, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { Debt, DebtKind, DebtPayment, DebtsListing } from '../../core/models';
import { ConfirmService } from '../../core/services/confirm.service';
import { CapabilitiesService } from '../../core/capabilities.service';
import { ExportSheet } from '../../core/export';
import { SortState, nextSort, sortArrow, sorted } from '../../core/sort';
import { MotionService } from '../../core/services/motion.service';
import { ToastService } from '../../core/services/toast.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { ExportMenuComponent } from '../../shared/components/export-menu/export-menu';
import { ListBarComponent } from '../../shared/components/list-bar/list-bar';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { StickyRowDirective } from '../../shared/ui/sticky-row.directive';
import { TableToolbarComponent } from '../../shared/components/table-toolbar/table-toolbar';
import { BsDateDirective } from '../../shared/ui/bs-date.directive';
import { CountUpDirective } from '../../shared/ui/count-up.directive';
import { MoneyDirective } from '../../shared/ui/money.directive';

/**
 * Every debt in one place, in two tabs: what customers owe me and what I owe. Debts from before the app are written here; they
 * join the debtors ageing, a customer's credit balance and the monthly report. Part payments are taken here; a debt that has
 * payments stays as a record (only a wrong entry nobody paid on can be deleted).
 */
@Component({
  selector: 'app-debts',
  imports: [FormsModule, ModalDialogComponent, TableToolbarComponent, ListBarComponent, RowMenuComponent, ExportMenuComponent, StickyRowDirective, BsDateDirective, CountUpDirective, MoneyDirective],
  templateUrl: './debts.html',
})
export class DebtsPage implements OnInit {
  private readonly api = inject(AccountantApi);
  private readonly toast = inject(ToastService);
  private readonly confirm = inject(ConfirmService);
  protected readonly i18n = inject(I18nService);
  protected readonly motion = inject(MotionService);
  private readonly caps = inject(CapabilitiesService);

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
    const found = q ? all.filter((d) => `${d.name} ${d.phone ?? ''} ${d.note ?? ''}`.toLowerCase().includes(q)) : all;

    return sorted(found, this.sort(), (d, k) => (k === 'name' ? d.name : k === 'phone' ? (d.phone ?? '') : k === 'amount' ? d.amount : k === 'left' ? d.left : d.due_on ?? d.started_on));
  });
  protected readonly sort = signal<SortState | null>(null);
  protected readonly arrow = sortArrow;

  protected sortBy(key: string): void {
    this.sort.update((c) => nextSort(c, key));
    this.page.set(1);
  }
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

  // ------------------------------------------------------------------ the menu of a row, and the export
  protected menuFor(d: Debt): MenuItem[] {
    const items: MenuItem[] = [
      { id: 'pay', label: this.i18n.t(this.kind() === 'receivable' ? 'debts.receive' : 'debts.pay'), primary: true, disabled: d.left <= 0, testid: 'debt-pay-' + d.id },
      { id: 'history', label: this.i18n.t('debts.payments'), testid: 'debt-history-' + d.id },
    ];
    // A debt nobody has paid on can still be taken away if it was a mistake; one with payments stays as a record.
    if (d.paid === 0) items.push({ id: 'delete', label: this.i18n.t('debts.delete.menu'), danger: true, testid: 'debt-delete-' + d.id });

    return items;
  }

  protected menuPicked(id: string, d: Debt): void {
    if (id === 'delete') void this.remove(d);
    else this.openPay(d);
  }

  /** The list as it is on the page now (the tab, the search), with the totals: what is printed or saved. */
  protected readonly sheet = (): ExportSheet => {
    const owed = this.kind() === 'receivable';
    const c = this.current();
    const rows = this.rows();
    const status = (d: Debt): string => (this.late(d) ? this.i18n.t('debts.late', d.days_late) : d.due_on ? this.i18n.t('debts.due', dayLabel(d.due_on)) : this.i18n.t('debts.since', dayLabel(d.started_on)));
    const sum = (f: (d: Debt) => number): number => rows.reduce((n, d) => n + f(d), 0);

    return {
      business: this.caps.receiptHeader().business,
      title: this.i18n.t(owed ? 'debts.tab.owed' : 'debts.tab.owe'),
      facts: [
        this.i18n.t('export.date', dayLabel(today())),
        `${this.i18n.t(owed ? 'debts.total.owed' : 'debts.total.owe')}: ${tsh(c?.total ?? 0)}`,
        `${this.i18n.t('debts.old')}: ${tsh(c?.old ?? 0)}`,
        `${rows.length} ${this.noun()}`,
      ],
      columns: [
        { label: '#', align: 'center', width: 6 },
        { label: this.i18n.t('debts.col.name'), width: 28 },
        { label: this.i18n.t('debts.col.phone'), width: 16 },
        { label: this.i18n.t('debts.form.note'), width: 28 },
        { label: this.i18n.t('debts.form.started'), width: 14 },
        { label: this.i18n.t('debts.form.due'), width: 14 },
        { label: this.i18n.t('debts.col.amount'), type: 'money', align: 'right', width: 16 },
        { label: this.i18n.t('debts.col.paid'), type: 'money', align: 'right', width: 16 },
        { label: this.i18n.t('debts.col.left'), type: 'money', align: 'right', width: 16 },
        { label: this.i18n.t('debts.col.when'), width: 20 },
      ],
      rows: rows.map((d, i) => [i + 1, d.name, d.phone ?? '', d.note ?? '', dayLabel(d.started_on), d.due_on ? dayLabel(d.due_on) : '', d.amount, d.amount - d.left, d.left, status(d)]),
      totals: [null, this.i18n.t('export.total'), null, null, null, null, sum((d) => d.amount), sum((d) => d.amount - d.left), sum((d) => d.left), null],
      footer: this.caps.receiptHeader().business,
    };
  };

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
