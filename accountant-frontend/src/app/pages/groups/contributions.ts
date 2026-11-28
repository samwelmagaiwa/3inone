import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { monthKey } from '../../core/format';
import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';

type Tab = 'owing' | 'types' | 'promises';
const STATES = ['owing', 'overdue', 'paid', 'exempt', 'all'];
const FREQUENCIES = ['monthly', 'one_time', 'event'];

/**
 * Contributions: what every member owes and has paid (with udhuru, an excuse, given by whoever may and always with a reason), the kinds
 * of contribution the group has (monthly, once, or for an event) and calling them, and the promises members made to pay.
 */
@Component({
  selector: 'app-g-contributions',
  imports: [RowMenuComponent, FormsModule, ModalDialogComponent],
  template: `
    <div class="ad ph-page" data-testid="g-contributions">
      <div class="g-toolbar" data-testid="g-c-toolbar">
        <div class="ph-chips g-seg">
          <button type="button" class="pill-tab" [class.is-active]="tab() === 'owing'" (click)="go('owing')" data-testid="g-c-tab-owing">{{ i18n.t('g.c.owing') }}</button>
          <button type="button" class="pill-tab" [class.is-active]="tab() === 'types'" (click)="go('types')" data-testid="g-c-tab-types">{{ i18n.t('g.c.types') }}</button>
          <button type="button" class="pill-tab" [class.is-active]="tab() === 'promises'" (click)="go('promises')" data-testid="g-c-tab-promises">{{ i18n.t('g.c.promises') }}</button>
        </div>
        @if (tab() === 'owing') {
          <span class="g-sep"></span>
          <div class="ph-chips g-seg">
            @for (s of states; track s) {
              <button type="button" class="pill-tab" [class.is-active]="state() === s" (click)="state.set(s); loadOwing(1)">{{ s === 'all' ? i18n.t('g.all') : status(s) }}</button>
            }
          </div>
          <input class="g-search" [ngModel]="q()" (ngModelChange)="q.set($event)" (keyup.enter)="loadOwing(1)" [placeholder]="i18n.t('g.pick.ph')" [attr.aria-label]="i18n.t('g.search')" />
          <select class="g-select" [ngModel]="typeId()" (ngModelChange)="typeId.set($event); loadOwing(1)" [attr.aria-label]="i18n.t('g.c.type')">
            <option [ngValue]="null">{{ i18n.t('g.c.all.types') }}</option>
            @for (t of types(); track t['id']) { <option [ngValue]="t['id']">{{ t['name'] }}</option> }
          </select>
          <button type="button" class="btn-outline ph-btn" (click)="loadOwing(1)">{{ i18n.t('ad.apply') }}</button>
          <span class="g-count">{{ i18n.t('g.count', total()) }}</span>
        }
        @if (tab() !== 'owing') {
        <input class="g-search" [ngModel]="find()" (ngModelChange)="find.set($event)" [placeholder]="i18n.t('g.find.ph')" [attr.aria-label]="i18n.t('g.search')" />
        <button type="button" class="btn-outline ph-btn" (click)="reload()">{{ i18n.t('ad.apply') }}</button>
          @if (tab() === 'types' && can('manage_contributions')) {
            <button type="button" class="btn-primary ph-btn" (click)="openType(null)" data-testid="g-c-type-new">{{ i18n.t('g.c.type.new') }}</button>
          }
        <span class="g-count">{{ i18n.t('g.count', shownCount()) }}</span>
        }
      </div>

      @if (error()) {
        <section class="ph-card"><p>{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="reload()">{{ i18n.t('pl.retry') }}</button></section>
      }

      @switch (tab()) {
        @case ('owing') {
          <div class="table-scroll-container fit-page" data-testid="g-c-owing">
            <table class="grid-table g-grid">
              <thead>
                <tr>
                <th class="no-col">#</th>
                <th>{{ i18n.t('g.member') }}</th>
                <th>{{ i18n.t('g.number') }}</th>
                <th>{{ i18n.t('g.c.type') }}</th>
                <th>{{ i18n.t('g.c.period') }}</th>
                <th>{{ i18n.t('g.c.due.date') }}</th>
                <th class="text-right">{{ i18n.t('g.c.amount.due') }}</th>
                <th class="text-right">{{ i18n.t('g.paid') }}</th>
                <th class="text-right">{{ i18n.t('g.l.left') }}</th>
                <th>{{ i18n.t('g.status') }}</th>
                <th>{{ i18n.t('g.note') }}</th>
                <th class="text-right">{{ i18n.t('g.actions') }}</th>
                </tr>
              </thead>
              <tbody>
                @for (o of owing(); track o['id']) {
                  <tr>
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td class="font-bold g-long" [title]="o['member_name']">{{ o['member_name'] }}</td>
                    <td>{{ o['member_number'] || '—' }}</td>
                    <td class="g-long" [title]="o['label'] || o['type_name']">{{ o['label'] || o['type_name'] }}</td>
                    <td>{{ o['period'] || '—' }}</td>
                    <td [class.ph-bad]="o['days_overdue'] > 0" [title]="o['days_overdue'] > 0 ? i18n.t('g.c.late.days', o['days_overdue']) : ''">{{ day(o['due_date']) }}</td>
                    <td class="text-right">{{ tsh(o['amount_due']) }}</td>
                    <td class="text-right">{{ tsh(o['paid']) }}</td>
                    <td class="text-right"><b [class.ph-bad]="o['remaining'] > 0">{{ tsh(o['remaining']) }}</b></td>
                    <td><span class="ph-badge" [class]="tone(o['state'])">{{ status(o['state']) }}</span></td>
                    <td class="g-long" [title]="o['exempt_reason'] || '—'">{{ o['exempt_reason'] || '—' }}</td>
                    <td class="text-right"><app-row-menu [items]="orNone(owingMenu(o))" [testid]="'g-c-menu-' + o['id']" (picked)="owingPicked($event, o)" /></td>
                  </tr>
                } @empty {
                  <tr><td colspan="12" class="ph-muted">{{ i18n.t('g.c.none') }}</td></tr>
                }
              </tbody>
            </table>
          </div>
          <div class="ph-row">
            <button type="button" class="btn-outline ph-btn" [disabled]="page() <= 1" (click)="loadOwing(page() - 1)">{{ i18n.t('g.prev') }}</button>
            <span class="ph-muted">{{ i18n.t('g.page', page()) }}</span>
            <button type="button" class="btn-outline ph-btn" [disabled]="!more()" (click)="loadOwing(page() + 1)">{{ i18n.t('g.next') }}</button>
          </div>
        }
        @case ('types') {
          <div class="table-scroll-container fit-page" data-testid="g-c-types">
            <table class="grid-table g-grid">
              <thead>
                <tr>
                <th class="no-col">#</th>
                <th>{{ i18n.t('g.name') }}</th>
                <th class="text-right">{{ i18n.t('g.c.amount.each') }}</th>
                <th>{{ i18n.t('g.c.frequency') }}</th>
                <th>{{ i18n.t('g.c.due.day.short') }}</th>
                <th>{{ i18n.t('g.c.mandatory') }}</th>
                <th>{{ i18n.t('g.c.refundable') }}</th>
                <th>{{ i18n.t('g.status') }}</th>
                <th>{{ i18n.t('g.description') }}</th>
                <th class="text-right">{{ i18n.t('g.actions') }}</th>
                </tr>
              </thead>
              <tbody>
                @for (t of filtered(types(), typeKeys); track t['id']) {
                  <tr>
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td class="font-bold g-long" [title]="t['name']">{{ t['name'] }}</td>
                    <td class="text-right">{{ tsh(t['amount']) }}</td>
                    <td>{{ i18n.t('g.freq.' + t['frequency']) }}</td>
                    <td>{{ t['frequency'] === 'monthly' ? t['due_day'] : '—' }}</td>
                    <td>{{ t['mandatory'] ? i18n.t('g.yes') : i18n.t('g.no') }}</td>
                    <td [class.ph-good]="t['refundable']">{{ t['refundable'] ? i18n.t('g.yes') : i18n.t('g.no') }}</td>
                    <td><span class="ph-badge" [class]="t['active'] ? 'ph-good' : 'ph-bad'">{{ t['active'] ? i18n.t('g.running') : i18n.t('g.stopped') }}</span></td>
                    <td class="g-long" [title]="t['description'] || '—'">{{ t['description'] || '—' }}</td>
                    <td class="text-right"><app-row-menu [items]="orNone(typeMenu(t))" [testid]="'g-c-type-menu-' + t['id']" (picked)="typePicked($event, t)" /></td>
                  </tr>
                } @empty {
                  <tr><td colspan="10" class="ph-muted">{{ i18n.t('g.c.types.none') }}</td></tr>
                }
              </tbody>
            </table>
          </div>
        }
        @case ('promises') {
          <div class="table-scroll-container fit-page" data-testid="g-c-promises">
            <table class="grid-table g-grid">
              <thead>
                <tr>
                <th class="no-col">#</th>
                <th>{{ i18n.t('g.member') }}</th>
                <th>{{ i18n.t('g.c.for') }}</th>
                <th class="text-right">{{ i18n.t('g.amount') }}</th>
                <th>{{ i18n.t('g.c.promise.day') }}</th>
                <th>{{ i18n.t('g.note') }}</th>
                <th>{{ i18n.t('g.status') }}</th>
                <th class="text-right">{{ i18n.t('g.actions') }}</th>
                </tr>
              </thead>
              <tbody>
                @for (p of filtered(promises(), promiseKeys); track p['id']) {
                  <tr>
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td class="font-bold g-long" [title]="p['member_name']">{{ p['member_name'] }}</td>
                    <td>{{ p['obligation_label'] || i18n.t('g.c.any') }}</td>
                    <td class="text-right">{{ tsh(p['amount']) }}</td>
                    <td>{{ day(p['promised_on']) }}</td>
                    <td class="g-long" [title]="p['note'] || '—'">{{ p['note'] || '—' }}</td>
                    <td><span class="ph-badge" [class]="tone(p['state'])">{{ status(p['state']) }}</span></td>
                    <td class="text-right"><app-row-menu [items]="orNone(promiseMenu(p))" [testid]="'g-c-promise-menu-' + p['id']" (picked)="cancelPromise(p)" /></td>
                  </tr>
                } @empty {
                  <tr><td colspan="8" class="ph-muted">{{ i18n.t('g.c.promises.none') }}</td></tr>
                }
              </tbody>
            </table>
          </div>
        }
      }
    </div>

    <!-- a kind of contribution -->
    <app-modal-dialog [show]="typeOpen()" [eyebrow]="i18n.t('nav.g.contributions')" [title]="tf['id'] ? i18n.t('g.edit') : i18n.t('g.c.type.new')" size="md" (close)="typeOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.name') }} *<input class="modal-input" [(ngModel)]="tf['name']" name="tn" [placeholder]="i18n.t('g.c.name.ph')" data-testid="g-ct-name" /></label>
        <label class="ph-field">{{ i18n.t('g.c.amount.each') }} *<input class="modal-input" inputmode="numeric" [(ngModel)]="tf['amount']" name="ta" data-testid="g-ct-amount" /></label>
        <label class="ph-field">{{ i18n.t('g.c.frequency') }}
          <select class="modal-input" [(ngModel)]="tf['frequency']" name="tfq">@for (f of frequencies; track f) { <option [value]="f">{{ i18n.t('g.freq.' + f) }}</option> }</select></label>
        @if (tf['frequency'] === 'monthly') {
          <label class="ph-field">{{ i18n.t('g.c.due.day') }}<input class="modal-input" type="number" min="1" max="31" [(ngModel)]="tf['due_day']" name="td" /></label>
        }
        <label class="ph-field">{{ i18n.t('g.description') }}<input class="modal-input" [(ngModel)]="tf['description']" name="tds" /></label>
        <label class="ph-row"><span>{{ i18n.t('g.c.mandatory') }}</span><input type="checkbox" [(ngModel)]="tf['mandatory']" name="tm" /></label>
        <label class="ph-row" [title]="i18n.t('g.c.refundable.hint')"><span>{{ i18n.t('g.c.refundable') }}</span><input type="checkbox" [(ngModel)]="tf['refundable']" name="trf" data-testid="g-c-refundable" /></label>
        @if (tf['id']) { <label class="ph-row"><span>{{ i18n.t('g.running') }}</span><input type="checkbox" [(ngModel)]="tf['active']" name="tac" /></label> }
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="typeOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-success ph-btn" [disabled]="busy()" (click)="saveType()" data-testid="g-ct-save">{{ i18n.t('g.save') }}</button>
      </div>
    </app-modal-dialog>

    <!-- call a contribution -->
    <app-modal-dialog [show]="!!raising()" [eyebrow]="raising()?.['name'] ?? ''" [title]="i18n.t('g.c.raise')" size="sm" (close)="raising.set(null)">
      <div slot="body" class="ph-page" style="gap: 10px">
        @if (raising()?.['frequency'] === 'monthly') {
          <label class="ph-field">{{ i18n.t('g.month') }}<input class="modal-input" type="month" [(ngModel)]="raiseMonth" name="rm" data-testid="g-cr-month" /></label>
          <p class="ph-muted">{{ i18n.t('g.c.raise.month.hint') }}</p>
        } @else {
          <label class="ph-field">{{ i18n.t('g.c.due.date') }}<input class="modal-input" type="date" [(ngModel)]="raiseDue" name="rd" /></label>
          @if (raising()?.['frequency'] === 'event') {
            <label class="ph-field">{{ i18n.t('g.c.event.for') }}<input class="modal-input" [(ngModel)]="raiseLabel" name="rl" [placeholder]="i18n.t('g.c.event.ph')" /></label>
          }
        }
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="raising.set(null)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-success ph-btn" [disabled]="busy()" (click)="raise()" data-testid="g-cr-save">{{ i18n.t('g.c.raise') }}</button>
      </div>
    </app-modal-dialog>

    <!-- a member's promise -->
    <app-modal-dialog [show]="!!promising()" [eyebrow]="promising()?.['member_name'] ?? ''" [title]="i18n.t('g.c.promise')" size="sm" (close)="promising.set(null)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.amount') }}<input class="modal-input" inputmode="numeric" [(ngModel)]="pAmount" name="pa" /></label>
        <label class="ph-field">{{ i18n.t('g.c.promise.day') }}<input class="modal-input" type="date" [(ngModel)]="pDay" [min]="today()" name="pd" /></label>
        <label class="ph-field">{{ i18n.t('g.note') }}<input class="modal-input" [(ngModel)]="pNote" name="pn" /></label>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="promising.set(null)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary ph-btn" [disabled]="busy()" (click)="savePromise()">{{ i18n.t('g.save') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [`.g-acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }`],
})
export class GContributionsPage extends GBase implements OnInit {
  protected readonly states = STATES;
  protected readonly frequencies = FREQUENCIES;
  protected readonly tab = signal<Tab>('owing');
  protected readonly error = signal('');

  protected readonly state = signal('owing');
  protected readonly q = signal('');
  protected readonly typeId = signal<number | null>(null);
  protected readonly owing = signal<Row[]>([]);
  protected readonly page = signal(1);
  protected readonly more = signal(false);
  protected readonly total = signal(0);
  protected readonly types = signal<Row[]>([]);
  protected readonly promises = signal<Row[]>([]);

  protected readonly typeOpen = signal(false);
  protected tf: Row = {};
  protected readonly raising = signal<Row | null>(null);
  protected raiseMonth = monthKey(new Date());
  protected raiseDue = '';
  protected raiseLabel = '';
  protected readonly promising = signal<Row | null>(null);
  protected pAmount = '';
  protected pDay = '';
  protected pNote = '';

  protected readonly typeKeys = ['name', 'description'];
  protected readonly promiseKeys = ['member_name', 'obligation_label', 'note'];

  protected shownCount(): number {
    return this.tab() === 'types' ? this.filtered(this.types(), this.typeKeys).length : this.filtered(this.promises(), this.promiseKeys).length;
  }

  ngOnInit(): void {
    void this.loadTypes();
    void this.loadOwing(1);
  }

  protected owingMenu(o: Row): MenuItem[] {
    if (!(o['remaining'] > 0) || o['state'] === 'exempt') return [];
    const items: MenuItem[] = [];
    if (this.can('grant_exemptions')) items.push({ id: 'exempt', label: this.i18n.t('g.c.exempt'), testid: 'g-c-exempt-' + o['id'] });
    if (this.can('record_payments')) items.push({ id: 'promise', label: this.i18n.t('g.c.promise') });
    return items;
  }

  protected owingPicked(id: string, o: Row): void {
    if (id === 'exempt') void this.exempt(o);
    if (id === 'promise') this.openPromise(o);
  }

  protected typeMenu(t: Row): MenuItem[] {
    if (!this.can('manage_contributions')) return [];
    const items: MenuItem[] = [{ id: 'edit', label: this.i18n.t('g.edit') }];
    if (t['active']) items.push({ id: 'raise', label: this.i18n.t('g.c.raise'), primary: true, testid: 'g-c-raise-' + t['id'] });
    return items;
  }

  protected typePicked(id: string, t: Row): void {
    if (id === 'edit') this.openType(t);
    if (id === 'raise') this.openRaise(t);
  }

  protected promiseMenu(p: Row): MenuItem[] {
    return (p['state'] === 'due' || p['state'] === 'open' || p['state'] === 'upcoming') && this.can('record_payments')
      ? [{ id: 'cancel', label: this.i18n.t('g.c.promise.cancel'), danger: true }]
      : [];
  }

  protected go(t: Tab): void {
    this.tab.set(t);
    void this.reload();
  }

  protected reload(): Promise<void> {
    switch (this.tab()) {
      case 'types': return this.loadTypes();
      case 'promises': return this.loadPromises();
      default: return this.loadOwing(this.page());
    }
  }

  async loadOwing(page: number): Promise<void> {
    this.error.set('');
    try {
      const p = await this.api.page('/obligations', 'obligations', { state: this.state(), type_id: this.typeId(), q: this.q() || null, page });
      this.owing.set(p.items);
      this.page.set(p.page);
      this.more.set(p.hasMore);
      this.total.set(p.total);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  async loadTypes(): Promise<void> {
    try {
      this.types.set(((await this.api.get('/contribution-types'))['types'] as Row[]) ?? []);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  async loadPromises(): Promise<void> {
    this.error.set('');
    try {
      this.promises.set(((await this.api.get('/promises'))['promises'] as Row[]) ?? []);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  protected async exempt(o: Row): Promise<void> {
    const why = await this.reason(this.i18n.t('g.c.exempt'), `${o['member_name']} · ${o['label'] || o['type_name']} · ${this.tsh(o['remaining'])}\n${this.i18n.t('g.c.exempt.why')}`, this.i18n.t('g.c.exempt'), false);
    if (why === null) return;
    if (await this.act(() => this.api.post(`/obligations/${o['id']}/exempt`, { reason: why }), this.i18n.t('g.saved'))) await this.loadOwing(this.page());
  }

  protected openType(t: Row | null): void {
    this.tf = t ? { ...t, amount: String(t['amount'] ?? '') } : { frequency: 'monthly', due_day: 5, mandatory: true, active: true, amount: '' };
    this.typeOpen.set(true);
  }

  protected async saveType(): Promise<void> {
    const amount = this.amount(this.tf['amount']);
    if (String(this.tf['name'] ?? '').trim().length < 2) return this.stop(this.i18n.t('g.need.name'));
    if (amount < 1) return this.stop(this.i18n.t('g.need.amount'));
    const body: Row = {
      name: String(this.tf['name']).trim(),
      amount,
      frequency: this.tf['frequency'],
      mandatory: !!this.tf['mandatory'],
      refundable: !!this.tf['refundable'],
      description: String(this.tf['description'] ?? '').trim() || null,
    };
    if (this.tf['frequency'] === 'monthly') body['due_day'] = Number(this.tf['due_day']) || 1;
    if (this.tf['id']) body['active'] = !!this.tf['active'];
    const id = this.tf['id'];
    if (await this.act(() => (id ? this.api.put(`/contribution-types/${id}`, body) : this.api.post('/contribution-types', body)), this.i18n.t('g.saved'))) {
      this.typeOpen.set(false);
      await this.loadTypes();
    }
  }

  protected openRaise(t: Row): void {
    this.raiseMonth = monthKey(new Date());
    this.raiseDue = this.today();
    this.raiseLabel = '';
    this.raising.set(t);
  }

  protected async raise(): Promise<void> {
    const t = this.raising();
    if (!t) return;
    const body: Row = t['frequency'] === 'monthly' ? { month: this.raiseMonth } : { due_date: this.raiseDue, ...(this.raiseLabel.trim() ? { label: this.raiseLabel.trim() } : {}) };
    if (t['frequency'] === 'event' && !this.raiseLabel.trim()) return this.stop(this.i18n.t('g.need.event'));
    let created = 0;
    if (await this.act(async () => (created = Number((await this.api.post(`/contribution-types/${t['id']}/raise`, body))['created'] ?? 0)))) {
      this.raising.set(null);
      this.done(this.i18n.t('g.c.raised', created));
      await this.loadOwing(1);
    }
  }

  protected openPromise(o: Row): void {
    this.pAmount = String(o['remaining'] ?? '');
    this.pDay = this.today();
    this.pNote = '';
    this.promising.set(o);
  }

  protected async savePromise(): Promise<void> {
    const o = this.promising();
    if (!o) return;
    const amount = this.amount(this.pAmount);
    if (amount < 1) return this.stop(this.i18n.t('g.need.amount'));
    const body: Row = { member_id: o['member_id'], obligation_id: o['id'], amount, promised_on: this.pDay || this.today(), ...(this.pNote.trim() ? { note: this.pNote.trim() } : {}) };
    if (await this.act(() => this.api.post('/promises', body), this.i18n.t('g.saved'))) this.promising.set(null);
  }

  protected async cancelPromise(p: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.c.promise.cancel'), `${p['member_name']} · ${this.tsh(p['amount'])}`, this.i18n.t('g.c.promise.cancel'), true))) return;
    if (await this.act(() => this.api.post(`/promises/${p['id']}/cancel`), this.i18n.t('g.saved'))) await this.loadPromises();
  }
}
