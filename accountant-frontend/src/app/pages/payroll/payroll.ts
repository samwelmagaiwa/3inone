import { HttpClient } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { dayLabel, dayOf, monthKey, monthName, parseAmount, serverMessage, shiftMonth, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';

const API = environment.apiUrl;

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const text = (v: unknown): string => (v === null || v === undefined ? '' : String(v));
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {});
const rows = (v: unknown): Record<string, unknown>[] => (Array.isArray(v) ? v.map(obj) : []);

export interface PayrollRowView {
  staffId: string;
  name: string;
  salary: number;
  commissionEarned: number;
  salaryPaid: number;
  commissionPaid: number;
  advances: number;
  owed: number;
}

export interface PayrollView {
  salary: number;
  commissionEarned: number;
  owed: number;
  staff: PayrollRowView[];
}

export interface PayoutView {
  id: number;
  staffId: string;
  staffName: string;
  kind: string;
  amount: number;
  paidOn: string;
  method: string;
  note: string;
}

export function readPayroll(j: Record<string, unknown>): PayrollView {
  const t = obj(j['totals']);

  return {
    salary: num(t['salary']),
    commissionEarned: num(t['commission_earned']),
    owed: num(t['owed']),
    staff: rows(j['staff']).map((r) => ({
      staffId: text(r['staff_id']),
      name: text(r['name']),
      salary: num(r['salary']),
      commissionEarned: num(r['commission_earned']),
      salaryPaid: num(r['salary_paid']),
      commissionPaid: num(r['commission_paid']),
      advances: num(r['advances']),
      owed: num(r['owed']),
    })),
  };
}

export function readPayouts(list: unknown): PayoutView[] {
  return rows(list).map((r) => ({
    id: num(r['id']),
    staffId: text(r['staff_id']),
    staffName: text(r['staff_name']),
    kind: text(r['kind']),
    amount: num(r['amount']),
    paidOn: text(r['paid_on']),
    method: text(r['method']) || 'cash',
    note: text(r['note']),
  }));
}

export const CHANNELS = ['cash', 'mpesa', 'mixx', 'airtel_money', 'halopesa', 'bank_transfer'];

