import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';

const STATUSES = ['submitted', 'approved', 'rejected', 'cancelled', ''];

/**
 * Welfare (msaada): the members' requests for help (a funeral, an illness, a wedding ...) and the chair's decision with the amount, the
 * treasurer's payout (verified by someone else), and the kinds of help the group gives.
 */
@Component({
  selector: 'app-g-welfare',
  imports: [RowMenuComponent, FormsModule, ModalDialogComponent],
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
        <div class="table-scroll-container fit-page" data-testid="g-w-list">
          <table class="grid-table">
            <thead>
              <tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('g.ref') }}</th>
              <th>{{ i18n.t('g.member') }}</th>
              <th>{{ i18n.t('g.kind') }}</th>
              <th>{{ i18n.t('g.w.beneficiary') }}</th>
              <th>{{ i18n.t('g.w.relationship') }}</th>
              <th>{{ i18n.t('g.w.event.date') }}</th>
              <th class="text-right">{{ i18n.t('g.l.asked') }}</th>
              <th class="text-right">{{ i18n.t('g.l.approved') }}</th>
              <th>{{ i18n.t('g.status') }}</th>
              <th>{{ i18n.t('g.note') }}</th>
              <th class="text-right">{{ i18n.t('g.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              @for (r of rows(); track r['id']) {
                <tr>
                  <td class="no-col">{{ $index + 1 }}</td>
                  <td>{{ r['reference'] }}</td>
                  <td class="font-bold">{{ r['member_name'] }}</td>
                  <td>{{ r['type_name'] }}</td>
                  <td>{{ r['beneficiary'] }}</td>
                  <td>{{ i18n.t('g.rel.' + r['relationship']) }}</td>
                  <td>{{ day(r['event_date']) }}</td>
                  <td class="text-right">{{ r['amount_requested'] ? tsh(r['amount_requested']) : '—' }}</td>
                  <td class="text-right">{{ r['amount_approved'] ? tsh(r['amount_approved']) : '—' }}</td>
                  <td><span class="ph-badge" [class]="tone(r['state'])">{{ status(r['state']) }}</span></td>
                  <td>{{ r['decision_note'] || r['description'] || '—' }}</td>
                  <td class="text-right">@if (menuFor(r).length) { <app-row-menu [items]="menuFor(r)" [testid]="'g-w-menu-' + r['id']" (picked)="picked($event, r)" /> } @else { — }</td>
                </tr>
              } @empty {
                <tr><td colspan="12" class="ph-muted">{{ i18n.t('g.w.none') }}</td></tr>
              }
            </tbody>
          </table>
        </div>
      } @else {
        @if (can('manage_settings')) {
          <div class="ph-row"><span></span><button type="button" class="btn-primary ph-btn" (click)="openType(null)" data-testid="g-w-type-new">{{ i18n.t('g.w.type.new') }}</button></div>
        }
        <div class="table-scroll-container fit-page">
          <table class="grid-table">
            <thead>
              <tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('g.name') }}</th>
              <th class="text-right">{{ i18n.t('g.w.usual.amount') }}</th>
              <th>{{ i18n.t('g.description') }}</th>
              <th>{{ i18n.t('g.status') }}</th>
              <th class="text-right">{{ i18n.t('g.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              @for (t of types(); track t['id']) {
                <tr>
                  <td class="no-col">{{ $index + 1 }}</td>
                  <td class="font-bold">{{ t['name'] }}</td>
                  <td class="text-right">{{ t['amount'] ? tsh(t['amount']) : i18n.t('g.w.decided') }}</td>
                  <td>{{ t['description'] || '—' }}</td>
                  <td><span class="ph-badge" [class]="t['active'] ? 'ph-good' : 'ph-bad'">{{ t['active'] ? i18n.t('g.running') : i18n.t('g.stopped') }}</span></td>
                  <td class="text-right">@if ((can('manage_settings') ? [{ id: 'edit', label: i18n.t('g.edit') }] : []).length) { <app-row-menu [items]="(can('manage_settings') ? [{ id: 'edit', label: i18n.t('g.edit') }] : [])" [testid]="'g-w-type-menu-' + t['id']" (picked)="openType(t)" /> } @else { — }</td>
                </tr>
              } @empty {
                <tr><td colspan="6" class="ph-muted">{{ i18n.t('g.w.types.none') }}</td></tr>
              }
            </tbody>
          </table>
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

  protected menuFor(r: Row): MenuItem[] {
    const items: MenuItem[] = [];
    if (r['state'] === 'submitted' && this.can('approve_benefits')) {
      items.push({ id: 'approve', label: this.i18n.t('g.approve'), primary: true, testid: 'g-w-approve-' + r['id'] });
      items.push({ id: 'reject', label: this.i18n.t('g.turn.down'), danger: true });
    }
    if (r['state'] === 'approved' && this.can('record_payouts')) items.push({ id: 'pay', label: this.i18n.t('g.pay'), testid: 'g-w-pay-' + r['id'] });
    return items;
  }

  protected picked(id: string, r: Row): void {
    if (id === 'approve') this.openDecide(r);
    if (id === 'reject') void this.turnDown(r);
    if (id === 'pay') this.openPay(r);
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
