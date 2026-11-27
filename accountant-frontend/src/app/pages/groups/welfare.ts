import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { GBase } from './g-base';

const STATUSES = ['submitted', 'approved', 'rejected', 'cancelled', ''];

/**
 * Welfare (msaada): the members' requests for help (a funeral, an illness, a wedding ...) and the chair's decision with the amount, the
 * treasurer's payout (verified by someone else), and the kinds of help the group gives.
 */
@Component({
  selector: 'app-g-welfare',
  imports: [FormsModule, ModalDialogComponent],
  template: `
    <div class="ad ph-page" data-testid="g-welfare">
      <div class="ph-chips">
        <button type="button" class="pill-tab" [class.is-active]="tab() === 'requests'" (click)="tab.set('requests'); load()">{{ i18n.t('g.w.requests') }}</button>
        <button type="button" class="pill-tab" [class.is-active]="tab() === 'types'" (click)="tab.set('types'); loadTypes()" data-testid="g-w-tab-types">{{ i18n.t('g.w.types') }}</button>
      </div>
      @if (error()) { <section class="ph-card"><p>{{ error() }}</p></section> }

      @if (tab() === 'requests') {
        <div class="ph-chips">
          @for (s of statuses; track s) {
            <button type="button" class="pill-tab" [class.is-active]="filter() === s" (click)="filter.set(s); load()">{{ s ? status(s) : i18n.t('g.all') }}</button>
          }
        </div>
        <div class="ph-card ph-joined" data-testid="g-w-list">
          @for (r of rows(); track r['id']) {
            <section class="ph-sec">
              <div class="ph-row"><h3>{{ r['member_name'] }} <span class="ph-muted">{{ r['reference'] }}</span></h3><span class="ph-badge" [class]="tone(r['state'])">{{ status(r['state']) }}</span></div>
              <div class="ph-line"><span>{{ r['type_name'] }} · {{ r['beneficiary'] }} ({{ i18n.t('g.rel.' + r['relationship']) }})</span><span class="ph-muted">{{ day(r['event_date']) }}</span></div>
              @if (r['description']) { <p class="ph-muted">{{ r['description'] }}</p> }
              <div class="ph-line"><span>{{ i18n.t('g.l.asked') }} {{ r['amount_requested'] ? tsh(r['amount_requested']) : '—' }}</span>
                @if (r['amount_approved']) { <b class="ph-good">{{ i18n.t('g.l.approved') }} {{ tsh(r['amount_approved']) }}</b> }</div>
              @if (r['decision_note']) { <p class="ph-muted">{{ r['decision_note'] }}</p> }
              <div class="g-acts">
                @if (r['state'] === 'submitted' && can('approve_benefits')) {
                  <button type="button" class="btn-primary is-success ph-btn" (click)="openDecide(r)" [attr.data-testid]="'g-w-approve-' + r['id']">{{ i18n.t('g.approve') }}</button>
                  <button type="button" class="btn-primary is-danger ph-btn" (click)="turnDown(r)">{{ i18n.t('g.turn.down') }}</button>
                }
                @if (r['state'] === 'approved' && can('record_payouts')) {
                  <button type="button" class="btn-primary is-warn ph-btn" (click)="openPay(r)" [attr.data-testid]="'g-w-pay-' + r['id']">{{ i18n.t('g.pay') }}</button>
                }
              </div>
            </section>
          } @empty { <section class="ph-sec"><p class="ph-muted">{{ i18n.t('g.w.none') }}</p></section> }
        </div>
      } @else {
        @if (can('manage_settings')) {
          <div class="ph-row"><span></span><button type="button" class="btn-primary ph-btn" (click)="openType(null)" data-testid="g-w-type-new">{{ i18n.t('g.w.type.new') }}</button></div>
        }
        <div class="ph-card ph-joined">
          @for (t of types(); track t['id']) {
            <section class="ph-sec">
              <div class="ph-row"><h3>{{ t['name'] }}</h3><b class="ph-accent">{{ t['amount'] ? tsh(t['amount']) : i18n.t('g.w.decided') }}</b></div>
              <div class="ph-line"><span class="ph-muted">{{ t['description'] }}</span><span class="ph-badge" [class]="t['active'] ? 'ph-good' : 'ph-bad'">{{ t['active'] ? i18n.t('g.running') : i18n.t('g.stopped') }}</span></div>
              @if (can('manage_settings')) { <div class="g-acts"><button type="button" class="btn-outline ph-btn" (click)="openType(t)">{{ i18n.t('g.edit') }}</button></div> }
            </section>
          } @empty { <section class="ph-sec"><p class="ph-muted">{{ i18n.t('g.w.types.none') }}</p></section> }
        </div>
      }
    </div>

    <app-modal-dialog [show]="!!deciding()" [eyebrow]="deciding()?.['member_name'] ?? ''" [title]="i18n.t('g.approve')" size="sm" (close)="deciding.set(null)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.w.amount.given') }} *<input class="modal-input" inputmode="numeric" [(ngModel)]="dAmount" name="da" data-testid="g-wd-amount" /></label>
        <label class="ph-field">{{ i18n.t('g.note') }}<input class="modal-input" [(ngModel)]="dNote" name="dn" /></label>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="deciding.set(null)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-success ph-btn" [disabled]="busy()" (click)="approve()" data-testid="g-wd-save">{{ i18n.t('g.approve') }}</button>
      </div>
    </app-modal-dialog>

    <app-modal-dialog [show]="!!paying()" [eyebrow]="paying()?.['member_name'] ?? ''" [title]="i18n.t('g.pay')" size="sm" variant="danger" (close)="paying.set(null)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <p><b>{{ tsh(paying()?.['amount_approved'] ?? 0) }}</b></p>
        <label class="ph-field">{{ i18n.t('g.method') }}<select class="modal-input" [(ngModel)]="payMethod" name="pm">@for (m of methods; track m) { <option [value]="m">{{ method(m) }}</option> }</select></label>
        @if (payMethod !== 'cash') { <label class="ph-field">{{ i18n.t('g.ref') }}<input class="modal-input" [(ngModel)]="payRef" name="pr" /></label> }
        <p class="ph-muted">{{ i18n.t('g.p.waits') }}</p>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="paying.set(null)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-warn ph-btn" [disabled]="busy()" (click)="pay()">{{ i18n.t('g.pay') }}</button>
      </div>
    </app-modal-dialog>

    <app-modal-dialog [show]="typeOpen()" [eyebrow]="i18n.t('g.w.types')" [title]="tf['id'] ? i18n.t('g.edit') : i18n.t('g.w.type.new')" size="sm" (close)="typeOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.name') }} *<input class="modal-input" [(ngModel)]="tf['name']" name="tn" data-testid="g-wt-name" /></label>
        <label class="ph-field">{{ i18n.t('g.w.usual.amount') }}<input class="modal-input" inputmode="numeric" [(ngModel)]="tf['amount']" name="ta" /></label>
        <label class="ph-field">{{ i18n.t('g.description') }}<input class="modal-input" [(ngModel)]="tf['description']" name="td" /></label>
        @if (tf['id']) { <label class="ph-row"><span>{{ i18n.t('g.running') }}</span><input type="checkbox" [(ngModel)]="tf['active']" name="tac" /></label> }
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="typeOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-success ph-btn" [disabled]="busy()" (click)="saveType()" data-testid="g-wt-save">{{ i18n.t('g.save') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [`.g-acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; } .g-acts:empty { display: none; }`],
})
export class GWelfarePage extends GBase implements OnInit {
  protected readonly statuses = STATUSES;
  protected readonly tab = signal<'requests' | 'types'>('requests');
  protected readonly filter = signal('submitted');
  protected readonly rows = signal<Row[]>([]);
  protected readonly types = signal<Row[]>([]);
  protected readonly error = signal('');

  protected readonly deciding = signal<Row | null>(null);
  protected dAmount = '';
  protected dNote = '';
  protected readonly paying = signal<Row | null>(null);
  protected payMethod = 'cash';
  protected payRef = '';
  protected readonly typeOpen = signal(false);
  protected tf: Row = {};

  ngOnInit(): void {
    if (!this.can('view_benefits')) this.tab.set('types');
    void (this.tab() === 'types' ? this.loadTypes() : this.load());
  }

  async load(): Promise<void> {
    this.error.set('');
    try {
      this.rows.set(((await this.api.get('/benefits', { status: this.filter() || null }))['requests'] as Row[]) ?? []);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  async loadTypes(): Promise<void> {
    this.error.set('');
    try {
      this.types.set(((await this.api.get('/benefit-types'))['types'] as Row[]) ?? []);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  protected openDecide(r: Row): void {
    this.dAmount = String(r['amount_requested'] ?? '');
    this.dNote = '';
    this.deciding.set(r);
  }

  protected async approve(): Promise<void> {
    const r = this.deciding();
    if (!r) return;
    const amount = this.amount(this.dAmount);
    if (amount < 1) return this.stop(this.i18n.t('g.need.amount'));
    if (await this.act(() => this.api.post(`/benefits/${r['id']}/decide`, { approve: true, amount, ...(this.dNote.trim() ? { note: this.dNote.trim() } : {}) }), this.i18n.t('g.saved'))) {
      this.deciding.set(null);
      await Promise.all([this.load(), this.ctx.reload()]);
    }
  }

  protected async turnDown(r: Row): Promise<void> {
    const why = await this.reason(this.i18n.t('g.turn.down'), `${r['member_name']} · ${r['type_name']}`, this.i18n.t('g.turn.down'));
    if (why === null) return;
    if (await this.act(() => this.api.post(`/benefits/${r['id']}/decide`, { approve: false, note: why }), this.i18n.t('g.saved'))) await Promise.all([this.load(), this.ctx.reload()]);
  }

  protected openPay(r: Row): void {
    this.payMethod = 'cash';
    this.payRef = '';
    this.paying.set(r);
  }

  protected async pay(): Promise<void> {
    const r = this.paying();
    if (!r) return;
    if (await this.act(() => this.api.post(`/benefits/${r['id']}/pay`, { method: this.payMethod, ...(this.payRef.trim() ? { external_ref: this.payRef.trim() } : {}) }), this.i18n.t('g.l.paid.waits'))) {
      this.paying.set(null);
      await this.load();
    }
  }

  protected openType(t: Row | null): void {
    this.tf = t ? { ...t, amount: t['amount'] ? String(t['amount']) : '' } : { amount: '', active: true };
    this.typeOpen.set(true);
  }

  protected async saveType(): Promise<void> {
    if (String(this.tf['name'] ?? '').trim().length < 2) return this.stop(this.i18n.t('g.need.name'));
    const body: Row = { name: String(this.tf['name']).trim(), description: String(this.tf['description'] ?? '').trim() || null, amount: this.tf['amount'] ? this.amount(this.tf['amount']) : null };
    if (this.tf['id']) body['active'] = !!this.tf['active'];
    const id = this.tf['id'];
    if (await this.act(() => (id ? this.api.put(`/benefit-types/${id}`, body) : this.api.post('/benefit-types', body)), this.i18n.t('g.saved'))) {
      this.typeOpen.set(false);
      await this.loadTypes();
    }
  }
}