@Component({
  selector: 'app-payroll',
  imports: [FormsModule, ModalDialogComponent],
  template: `
    <div class="ad ph-page" data-testid="payroll-page">
      <div class="ph-row">
        <button type="button" class="btn-outline ph-btn" (click)="go(-1)" data-testid="pr-prev" [attr.aria-label]="i18n.t('tm.prev')">‹</button>
        <b data-testid="pr-month">{{ monthTitle() }}</b>
        <button type="button" class="btn-outline ph-btn" (click)="go(1)" data-testid="pr-next" [attr.aria-label]="i18n.t('tm.next')">›</button>
      </div>

      @if (error() && !report()) {
        <section class="ph-card"><p data-testid="pr-error">{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (!report()) {
        <section class="ph-card"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else {
        @let r = report()!;
        <div class="ph-tiles">
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('pr.salary') }}</span><b data-testid="pr-salary">{{ tsh(r.salary) }}</b></div>
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('st.commission') }}</span><b class="ph-warn">{{ tsh(r.commissionEarned) }}</b></div>
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('pr.owed') }}</span><b class="ph-good" data-testid="pr-owed">{{ tsh(r.owed) }}</b></div>
        </div>
        @if (error()) { <p class="ph-bad">{{ error() }}</p> }

        @for (s of r.staff; track s.staffId) {
          <section class="ph-card" [attr.data-testid]="'pr-staff-' + s.staffId">
            <div class="ph-row"><h3>{{ s.name }}</h3><button type="button" class="btn-outline ph-btn" (click)="openProfile(s)" [attr.data-testid]="'pr-profile-' + s.staffId">{{ i18n.t('pr.profile') }}</button></div>
            <div class="ph-line"><span>{{ i18n.t('pr.salary') }}</span><b>{{ tsh(s.salary) }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('st.commission') }}</span><b>{{ tsh(s.commissionEarned) }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('pr.paid') }}</span><b>{{ tsh(s.salaryPaid + s.commissionPaid) }}</b></div>
            <div class="ph-line"><span>{{ i18n.t('pr.advance') }}</span><b>{{ tsh(s.advances) }}</b></div>
            <div class="ph-row" style="margin-top: 6px">
              <b [class.ph-warn]="s.owed > 0" [class.ph-good]="s.owed <= 0" [attr.data-testid]="'pr-owed-' + s.staffId">{{ s.owed > 0 ? i18n.t('pr.owed.amount', tsh(s.owed)) : i18n.t('pr.nothing.owed') }}</b>
              <button type="button" class="btn-primary ph-btn" (click)="openPay(s)" [attr.data-testid]="'pr-pay-' + s.staffId">{{ i18n.t('pr.pay') }}</button>
            </div>
          </section>
        } @empty {
          <section class="ph-card"><p class="ph-muted">{{ i18n.t('pr.none') }}</p></section>
        }

        @if (payouts().length) {
          <section class="ph-card">
            <h3>{{ i18n.t('pr.payments') }}</h3>
            @for (p of payouts(); track p.id) {
              <div class="ph-row" style="padding: 4px 0" [attr.data-testid]="'pr-payout-' + p.id">
                <span>{{ p.staffName }} • {{ kindName(p.kind) }}<br /><span class="ph-muted">{{ dayLabel(p.paidOn) }} • {{ channel(p.method) }}@if (p.note) { • {{ p.note }} }</span></span>
                <span><b>{{ tsh(p.amount) }}</b> <button type="button" class="btn-outline" style="padding: 0 8px" (click)="remove(p)" [attr.aria-label]="i18n.t('cb.remove')" [attr.data-testid]="'pr-remove-' + p.id">×</button></span>
              </div>
            }
          </section>
        }
      }
    </div>

    <app-modal-dialog [show]="dialog() === 'pay'" [eyebrow]="i18n.t('pr.pay')" [title]="who()?.name ?? ''" size="sm" (close)="dialog.set('')">
      <div slot="body" class="ph-page" style="gap: 12px">
        <div class="ph-chips">
          @for (k of kinds; track k) { <button type="button" class="pill-tab" [class.is-active]="fKind() === k" (click)="fKind.set(k)" [attr.data-testid]="'pr-kind-' + k">{{ kindName(k) }}</button> }
        </div>
        <label class="ph-field">{{ i18n.t('pr.amount') }}<input class="modal-input" inputmode="numeric" [ngModel]="fAmount()" (ngModelChange)="fAmount.set($event)" data-testid="pr-amount" name="prAmount" /></label>
        <div>
          <p class="ph-field">{{ i18n.t('pr.paid.by') }}</p>
          <div class="ph-chips" style="margin-top: 4px">
            @for (c of channels; track c) { <button type="button" class="pill-tab" [class.is-active]="fMethod() === c" (click)="fMethod.set(c)">{{ channel(c) }}</button> }
          </div>
        </div>
        <label class="ph-field">{{ i18n.t('cb.note') }}<input class="modal-input" [ngModel]="fNote()" (ngModelChange)="fNote.set($event)" name="prNote" /></label>
        @if (problem()) { <p class="ph-bad" data-testid="pr-problem">{{ problem() }}</p> }
      </div>
      <div slot="footer" class="flex gap-2 justify-end">
        <button type="button" class="modal-cancel-btn" (click)="dialog.set('')">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary" [disabled]="busy()" (click)="savePay()" data-testid="pr-save">{{ i18n.t('pr.save.payment') }}</button>
      </div>
    </app-modal-dialog>

    <app-modal-dialog [show]="dialog() === 'profile'" [eyebrow]="i18n.t('pr.profile')" [title]="who()?.name ?? ''" size="sm" (close)="dialog.set('')">
      <div slot="body" class="ph-page" style="gap: 12px">
        <label class="ph-field">{{ i18n.t('pr.special') }}<input class="modal-input" [ngModel]="fSpecial()" (ngModelChange)="fSpecial.set($event)" name="prSpecial" /></label>
        <label class="ph-field">{{ i18n.t('pr.monthly') }}<input class="modal-input" inputmode="numeric" [ngModel]="fSalary()" (ngModelChange)="fSalary.set($event)" data-testid="pr-salary-input" name="prSalary" /></label>
        <label class="ph-field">{{ i18n.t('pr.rate') }}<input class="modal-input" inputmode="decimal" [ngModel]="fRate()" (ngModelChange)="fRate.set($event)" data-testid="pr-rate" name="prRate" /></label>
        <p class="ph-muted">{{ i18n.t('pr.rate.hint') }}</p>
        @if (problem()) { <p class="ph-bad" data-testid="pr-problem">{{ problem() }}</p> }
      </div>
      <div slot="footer" class="flex gap-2 justify-end">
        <button type="button" class="modal-cancel-btn" (click)="dialog.set('')">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary" [disabled]="busy() || !loaded()" (click)="saveProfile()" data-testid="pr-profile-save">{{ i18n.t('common.save') }}</button>
      </div>
    </app-modal-dialog>
  `,
})
export class PayrollPage implements OnInit {
  private readonly http = inject(HttpClient);
  protected readonly i18n = inject(I18nService);
  protected readonly tsh = tsh;
  protected readonly dayLabel = dayLabel;
  protected readonly channels = CHANNELS;
  protected readonly kinds = ['salary', 'commission', 'advance'];

  protected readonly month = signal(monthKey(new Date()));
  protected readonly report = signal<PayrollView | null>(null);
  protected readonly payouts = signal<PayoutView[]>([]);
  protected readonly error = signal('');
  private asked = 0;

  protected readonly dialog = signal<'' | 'pay' | 'profile'>('');
  protected readonly who = signal<PayrollRowView | null>(null);
  protected readonly fKind = signal('salary');
  protected readonly fAmount = signal('');
  protected readonly fMethod = signal('cash');
  protected readonly fNote = signal('');
  protected readonly fSpecial = signal('');
  protected readonly fSalary = signal('');
  protected readonly fRate = signal('');
  protected readonly problem = signal('');
  protected readonly busy = signal(false);
  protected readonly loaded = signal(false);

