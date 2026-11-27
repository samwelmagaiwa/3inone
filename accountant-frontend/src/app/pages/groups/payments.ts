import { Component, OnInit, computed, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';
import { MemberPick, PickedMember } from './member-pick';

const STATES = ['pending', 'verified', 'rejected', ''];
const CATEGORIES = ['joining_fee', 'shares', 'savings', 'contribution', 'loan_repayment', 'expense', 'loan_disbursement', 'welfare', 'hire', 'dividend', 'opening_balance'];
/** What a member pays in (the phone's member payment kinds). */
const MEMBER_KINDS = ['contribution', 'savings', 'shares', 'joining_fee', 'loan_repayment'];
type Form = 'member' | 'withdrawal' | 'expense' | 'opening';

/**
 * The group's money: every payment in and out, waiting ones first. The treasurer records (a member's payment, possibly on an earlier
 * day; a savings withdrawal; a group expense; the opening balance), someone else verifies or turns it down, and a verified one is put
 * right only by a reversal. Nothing is ever edited or deleted.
 */
@Component({
  selector: 'app-g-payments',
  imports: [RowMenuComponent, FormsModule, ModalDialogComponent, MemberPick],
  template: `
    <div class="ad ph-page" data-testid="g-payments">
      @if (summary(); as s) {
        <div class="ph-tiles">
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.cash') }}</span><b class="ph-accent" data-testid="g-p-cash">{{ tsh(s['cash_on_record']) }}</b></div>
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.pending') }}</span><b class="ph-warn">{{ s['pending_count'] }} · {{ tsh(s['pending_amount']) }}</b></div>
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.savings') }}</span><b>{{ tsh(s['verified']?.['savings'] ?? 0) }}</b></div>
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.shares') }}</span><b>{{ tsh(s['verified']?.['shares'] ?? 0) }}</b></div>
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.p.spent.month') }}</span><b class="ph-bad">{{ tsh(s['expenses_in_month'] ?? 0) }}</b></div>
        </div>
      }

      <div class="g-toolbar">
        <div class="ph-chips g-seg">
          @for (s of states; track s) {
            <button type="button" class="pill-tab" [class.is-active]="state() === s" (click)="pickState(s)" [attr.data-testid]="'g-pst-' + (s || 'all')">{{ s ? status(s) : i18n.t('g.all') }}</button>
          }
        </div>
        <input class="g-search" [ngModel]="q()" (ngModelChange)="q.set($event)" (keyup.enter)="load(1)" [placeholder]="i18n.t('g.p.search.ph')" [attr.aria-label]="i18n.t('g.search')" />
        <select class="g-select" [ngModel]="category()" (ngModelChange)="category.set($event); load(1)" [attr.aria-label]="i18n.t('g.kind')" data-testid="g-p-cat">
          <option value="">{{ i18n.t('g.p.all.kinds') }}</option>
          @for (c of categories; track c) { <option [value]="c">{{ cat(c) }}</option> }
        </select>
        <button type="button" class="btn-outline ph-btn" (click)="load(1)">{{ i18n.t('ad.apply') }}</button>
        @if (recordMenu().length) {
          <app-row-menu [items]="recordMenu()" [label]="i18n.t('g.p.record.short')" icon="plus" buttonClass="btn-primary is-success ph-btn g-menu-btn" testid="g-p-record" (picked)="openForm($any($event))" />
        }
        <span class="g-count">{{ i18n.t('g.count', total()) }}</span>
      </div>

      @if (error()) {
        <section class="ph-card"><p>{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load(page())">{{ i18n.t('pl.retry') }}</button></section>
      } @else {
        <div class="table-scroll-container fit-page" data-testid="g-p-list">
          <table class="grid-table g-grid">
            <thead>
              <tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('g.paid.on') }}</th>
              <th>{{ i18n.t('g.p.who') }}</th>
              <th>{{ i18n.t('g.kind') }}</th>
              <th>{{ i18n.t('g.p.for') }}</th>
              <th>{{ i18n.t('g.method.col') }}</th>
              <th>{{ i18n.t('g.ref.col') }}</th>
              <th class="text-right">{{ i18n.t('g.amount') }}</th>
              <th>{{ i18n.t('g.status') }}</th>
              <th>{{ i18n.t('g.p.recorded.by') }}</th>
              <th>{{ i18n.t('g.note') }}</th>
              <th class="text-right">{{ i18n.t('g.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              @for (t of rows(); track t['id']) {
                <tr>
                  <td class="no-col">{{ $index + 1 }}</td>
                  <td>{{ day(t['paid_on']) }}</td>
                  <td class="font-bold g-long" [title]="t['member_name'] || t['payee'] || ''">{{ t['member_name'] || t['payee'] || (t['category'] === 'opening_balance' ? i18n.t('g.p.group') : '—') }}</td>
                  <td>{{ cat(t['category']) }}</td>
                  <td class="g-long" [title]="t['obligation_label'] || '—'">{{ t['obligation_label'] || '—' }}</td>
                  <td>{{ method(t['method']) }}</td>
                  <td>{{ t['external_ref'] || '—' }}</td>
                  <td class="text-right"><b [class.ph-good]="t['direction'] === 'in'" [class.ph-bad]="t['direction'] === 'out'">{{ t['direction'] === 'out' ? '-' : '+' }}{{ tsh(t['amount']) }}</b></td>
                  <td><span class="ph-badge" [class]="t['reversed_by_id'] ? 'ph-bad' : tone(t['status'])">{{ t['reversed_by_id'] ? status('reversed') : status(t['status']) }}</span></td>
                  <td class="g-long" [title]="t['submitted_by_name'] || '—'">{{ t['submitted_by_name'] || '—' }}</td>
                  <td class="g-long" [title]="t['reject_reason'] || t['note'] || '—'">{{ t['reject_reason'] || t['note'] || '—' }}</td>
                  <td class="text-right"><app-row-menu [items]="orNone(menuFor(t))" [testid]="'g-p-menu-' + t['id']" (picked)="picked($event, t)" /></td>
                </tr>
              } @empty {
                <tr><td colspan="12" class="ph-muted">{{ i18n.t('g.p.empty') }}</td></tr>
              }
            </tbody>
          </table>
        </div>
        <div class="ph-row">
          <button type="button" class="btn-outline ph-btn" [disabled]="page() <= 1" (click)="load(page() - 1)">{{ i18n.t('g.prev') }}</button>
          <span class="ph-muted">{{ i18n.t('g.page', page()) }}</span>
          <button type="button" class="btn-outline ph-btn" [disabled]="!more()" (click)="load(page() + 1)">{{ i18n.t('g.next') }}</button>
        </div>
      }
    </div>

    <app-modal-dialog [show]="!!form()" [eyebrow]="i18n.t('nav.g.payments')" [title]="formTitle()" size="md" [variant]="form() === 'expense' ? 'danger' : 'primary'" (close)="form.set(null)">
      <div slot="body" class="ph-page" style="gap: 10px">
        @if (form() === 'member' || form() === 'withdrawal') {
          <app-g-member-pick [value]="member()" (picked$)="pickMember($event)" status="" />
        }
        @if (form() === 'member') {
          <label class="ph-field">{{ i18n.t('g.kind') }}
            <select class="modal-input" [ngModel]="kind()" (ngModelChange)="kind.set($event); ref = ''" name="kind" data-testid="g-pf-kind">
              @for (k of memberKinds; track k) { <option [value]="k">{{ cat(k) }}</option> }
            </select></label>
          @if (kind() === 'contribution') {
            <label class="ph-field">{{ i18n.t('g.p.which.contribution') }}
              <select class="modal-input" [(ngModel)]="obligationId" name="obl" data-testid="g-pf-obl">
                <option [ngValue]="null">—</option>
                @for (o of owing(); track o['id']) { <option [ngValue]="o['id']">{{ o['label'] || o['type_name'] }} · {{ i18n.t('g.p.left', tsh(o['remaining'])) }}</option> }
              </select></label>
            @if (member() && !owing().length) { <p class="ph-muted">{{ i18n.t('g.p.nothing.owed') }}</p> }
          }
          @if (kind() === 'loan_repayment') {
            <label class="ph-field">{{ i18n.t('g.p.which.loan') }}
              <select class="modal-input" [(ngModel)]="loanId" name="loan" data-testid="g-pf-loan">
                <option [ngValue]="null">—</option>
                @for (l of memberLoans(); track l['id']) { <option [ngValue]="l['id']">{{ l['reference'] }} · {{ i18n.t('g.p.left', tsh(l['outstanding'] ?? l['position']?.['outstanding'] ?? 0)) }}</option> }
              </select></label>
            @if (member() && !memberLoans().length) { <p class="ph-muted">{{ i18n.t('g.p.no.loan') }}</p> }
          }
        }
        @if (form() === 'expense') {
          <label class="ph-field">{{ i18n.t('g.payee') }} *<input class="modal-input" [(ngModel)]="payee" name="payee" data-testid="g-pf-payee" /></label>
        }
        @if (form() === 'opening') {
          <p class="ph-muted">{{ i18n.t('g.p.opening.hint') }}</p>
        }
        <div class="ph-row" style="gap: 10px">
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.amount') }} *<input class="modal-input" inputmode="numeric" [(ngModel)]="amountText" name="amt" data-testid="g-pf-amount" /></label>
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.paid.on') }}<input class="modal-input" type="date" [(ngModel)]="paidOn" [max]="today()" name="paidOn" data-testid="g-pf-date" /></label>
        </div>
        <div class="ph-row" style="gap: 10px">
          <label class="ph-field" style="flex: 1">{{ form() === 'opening' ? i18n.t('g.held.as') : i18n.t('g.method') }}
            <select class="modal-input" [(ngModel)]="method_" name="method" data-testid="g-pf-method">
              @for (m of allowedMethods(); track m) { <option [value]="m">{{ method(m) }}</option> }
            </select></label>
          @if (method_ !== 'cash') {
            <label class="ph-field" style="flex: 1">{{ i18n.t('g.ref') }}{{ needsRef() ? ' *' : '' }}<input class="modal-input" [(ngModel)]="ref" name="ref" data-testid="g-pf-ref" /></label>
          }
        </div>
        <label class="ph-field">{{ form() === 'expense' ? i18n.t('g.p.for.what') : i18n.t('g.note') }}<input class="modal-input" [(ngModel)]="note" name="note" maxlength="255" /></label>
        <p class="ph-muted">{{ i18n.t('g.p.waits') }}</p>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="form.set(null)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary ph-btn" [class.is-success]="form() === 'member' || form() === 'opening'" [class.is-danger]="form() === 'expense'" [class.is-warn]="form() === 'withdrawal'"
          [disabled]="busy()" (click)="record()" data-testid="g-pf-save">{{ i18n.t('g.p.record.it') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [`.g-acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; } .g-acts:empty { display: none; }`],
})
export class GPaymentsPage extends GBase implements OnInit {
  protected readonly states = STATES;
  protected readonly categories = CATEGORIES;
  protected readonly memberKinds = MEMBER_KINDS;

  protected readonly summary = signal<Row | null>(null);
  protected readonly state = signal('pending');
  protected readonly category = signal('');
  protected readonly q = signal('');
  protected readonly rows = signal<Row[]>([]);
  protected readonly page = signal(1);
  protected readonly more = signal(false);
  protected readonly total = signal(0);
  protected readonly error = signal('');

  protected readonly form = signal<Form | null>(null);
  protected readonly member = signal<PickedMember | null>(null);
  protected readonly kind = signal('contribution');
  protected readonly owing = signal<Row[]>([]);
  protected readonly memberLoans = signal<Row[]>([]);
  protected readonly authorised = signal<string[]>([]);
  protected obligationId: number | null = null;
  protected loanId: number | null = null;
  protected amountText = '';
  protected paidOn = '';
  protected method_ = 'cash';
  protected ref = '';
  protected note = '';
  protected payee = '';

  /** The group's chosen methods once it has chosen; every method until then. */
  protected readonly allowedMethods = computed(() => (this.authorised().length ? this.authorised() : this.methods.filter((m) => m !== 'other')));

  /** What this person may record: a member's payment, and (for whoever records payouts) a withdrawal, spending and the opening balance. */
  protected readonly recordMenu = computed<MenuItem[]>(() => [
    ...(this.can('record_payments') ? [{ id: 'member', label: this.i18n.t('g.p.record'), primary: true, testid: 'g-p-new' }] : []),
    ...(this.can('record_payouts')
      ? [
          { id: 'withdrawal', label: this.i18n.t('g.p.withdrawal'), testid: 'g-p-withdraw' },
          { id: 'expense', label: this.i18n.t('g.p.expense'), danger: true, testid: 'g-p-expense' },
          { id: 'opening', label: this.i18n.t('g.p.opening'), testid: 'g-p-opening' },
        ]
      : []),
  ]);

  protected readonly formTitle = computed(() => {
    switch (this.form()) {
      case 'withdrawal': return this.i18n.t('g.p.withdrawal');
      case 'expense': return this.i18n.t('g.p.expense');
      case 'opening': return this.i18n.t('g.p.opening');
      default: return this.i18n.t('g.p.record');
    }
  });

  ngOnInit(): void {
    void this.load(1);
    void this.loadSummary();
    void this.api.get('/payment-methods').then((d) => this.authorised.set(((d['methods'] as Row[]) ?? []).map((m) => String(m['method'])))).catch(() => undefined);
  }

  /** The three-dots menu of a payment's row. */
  protected menuFor(t: Row): MenuItem[] {
    const items: MenuItem[] = [];
    if (t['status'] === 'pending' && this.can('verify_payments')) {
      items.push({ id: 'verify', label: this.i18n.t('g.verify'), primary: true, testid: 'g-p-verify-' + t['id'] });
      items.push({ id: 'reject', label: this.i18n.t('g.turn.down'), danger: true, testid: 'g-p-reject-' + t['id'] });
    }
    if (t['status'] === 'verified' && !t['reversed_by_id'] && !t['reverses_id'] && this.can('reverse_payments')) {
      items.push({ id: 'reverse', label: this.i18n.t('g.p.reverse'), danger: true, testid: 'g-p-reverse-' + t['id'] });
    }
    return items;
  }

  protected picked(id: string, t: Row): void {
    if (id === 'verify') void this.verify(t);
    if (id === 'reject') void this.reject(t);
    if (id === 'reverse') void this.reverse(t);
  }

  protected needsRef(): boolean {
    return this.method_ !== 'cash' && (this.form() === 'member' || this.form() === 'opening');
  }

  protected pickState(s: string): void {
    this.state.set(s);
    void this.load(1);
  }

  async loadSummary(): Promise<void> {
    try {
      this.summary.set(await this.api.get('/transactions/summary'));
    } catch {
      this.summary.set(null);
    }
  }

  async load(page: number): Promise<void> {
    this.error.set('');
    try {
      const p = await this.api.page('/transactions', 'transactions', { status: this.state() || null, category: this.category() || null, q: this.q() || null, page });
      this.rows.set(p.items);
      this.page.set(p.page);
      this.more.set(p.hasMore);
      this.total.set(p.total);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  protected openForm(kind: Form): void {
    this.form.set(kind);
    this.member.set(null);
    this.kind.set('contribution');
    this.owing.set([]);
    this.memberLoans.set([]);
    this.obligationId = null;
    this.loanId = null;
    this.amountText = '';
    this.paidOn = this.today();
    this.method_ = this.allowedMethods()[0] ?? 'cash';
    this.ref = '';
    this.note = '';
    this.payee = '';
  }

  /** A member chosen: what they owe (for a contribution) and their running loans (for a repayment). */
  protected async pickMember(m: PickedMember | null): Promise<void> {
    this.member.set(m);
    this.owing.set([]);
    this.memberLoans.set([]);
    this.obligationId = null;
    this.loanId = null;
    if (!m) return;
    try {
      const o = await this.api.page('/obligations', 'obligations', { member_id: m.id, state: 'owing' });
      this.owing.set(o.items);
      if (o.items.length === 1) this.obligationId = Number(o.items[0]['id']);
    } catch {
      /* the list stays empty: the payment can still be another kind */
    }
    if (this.can('view_loans', 'view_finance')) {
      try {
        const l = await this.api.page('/loans', 'loans', { status: 'active' });
        this.memberLoans.set(l.items.filter((x) => Number(x['member_id']) === m.id));
        if (this.memberLoans().length === 1) this.loanId = Number(this.memberLoans()[0]['id']);
      } catch {
        /* none shown */
      }
    }
  }

  protected async record(): Promise<void> {
    const form = this.form();
    const amount = this.amount(this.amountText);
    if (amount < 1) return this.stop(this.i18n.t('g.need.amount'));
    const body: Row = { amount, method: this.method_, paid_on: this.paidOn || this.today() };
    if (this.ref.trim()) body['external_ref'] = this.ref.trim();
    if (this.note.trim()) body['note'] = this.note.trim();
    let what = '';
    if (form === 'member' || form === 'withdrawal') {
      const m = this.member();
      if (!m) return this.stop(this.i18n.t('g.need.member'));
      body['member_id'] = m.id;
      if (form === 'withdrawal') {
        body['category'] = 'savings';
        body['direction'] = 'out';
      } else {
        body['category'] = this.kind();
        if (this.kind() === 'contribution') {
          if (!this.obligationId) return this.stop(this.i18n.t('g.need.contribution'));
          body['obligation_id'] = this.obligationId;
        }
        if (this.kind() === 'loan_repayment') {
          if (!this.loanId) return this.stop(this.i18n.t('g.need.loan'));
          body['loan_id'] = this.loanId;
        }
      }
      what = `${m.name}: ${form === 'withdrawal' ? this.i18n.t('g.p.withdrawal') : this.cat(this.kind())} ${this.tsh(amount)}`;
    } else if (form === 'expense') {
      if (this.payee.trim().length < 2) return this.stop(this.i18n.t('g.need.payee'));
      body['category'] = 'expense';
      body['payee'] = this.payee.trim();
      what = `${this.payee.trim()}: ${this.tsh(amount)}`;
    } else {
      body['category'] = 'opening_balance';
      what = `${this.i18n.t('g.p.opening')}: ${this.tsh(amount)}`;
    }
    if (!(await this.sure(this.formTitle(), `${what}\n${this.i18n.t('g.p.waits')}`, this.i18n.t('g.p.record.it'), form === 'expense' || form === 'withdrawal'))) return;
    if (await this.act(() => this.api.post('/transactions', body), this.i18n.t('g.p.recorded'))) {
      this.form.set(null);
      this.state.set('pending');
      await Promise.all([this.load(1), this.loadSummary()]);
    }
  }

  protected async verify(t: Row): Promise<void> {
    const who = t['member_name'] || t['payee'] || '';
    if (!(await this.sure(this.i18n.t('g.verify'), `${who} · ${this.cat(t['category'])} · ${this.tsh(t['amount'])}\n${this.i18n.t('g.p.verify.sure')}`, this.i18n.t('g.verify')))) return;
    if (await this.act(() => this.api.post(`/transactions/${t['id']}/verify`), this.i18n.t('g.p.verified'))) await this.after();
  }

  protected async reject(t: Row): Promise<void> {
    const why = await this.reason(this.i18n.t('g.turn.down'), this.i18n.t('g.p.reject.why'), this.i18n.t('g.turn.down'));
    if (why === null) return;
    if (await this.act(() => this.api.post(`/transactions/${t['id']}/reject`, { reason: why }), this.i18n.t('g.saved'))) await this.after();
  }

  protected async reverse(t: Row): Promise<void> {
    const why = await this.reason(this.i18n.t('g.p.reverse'), this.i18n.t('g.p.reverse.why', this.tsh(t['amount'])), this.i18n.t('g.p.reverse'));
    if (why === null) return;
    if (await this.act(() => this.api.post(`/transactions/${t['id']}/reverse`, { reason: why }), this.i18n.t('g.p.reversed'))) await this.after();
  }

  private async after(): Promise<void> {
    await Promise.all([this.load(this.page()), this.loadSummary(), this.ctx.reload()]);
  }
}
