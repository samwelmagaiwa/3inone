import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';
import { MemberPick, PickedMember } from './member-pick';

const STATUSES = ['open', 'awaiting_guarantors', 'under_review', 'recommended', 'approved', 'active', 'rejected', 'cancelled', ''];

/**
 * Loans: each one's road (guarantors, the projects committee's recommendation, the chair's approval, the treasurer's payout, which
 * someone else verifies), what is owed and late, the repayment schedule, and an application entered for a member. Nobody takes a step
 * on their own loan; the server refuses it too.
 */
@Component({
  selector: 'app-g-loans',
  imports: [RowMenuComponent, FormsModule, ModalDialogComponent, MemberPick],
  template: `
    <div class="ad ph-page" data-testid="g-loans">
      <div class="g-toolbar">
        <div class="ph-chips g-seg">
          @for (s of statuses; track s) {
            <button type="button" class="pill-tab" [class.is-active]="filter() === s" (click)="filter.set(s); load(1)" [attr.data-testid]="'g-l-st-' + (s || 'all')">{{ s === 'open' ? i18n.t('g.l.open') : s ? status(s) : i18n.t('g.all') }}</button>
          }
        </div>
        <input class="g-search" [ngModel]="find()" (ngModelChange)="find.set($event)" [placeholder]="i18n.t('g.find.ph')" [attr.aria-label]="i18n.t('g.search')" />
        <button type="button" class="btn-outline ph-btn" (click)="load(1)">{{ i18n.t('ad.apply') }}</button>
        @if (can('record_payments')) {
          <button type="button" class="btn-primary ph-btn" (click)="openApply()" data-testid="g-l-new" [title]="i18n.t('g.l.apply')">{{ i18n.t('g.l.new') }}</button>
        }
        <span class="g-count">{{ i18n.t('g.count', shownCount()) }}</span>
      </div>

      @if (error()) {
        <section class="ph-card"><p>{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load(page())">{{ i18n.t('pl.retry') }}</button></section>
      } @else {
        <div class="table-scroll-container fit-page" data-testid="g-l-list">
          <table class="grid-table">
            <thead>
              <tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('g.reference') }}</th>
              <th>{{ i18n.t('g.member') }}</th>
              <th>{{ i18n.t('g.l.purpose') }}</th>
              <th class="text-right">{{ i18n.t('g.amount') }}</th>
              <th>{{ i18n.t('g.l.months') }}</th>
              <th>{{ i18n.t('g.l.rate') }}</th>
              <th class="text-right">{{ i18n.t('g.l.owed') }}</th>
              <th class="text-right">{{ i18n.t('g.loans.arrears') }}</th>
              <th>{{ i18n.t('g.status') }}</th>
              <th class="text-right">{{ i18n.t('g.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              @for (l of filtered(rows(), keys); track l['id']) {
                <tr>
                  <td class="no-col">{{ $index + 1 }}</td>
                  <td>{{ l['reference'] }}</td>
                  <td class="font-bold">{{ l['member_name'] }}</td>
                  <td>{{ l['purpose'] }}</td>
                  <td class="text-right">{{ tsh(l['amount_approved'] ?? l['amount_requested']) }}</td>
                  <td>{{ l['term_months'] }}</td>
                  <td>{{ l['interest_rate'] }}%@if (l['interest_method']) { · {{ i18n.t('g.l.method.' + l['interest_method']) }} }</td>
                  <td class="text-right">{{ l['outstanding'] === null || l['outstanding'] === undefined ? '—' : tsh(l['outstanding']) }}</td>
                  <td class="text-right"><span [class.ph-bad]="l['arrears'] > 0">{{ l['arrears'] ? tsh(l['arrears']) : '—' }}</span></td>
                  <td><span class="ph-badge" [class]="tone(l['state'] === 'overdue' ? 'overdue' : l['status'])">{{ l['state'] === 'overdue' ? status('overdue') : status(l['status']) }}</span></td>
                  <td class="text-right">@if (menuFor(l).length) { <app-row-menu [items]="menuFor(l)" [testid]="'g-l-menu-' + l['id']" (picked)="picked($event, l)" /> } @else { — }</td>
                </tr>
              } @empty {
                <tr><td colspan="11" class="ph-muted">{{ i18n.t('g.l.none') }}</td></tr>
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

    <!-- one loan -->
    <app-modal-dialog [show]="!!loan()" [eyebrow]="loan()?.['reference'] ?? ''" [title]="loan()?.['member_name'] ?? ''" size="xl" (close)="loan.set(null)">
      <div slot="body">
        @if (loan(); as l) {
          <div class="ph-page" style="gap: 10px">
            <div class="ph-tiles">
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.status') }}</span><b [class]="tone(l['status'])">{{ status(l['status']) }}</b></div>
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.l.asked') }}</span><b>{{ tsh(l['amount_requested']) }}</b></div>
              @if (l['amount_approved'] !== null) { <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.l.approved') }}</span><b class="ph-good">{{ tsh(l['amount_approved']) }}</b></div> }
              @if (l['ceiling'] !== null) { <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.l.ceiling') }}</span><b>{{ tsh(l['ceiling']) }}</b></div> }
              @if (l['position']; as p) {
                <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.l.owed') }}</span><b class="ph-accent">{{ tsh(p['outstanding']) }}</b></div>
                <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.loans.arrears') }}</span><b [class.ph-bad]="p['arrears'] > 0">{{ tsh(p['arrears']) }}</b></div>
              }
            </div>
            <div class="ph-card ph-joined ph-cols">
              <section class="ph-sec">
                <h3>{{ i18n.t('g.details') }}</h3>
                <div class="ph-line"><span>{{ i18n.t('g.l.purpose') }}</span><b>{{ l['purpose'] }}</b></div>
                <div class="ph-line"><span>{{ i18n.t('g.l.months') }}</span><b>{{ l['term_months'] }}</b></div>
                <div class="ph-line"><span>{{ i18n.t('g.l.rate') }}</span><b>{{ l['interest_rate'] }}% · {{ l['interest_method'] ? i18n.t('g.l.method.' + l['interest_method']) : '—' }}</b></div>
                <div class="ph-line"><span>{{ i18n.t('g.l.repay') }}</span><b>{{ i18n.t('g.repay.' + (l['repayment_every'] || 'monthly')) }}</b></div>
                @if (l['disbursed_on']) { <div class="ph-line"><span>{{ i18n.t('g.l.paid.out') }}</span><b>{{ day(l['disbursed_on']) }}</b></div> }
                @if (recommendation(l); as r) { <div class="ph-line"><span>{{ i18n.t('g.l.recommendation') }}</span><b>{{ r }}</b></div> }
                @if (l['reject_reason']) { <div class="ph-line"><span>{{ i18n.t('g.reason') }}</span><b class="ph-bad">{{ l['reject_reason'] }}</b></div> }
              </section>
              <section class="ph-sec">
                <h3>{{ i18n.t('g.l.guarantors') }}</h3>
                @for (g of l['guarantors'] ?? []; track g['id']) {
                  <div class="ph-line"><span>{{ g['name'] }}@if (g['note']) { <span class="ph-muted"> · {{ g['note'] }}</span> }</span><span class="ph-badge" [class]="tone(g['status'] === 'accepted' ? 'approved' : g['status'])">{{ status(g['status']) }}</span></div>
                } @empty { <p class="ph-muted">{{ i18n.t('g.none') }}</p> }
                <h3 style="margin-top: 10px">{{ i18n.t('g.actions') }}</h3>
                <div class="g-acts">
                  @if (l['status'] === 'under_review' && can('recommend_loans')) {
                    <button type="button" class="btn-primary is-success ph-btn" (click)="recommend(l)" data-testid="g-l-recommend">{{ i18n.t('g.l.recommend') }}</button>
                  }
                  @if (l['status'] === 'recommended' && can('approve_loans')) {
                    <button type="button" class="btn-primary is-success ph-btn" (click)="approve(l)" data-testid="g-l-approve">{{ i18n.t('g.approve') }}</button>
                  }
                  @if ((l['status'] === 'under_review' || l['status'] === 'recommended') && can('approve_loans', 'recommend_loans')) {
                    <button type="button" class="btn-primary is-danger ph-btn" (click)="reject(l)" data-testid="g-l-reject">{{ i18n.t('g.turn.down') }}</button>
                  }
                  @if (l['status'] === 'approved' && can('record_payouts')) {
                    <button type="button" class="btn-primary is-warn ph-btn" (click)="payOut.set(l)" data-testid="g-l-disburse">{{ i18n.t('g.l.pay.out') }}</button>
                  }
                </div>
              </section>
            </div>
            @let sched = l['position']?.['instalments'] ?? l['preview']?.['instalments'] ?? [];
            @if (sched.length) {
              <div class="ph-card">
                <h3>{{ l['position'] ? i18n.t('g.l.schedule') : i18n.t('g.l.preview') }}</h3>
                <div class="g-table">
                  <div class="g-tr g-th"><span>#</span><span>{{ i18n.t('g.l.due') }}</span><span>{{ i18n.t('g.l.principal') }}</span><span>{{ i18n.t('g.l.interest') }}</span><span>{{ i18n.t('g.paid') }}</span><span>{{ i18n.t('g.l.left') }}</span></div>
                  @for (i of sched; track i['number']) {
                    <div class="g-tr"><span>{{ i['number'] }}</span><span>{{ day(i['due_date']) }}</span><span>{{ tsh(i['principal_due']) }}</span><span>{{ tsh(i['interest_due']) }}</span>
                      <span>{{ tsh(i['paid'] ?? 0) }}</span><span [class]="i['state'] === 'overdue' ? 'ph-bad' : i['state'] === 'paid' ? 'ph-good' : ''">{{ i['left'] !== undefined ? tsh(i['left']) : '—' }}</span></div>
                  }
                </div>
                @if (l['preview']; as pv) { <p class="ph-muted">{{ i18n.t('g.l.total', tsh(pv['total']), tsh(pv['total_interest'])) }}</p> }
              </div>
            }
          </div>
        }
      </div>
      <div slot="footer" class="flex gap-2"><button type="button" class="btn-outline ph-btn" (click)="loan.set(null)">{{ i18n.t('common.close') }}</button></div>
    </app-modal-dialog>

    <!-- pay a loan out -->
    <app-modal-dialog [show]="!!payOut()" [eyebrow]="payOut()?.['member_name'] ?? ''" [title]="i18n.t('g.l.pay.out')" size="sm" variant="danger" (close)="payOut.set(null)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <p><b>{{ tsh(payOut()?.['amount_approved'] ?? 0) }}</b></p>
        <label class="ph-field">{{ i18n.t('g.method') }}<select class="modal-input" [(ngModel)]="payMethod" name="pm">@for (m of methods; track m) { <option [value]="m">{{ method(m) }}</option> }</select></label>
        @if (payMethod !== 'cash') { <label class="ph-field">{{ i18n.t('g.ref') }}<input class="modal-input" [(ngModel)]="payRef" name="pr" /></label> }
        <p class="ph-muted">{{ i18n.t('g.p.waits') }}</p>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="payOut.set(null)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-warn ph-btn" [disabled]="busy()" (click)="disburse()" data-testid="g-l-disburse-save">{{ i18n.t('g.l.pay.out') }}</button>
      </div>
    </app-modal-dialog>

    <!-- the projects committee's recommendation -->
    <app-modal-dialog [show]="!!recommending()" [eyebrow]="recommending()?.['member_name'] ?? ''" [title]="i18n.t('g.l.recommend')" size="sm" (close)="recommending.set(null)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <p class="ph-muted">{{ i18n.t('g.l.asked') }}: {{ tsh(recommending()?.['amount_requested'] ?? 0) }}@if (recommending()?.['ceiling'] !== null) { · {{ i18n.t('g.l.ceiling') }}: {{ tsh(recommending()?.['ceiling'] ?? 0) }} }</p>
        <label class="ph-field">{{ i18n.t('g.l.recommend.amount') }}<input class="modal-input" inputmode="numeric" [(ngModel)]="rAmount" name="ra" data-testid="g-lr-amount" /></label>
        <label class="ph-field">{{ i18n.t('g.reason') }} *<textarea class="modal-input" rows="2" [(ngModel)]="rNote" name="rn" data-testid="g-lr-note"></textarea></label>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="recommending.set(null)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-success ph-btn" [disabled]="busy()" (click)="saveRecommendation()" data-testid="g-lr-save">{{ i18n.t('g.l.recommend') }}</button>
      </div>
    </app-modal-dialog>

    <!-- an application for a member -->
    <app-modal-dialog [show]="applyOpen()" [eyebrow]="i18n.t('nav.g.loans')" [title]="i18n.t('g.l.apply')" size="md" (close)="applyOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <app-g-member-pick [value]="borrower()" (picked$)="borrower.set($event)" />
        <label class="ph-field">{{ i18n.t('g.amount') }} *<input class="modal-input" inputmode="numeric" [(ngModel)]="aAmount" name="aa" data-testid="g-la-amount" /></label>
        <label class="ph-field">{{ i18n.t('g.l.purpose') }} *<input class="modal-input" [(ngModel)]="aPurpose" name="ap" data-testid="g-la-purpose" /></label>
        <label class="ph-field">{{ i18n.t('g.l.months') }} *<input class="modal-input" type="number" min="1" max="120" [(ngModel)]="aMonths" name="am" /></label>
        <p class="ph-field">{{ i18n.t('g.l.guarantors') }}</p>
        @for (g of guarantors(); track g.id) {
          <div class="ph-row ph-card" style="padding: 6px 12px"><span>{{ g.name }}</span><button type="button" class="link-btn danger" (click)="dropGuarantor(g.id)">{{ i18n.t('common.delete') }}</button></div>
        }
        @if (guarantors().length < 5) { <app-g-member-pick [label]="i18n.t('g.l.add.guarantor')" [value]="null" (picked$)="addGuarantor($event)" /> }
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="applyOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary ph-btn" [disabled]="busy()" (click)="apply()" data-testid="g-la-save">{{ i18n.t('g.l.send') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [
    `
      .g-acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
      .g-table { display: grid; gap: 2px; margin-top: 6px; font-size: 13px; overflow-x: auto; }
      .g-tr { display: grid; grid-template-columns: 40px repeat(5, minmax(90px, 1fr)); gap: 8px; padding: 4px 0; border-bottom: 1px solid rgba(255, 255, 255, 0.08); }
      .g-th { font-weight: 900; opacity: 0.8; }
    `,
  ],
})
export class GLoansPage extends GBase implements OnInit {
  protected readonly statuses = STATUSES;
  protected readonly filter = signal('open');
  protected readonly rows = signal<Row[]>([]);
  protected readonly page = signal(1);
  protected readonly more = signal(false);
  protected readonly total = signal(0);
  protected readonly error = signal('');

  protected readonly loan = signal<Row | null>(null);
  protected readonly payOut = signal<Row | null>(null);
  protected readonly recommending = signal<Row | null>(null);
  protected rAmount = '';
  protected rNote = '';
  protected payMethod = 'cash';
  protected payRef = '';

  protected readonly applyOpen = signal(false);
  protected readonly borrower = signal<PickedMember | null>(null);
  protected readonly guarantors = signal<PickedMember[]>([]);
  protected aAmount = '';
  protected aPurpose = '';
  protected aMonths: number | string = 6;

  protected readonly keys = ['member_name', 'member_number', 'reference', 'purpose'];

  protected shownCount(): number {
    return this.find().trim() ? this.filtered(this.rows(), this.keys).length : this.total();
  }

  ngOnInit(): void {
    void this.load(1);
  }

  async load(page: number): Promise<void> {
    this.error.set('');
    try {
      const p = await this.api.page('/loans', 'loans', { status: this.filter() || null, page });
      this.rows.set(p.items);
      this.page.set(p.page);
      this.more.set(p.hasMore);
      this.total.set(p.total);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  protected menuFor(l: Row): MenuItem[] {
    const items: MenuItem[] = [{ id: 'open', label: this.i18n.t('g.open'), testid: 'g-l-open-' + l['id'] }];
    if (l['status'] === 'under_review' && this.can('recommend_loans')) items.push({ id: 'recommend', label: this.i18n.t('g.l.recommend'), primary: true });
    if (l['status'] === 'recommended' && this.can('approve_loans')) items.push({ id: 'approve', label: this.i18n.t('g.approve'), primary: true });
    if ((l['status'] === 'under_review' || l['status'] === 'recommended') && this.can('approve_loans', 'recommend_loans')) items.push({ id: 'reject', label: this.i18n.t('g.turn.down'), danger: true });
    if (l['status'] === 'approved' && this.can('record_payouts')) items.push({ id: 'payout', label: this.i18n.t('g.l.pay.out') });
    return items;
  }

  protected picked(id: string, l: Row): void {
    switch (id) {
      case 'open': void this.open(Number(l['id'])); break;
      case 'recommend': this.recommend(l); break;
      case 'approve': void this.approve(l); break;
      case 'reject': void this.reject(l); break;
      case 'payout': this.payOut.set(l); break;
    }
  }

  protected recommendation(l: Row): string {
    const r = l['recommendation'];
    if (!r) return '';
    if (typeof r === 'string') return r;
    return [r['amount'] !== undefined ? this.tsh(Number(r['amount'])) : '', r['note'] ?? '', r['by_name'] ?? ''].filter((x) => !!x).join(' · ');
  }

  protected async open(id: number): Promise<void> {
    try {
      this.loan.set((await this.api.get(`/loans/${id}`))['loan'] ?? null);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  private async refresh(l: Row): Promise<void> {
    await Promise.all([this.open(Number(l['id'])), this.load(this.page()), this.ctx.reload()]);
  }

  protected recommend(l: Row): void {
    this.rAmount = String(l['amount_requested'] ?? '');
    this.rNote = '';
    this.recommending.set(l);
  }

  protected async saveRecommendation(): Promise<void> {
    const l = this.recommending();
    if (!l) return;
    const amount = this.amount(this.rAmount);
    if (amount < 1) return this.stop(this.i18n.t('g.need.amount'));
    if (this.rNote.trim().length < 3) return this.stop(this.i18n.t('g.need.reason'));
    if (await this.act(() => this.api.post(`/loans/${l['id']}/recommend`, { amount, note: this.rNote.trim() }), this.i18n.t('g.saved'))) {
      this.recommending.set(null);
      await this.refresh(l);
    }
  }

  protected async approve(l: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.approve'), `${l['member_name']} · ${this.tsh(l['amount_approved'] ?? l['amount_requested'])}`, this.i18n.t('g.approve')))) return;
    if (await this.act(() => this.api.post(`/loans/${l['id']}/approve`), this.i18n.t('g.saved'))) await this.refresh(l);
  }

  protected async reject(l: Row): Promise<void> {
    const why = await this.reason(this.i18n.t('g.turn.down'), this.i18n.t('g.l.reject.why'), this.i18n.t('g.turn.down'));
    if (why === null) return;
    if (await this.act(() => this.api.post(`/loans/${l['id']}/reject`, { reason: why }), this.i18n.t('g.saved'))) await this.refresh(l);
  }

  protected async disburse(): Promise<void> {
    const l = this.payOut();
    if (!l) return;
    const body: Row = { method: this.payMethod, ...(this.payRef.trim() ? { external_ref: this.payRef.trim() } : {}) };
    if (await this.act(() => this.api.post(`/loans/${l['id']}/disburse`, body), this.i18n.t('g.l.paid.waits'))) {
      this.payOut.set(null);
      this.payRef = '';
      await this.refresh(l);
    }
  }

  protected openApply(): void {
    this.borrower.set(null);
    this.guarantors.set([]);
    this.aAmount = '';
    this.aPurpose = '';
    this.aMonths = 6;
    this.applyOpen.set(true);
  }

  protected addGuarantor(m: PickedMember | null): void {
    if (!m || this.guarantors().some((g) => g.id === m.id) || this.borrower()?.id === m.id) return;
    this.guarantors.set([...this.guarantors(), m]);
  }

  protected dropGuarantor(id: number): void {
    this.guarantors.set(this.guarantors().filter((g) => g.id !== id));
  }

  protected async apply(): Promise<void> {
    const b = this.borrower();
    const amount = this.amount(this.aAmount);
    if (!b) return this.stop(this.i18n.t('g.need.member'));
    if (amount < 1000) return this.stop(this.i18n.t('g.need.amount'));
    if (this.aPurpose.trim().length < 3) return this.stop(this.i18n.t('g.need.purpose'));
    const body: Row = { member_id: b.id, amount, purpose: this.aPurpose.trim(), term_months: Number(this.aMonths) || 1, guarantor_ids: this.guarantors().map((g) => g.id) };
    if (await this.act(() => this.api.post('/loans', body), this.i18n.t('g.l.sent'))) {
      this.applyOpen.set(false);
      await this.load(1);
    }
  }
}