  protected readonly monthTitle = computed(() => monthName(this.month(), this.i18n.lang() === 'sw' ? 'sw-TZ' : 'en-GB'));

  ngOnInit(): void {
    void this.load();
  }

  protected go(by: number): void {
    this.month.set(shiftMonth(this.month(), by));
    void this.load();
  }

  protected kindName(k: string): string {
    return k === 'salary' ? this.i18n.t('pr.k.salary') : k === 'commission' ? this.i18n.t('st.commission') : this.i18n.t('pr.k.advance');
  }

  protected channel(m: string): string {
    switch (m) {
      case 'cash': return this.i18n.t('pl.ch.cash');
      case 'mpesa': return 'M-Pesa';
      case 'mixx': return 'Mixx';
      case 'airtel_money': return 'Airtel Money';
      case 'halopesa': return 'HaloPesa';
      case 'bank_transfer': return this.i18n.t('pl.ch.bank');
      default: return m.replace(/_/g, ' ');
    }
  }

  async load(): Promise<void> {
    const month = this.month();
    const ticket = ++this.asked;
    this.error.set('');
    try {
      const [rep, pay] = await Promise.all([
        firstValueFrom(this.http.get<{ data: Record<string, unknown> }>(`${API}/inventory/salon/payroll`, { params: { month } })),
        firstValueFrom(this.http.get<{ data?: unknown }>(`${API}/inventory/salon/payouts`, { params: { month } })),
      ]);
      if (ticket !== this.asked) return;
      this.report.set(readPayroll(rep.data ?? {}));
      this.payouts.set(readPayouts(pay.data));
    } catch (e) {
      if (ticket !== this.asked) return;
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
  }

  protected openPay(s: PayrollRowView): void {
    this.who.set(s);
    this.fKind.set('salary');
    this.fAmount.set(s.owed > 0 ? String(Math.round(s.owed)) : '');
    this.fMethod.set('cash');
    this.fNote.set('');
    this.problem.set('');
    this.dialog.set('pay');
  }

  protected async savePay(): Promise<void> {
    const s = this.who();
    const amount = parseAmount(this.fAmount());
    if (!s) return;
    if (!(amount > 0)) {
      this.problem.set(this.i18n.t('pr.err.amount'));
      return;
    }
    this.busy.set(true);
    try {
      await firstValueFrom(
        this.http.post(`${API}/inventory/salon/payouts`, {
          staff_id: s.staffId,
          kind: this.fKind(),
          amount,
          paid_on: dayOf(new Date()),
          method: this.fMethod(),
          ...(this.fKind() === 'advance' ? {} : { period_month: this.month() }),
          ...(this.fNote().trim() ? { note: this.fNote().trim() } : {}),
        }),
      );
      this.dialog.set('');
      await this.load();
    } catch (e) {
      this.problem.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
    this.busy.set(false);
  }

  protected async openProfile(s: PayrollRowView): Promise<void> {
    this.who.set(s);
    this.problem.set('');
    this.loaded.set(false);
    this.fSpecial.set('');
    this.fSalary.set(s.salary > 0 ? String(Math.round(s.salary)) : '');
    this.fRate.set('');
    this.dialog.set('profile');
    try {
      const r = await firstValueFrom(this.http.get<{ data?: unknown }>(`${API}/inventory/salon/staff-profiles`));
      const p = rows(r.data).find((x) => text(x['staff_id']) === s.staffId);
      if (p) {
        this.fSpecial.set(text(p['specialization']));
        this.fSalary.set(num(p['monthly_salary']) > 0 ? String(Math.round(num(p['monthly_salary']))) : '');
        this.fRate.set(p['commission_percent'] === null || p['commission_percent'] === undefined ? '' : String(num(p['commission_percent'])));
      }
    } catch {
      // the form still works with what the payroll row knows
    }
    this.loaded.set(true);
  }

  protected async saveProfile(): Promise<void> {
    const s = this.who();
    if (!s) return;
    const rateText = this.fRate().trim().replace(',', '.');
    const rate = rateText === '' ? null : Number(rateText);
    if (rate !== null && (!Number.isFinite(rate) || rate < 0 || rate > 100)) {
      this.problem.set(this.i18n.t('pr.err.rate'));
      return;
    }
    const salary = parseAmount(this.fSalary());
    this.busy.set(true);
    try {
      await firstValueFrom(
        this.http.put(`${API}/inventory/salon/staff-profiles/${s.staffId}`, {
          specialization: this.fSpecial().trim(),
          monthly_salary: Number.isFinite(salary) ? salary : 0,
          commission_percent: rate,
        }),
      );
      this.dialog.set('');
      await this.load();
    } catch (e) {
      this.problem.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
    this.busy.set(false);
  }

  protected async remove(p: PayoutView): Promise<void> {
    if (typeof window !== 'undefined' && !window.confirm(`${this.i18n.t('pr.delete.ask')}\n${tsh(p.amount)} • ${p.staffName}`)) return;
    try {
      await firstValueFrom(this.http.delete(`${API}/inventory/salon/payouts/${p.id}`));
      await this.load();
    } catch (e) {
      this.error.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
  }
}
