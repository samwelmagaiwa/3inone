import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';

const STATUSES = ['requested', 'approved', 'rejected', 'cancelled', ''];
const CATEGORIES = ['project', 'office', 'meeting', 'transport', 'event', 'other'];

/**
 * The group's spending (matumizi): a leader asks (what for, who is paid, how much, maybe for a running project), the treasurer or chair
 * approves the amount asked or less, the treasurer pays it out, someone else verifies it. Nobody decides or pays their own request.
 */
@Component({
  selector: 'app-g-expenses',
  imports: [RowMenuComponent, FormsModule, ModalDialogComponent],
  template: `
    <div class="ad ph-page" data-testid="g-expenses">
      <div class="ph-row" style="flex-wrap: wrap">
        <div class="ph-chips">
          @for (s of statuses; track s) {
            <button type="button" class="pill-tab" [class.is-active]="filter() === s" (click)="filter.set(s); load()">{{ s ? status(s) : i18n.t('g.all') }}</button>
          }
        </div>
        @if (can('request_expenses')) { <button type="button" class="btn-primary ph-btn" (click)="openNew()" data-testid="g-e-new">{{ i18n.t('g.e.new') }}</button> }
      </div>
      @if (error()) { <section class="ph-card"><p>{{ error() }}</p></section> }
      <div class="table-scroll-container fit-page" data-testid="g-e-list">
          <table class="grid-table">
            <thead>
              <tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('g.ref') }}</th>
              <th>{{ i18n.t('g.date') }}</th>
              <th>{{ i18n.t('g.p.for.what') }}</th>
              <th>{{ i18n.t('g.kind') }}</th>
              <th>{{ i18n.t('g.payee') }}</th>
              <th>{{ i18n.t('g.e.project.short') }}</th>
              <th>{{ i18n.t('g.e.asked.by.short') }}</th>
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
                  <td>{{ day(r['created_at']) }}</td>
                  <td class="font-bold">{{ r['purpose'] }}</td>
                  <td>{{ i18n.t('g.e.cat.' + r['category']) }}</td>
                  <td>{{ r['payee'] }}</td>
                  <td>{{ r['project_title'] || '—' }}</td>
                  <td>{{ r['requested_by_name'] || '—' }}</td>
                  <td class="text-right">{{ tsh(r['amount']) }}</td>
                  <td class="text-right">{{ r['amount_approved'] ? tsh(r['amount_approved']) : '—' }}</td>
                  <td><span class="ph-badge" [class]="tone(r['state'])">{{ status(r['state']) }}</span></td>
                  <td>{{ r['decision_note'] || '—' }}</td>
                  <td class="text-right">@if (menuFor(r).length) { <app-row-menu [items]="menuFor(r)" [testid]="'g-e-menu-' + r['id']" (picked)="picked($event, r)" /> } @else { — }</td>
                </tr>
              } @empty {
                <tr><td colspan="13" class="ph-muted">{{ i18n.t('g.e.none') }}</td></tr>
              }
            </tbody>
          </table>
        </div>
    </div>

    <app-modal-dialog [show]="newOpen()" [eyebrow]="i18n.t('nav.g.expenses')" [title]="i18n.t('g.e.new')" size="md" (close)="newOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.p.for.what') }} *<input class="modal-input" [(ngModel)]="f['purpose']" name="fp" data-testid="g-ef-purpose" /></label>
        <label class="ph-field">{{ i18n.t('g.kind') }}<select class="modal-input" [(ngModel)]="f['category']" name="fc">@for (c of categories; track c) { <option [value]="c">{{ i18n.t('g.e.cat.' + c) }}</option> }</select></label>
        <label class="ph-field">{{ i18n.t('g.payee') }} *<input class="modal-input" [(ngModel)]="f['payee']" name="fpy" data-testid="g-ef-payee" /></label>
        <label class="ph-field">{{ i18n.t('g.amount') }} *<input class="modal-input" inputmode="numeric" [(ngModel)]="f['amount']" name="fa" data-testid="g-ef-amount" /></label>
        @if (projects().length) {
          <label class="ph-field">{{ i18n.t('g.e.project') }}<select class="modal-input" [(ngModel)]="f['project_id']" name="fpr">
            <option [ngValue]="null">—</option>@for (p of projects(); track p['id']) { <option [ngValue]="p['id']">{{ p['title'] }}</option> }</select></label>
        }
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="newOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary ph-btn" [disabled]="busy()" (click)="send()" data-testid="g-ef-save">{{ i18n.t('g.e.send') }}</button>
      </div>
    </app-modal-dialog>

    <app-modal-dialog [show]="!!paying()" [eyebrow]="paying()?.['payee'] ?? ''" [title]="i18n.t('g.pay')" size="sm" variant="danger" (close)="paying.set(null)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <p><b>{{ tsh(paying()?.['amount_approved'] ?? 0) }}</b> · {{ paying()?.['purpose'] }}</p>
        <label class="ph-field">{{ i18n.t('g.method') }}<select class="modal-input" [(ngModel)]="payMethod" name="pm">@for (m of methods; track m) { <option [value]="m">{{ method(m) }}</option> }</select></label>
        @if (payMethod !== 'cash') { <label class="ph-field">{{ i18n.t('g.ref') }}<input class="modal-input" [(ngModel)]="payRef" name="pr" /></label> }
        <p class="ph-muted">{{ i18n.t('g.p.waits') }}</p>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="paying.set(null)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-warn ph-btn" [disabled]="busy()" (click)="pay()">{{ i18n.t('g.pay') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [`.g-acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; } .g-acts:empty { display: none; }`],
})
export class GExpensesPage extends GBase implements OnInit {
  protected readonly statuses = STATUSES;
  protected readonly categories = CATEGORIES;
  protected readonly filter = signal('requested');
  protected readonly rows = signal<Row[]>([]);
  protected readonly projects = signal<Row[]>([]);
  protected readonly error = signal('');
  protected readonly newOpen = signal(false);
  protected f: Row = {};
  protected readonly paying = signal<Row | null>(null);
  protected payMethod = 'cash';
  protected payRef = '';

  ngOnInit(): void {
    void this.load();
  }

  protected menuFor(r: Row): MenuItem[] {
    const items: MenuItem[] = [];
    if (r['state'] === 'requested' && !r['mine'] && this.can('approve_expenses')) {
      items.push({ id: 'approve', label: this.i18n.t('g.approve'), primary: true, testid: 'g-e-approve-' + r['id'] });
      items.push({ id: 'reject', label: this.i18n.t('g.turn.down'), danger: true });
    }
    if (r['state'] === 'approved' && !r['mine'] && this.can('record_payouts')) items.push({ id: 'pay', label: this.i18n.t('g.pay'), testid: 'g-e-pay-' + r['id'] });
    if (r['state'] === 'requested' && r['mine']) items.push({ id: 'withdraw', label: this.i18n.t('g.e.withdraw'), danger: true });
    return items;
  }

  protected picked(id: string, r: Row): void {
    if (id === 'approve') void this.approve(r);
    if (id === 'reject') void this.turnDown(r);
    if (id === 'pay') this.openPay(r);
    if (id === 'withdraw') void this.cancel(r);
  }

  async load(): Promise<void> {
    this.error.set('');
    try {
      this.rows.set(((await this.api.get('/expenses', { status: this.filter() || null }))['requests'] as Row[]) ?? []);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  protected async openNew(): Promise<void> {
    this.f = { category: 'other', project_id: null, amount: '' };
    this.newOpen.set(true);
    try {
      this.projects.set(((await this.api.get('/projects', { status: 'active' }))['projects'] as Row[]) ?? []);
    } catch {
      this.projects.set([]);
    }
  }

  protected async send(): Promise<void> {
    const amount = this.amount(this.f['amount']);
    if (String(this.f['purpose'] ?? '').trim().length < 3) return this.stop(this.i18n.t('g.need.purpose'));
    if (String(this.f['payee'] ?? '').trim().length < 2) return this.stop(this.i18n.t('g.need.payee'));
    if (amount < 1) return this.stop(this.i18n.t('g.need.amount'));
    const body: Row = { purpose: String(this.f['purpose']).trim(), category: this.f['category'], payee: String(this.f['payee']).trim(), amount, ...(this.f['project_id'] ? { project_id: this.f['project_id'] } : {}) };
    if (await this.act(() => this.api.post('/expenses', body), this.i18n.t('g.e.sent'))) {
      this.newOpen.set(false);
      this.filter.set('requested');
      await this.load();
    }
  }

  protected async approve(r: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.approve'), `${r['purpose']} · ${r['payee']} · ${this.tsh(r['amount'])}`, this.i18n.t('g.approve')))) return;
    if (await this.act(() => this.api.post(`/expenses/${r['id']}/decide`, { approve: true }), this.i18n.t('g.saved'))) await Promise.all([this.load(), this.ctx.reload()]);
  }

  protected async turnDown(r: Row): Promise<void> {
    const why = await this.reason(this.i18n.t('g.turn.down'), `${r['purpose']} · ${this.tsh(r['amount'])}`, this.i18n.t('g.turn.down'));
    if (why === null) return;
    if (await this.act(() => this.api.post(`/expenses/${r['id']}/decide`, { approve: false, note: why }), this.i18n.t('g.saved'))) await Promise.all([this.load(), this.ctx.reload()]);
  }

  protected openPay(r: Row): void {
    this.payMethod = 'cash';
    this.payRef = '';
    this.paying.set(r);
  }

  protected async pay(): Promise<void> {
    const r = this.paying();
    if (!r) return;
    if (await this.act(() => this.api.post(`/expenses/${r['id']}/pay`, { method: this.payMethod, ...(this.payRef.trim() ? { external_ref: this.payRef.trim() } : {}) }), this.i18n.t('g.l.paid.waits'))) {
      this.paying.set(null);
      await this.load();
    }
  }

  protected async cancel(r: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.e.withdraw'), `${r['purpose']} · ${this.tsh(r['amount'])}`, this.i18n.t('g.e.withdraw'), true))) return;
    if (await this.act(() => this.api.post(`/expenses/${r['id']}/cancel`), this.i18n.t('g.saved'))) await this.load();
  }
}
