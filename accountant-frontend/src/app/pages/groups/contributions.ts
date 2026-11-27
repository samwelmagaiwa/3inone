import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { monthKey } from '../../core/format';
import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
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
  imports: [FormsModule, ModalDialogComponent],
  template: `
    <div class="ad ph-page" data-testid="g-contributions">
      <div class="ph-chips">
        <button type="button" class="pill-tab" [class.is-active]="tab() === 'owing'" (click)="go('owing')" data-testid="g-c-tab-owing">{{ i18n.t('g.c.owing') }}</button>
        <button type="button" class="pill-tab" [class.is-active]="tab() === 'types'" (click)="go('types')" data-testid="g-c-tab-types">{{ i18n.t('g.c.types') }}</button>
        <button type="button" class="pill-tab" [class.is-active]="tab() === 'promises'" (click)="go('promises')" data-testid="g-c-tab-promises">{{ i18n.t('g.c.promises') }}</button>
      </div>

      @if (error()) {
        <section class="ph-card"><p>{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="reload()">{{ i18n.t('pl.retry') }}</button></section>
      }

      @switch (tab()) {
        @case ('owing') {
          <div class="ph-row" style="flex-wrap: wrap">
            <div class="ph-chips">
              @for (s of states; track s) {
                <button type="button" class="pill-tab" [class.is-active]="state() === s" (click)="state.set(s); loadOwing(1)">{{ s === 'all' ? i18n.t('g.all') : status(s) }}</button>
              }
            </div>
          </div>
          <div class="ph-row" style="flex-wrap: wrap">
            <label class="ph-field" style="flex: 2; min-width: 200px">{{ i18n.t('g.search') }}<input [ngModel]="q()" (ngModelChange)="q.set($event)" (keyup.enter)="loadOwing(1)" [placeholder]="i18n.t('g.pick.ph')" /></label>
            <label class="ph-field" style="flex: 1; min-width: 160px">{{ i18n.t('g.c.type') }}
              <select [ngModel]="typeId()" (ngModelChange)="typeId.set($event); loadOwing(1)">
                <option [ngValue]="null">{{ i18n.t('g.all') }}</option>
                @for (t of types(); track t['id']) { <option [ngValue]="t['id']">{{ t['name'] }}</option> }
              </select></label>
            <button type="button" class="btn-outline ph-btn" (click)="loadOwing(1)">{{ i18n.t('ad.apply') }}</button>
          </div>
          <p class="ph-muted">{{ i18n.t('g.count', total()) }}</p>
          <div class="ph-card ph-joined" data-testid="g-c-owing">
            @for (o of owing(); track o['id']) {
              <section class="ph-sec">
                <div class="ph-row"><h3>{{ o['member_name'] }} <span class="ph-muted">{{ o['member_number'] }}</span></h3>
                  <span class="ph-badge" [class]="tone(o['state'])">{{ status(o['state']) }}</span></div>
                <div class="ph-line"><span>{{ o['label'] || o['type_name'] }} @if (o['period']) { · {{ o['period'] }} }</span><b>{{ tsh(o['amount_due']) }}</b></div>
                <div class="ph-line"><span class="ph-muted">{{ i18n.t('g.c.due', day(o['due_date'])) }}@if (o['days_overdue'] > 0) { · {{ i18n.t('g.c.late.days', o['days_overdue']) }} }</span>
                  <span>{{ i18n.t('g.paid') }} {{ tsh(o['paid']) }} · <b [class.ph-bad]="o['remaining'] > 0">{{ i18n.t('g.p.left', tsh(o['remaining'])) }}</b></span></div>
                @if (o['exempt_reason']) { <p class="ph-muted">{{ i18n.t('g.c.excused', o['exempt_reason']) }}</p> }
                @if (o['remaining'] > 0 && o['state'] !== 'exempt') {
                  <div class="g-acts">
                    @if (can('grant_exemptions')) { <button type="button" class="btn-primary is-warn ph-btn" (click)="exempt(o)" [attr.data-testid]="'g-c-exempt-' + o['id']">{{ i18n.t('g.c.exempt') }}</button> }
                    @if (can('record_payments')) { <button type="button" class="btn-outline ph-btn" (click)="openPromise(o)">{{ i18n.t('g.c.promise') }}</button> }
                  </div>
                }
              </section>
            } @empty { <section class="ph-sec"><p class="ph-muted">{{ i18n.t('g.c.none') }}</p></section> }
          </div>
          <div class="ph-row">
            <button type="button" class="btn-outline ph-btn" [disabled]="page() <= 1" (click)="loadOwing(page() - 1)">{{ i18n.t('g.prev') }}</button>
            <span class="ph-muted">{{ i18n.t('g.page', page()) }}</span>
            <button type="button" class="btn-outline ph-btn" [disabled]="!more()" (click)="loadOwing(page() + 1)">{{ i18n.t('g.next') }}</button>
          </div>
        }
        @case ('types') {
          @if (can('manage_contributions')) {
            <div class="ph-row"><span></span><button type="button" class="btn-primary ph-btn" (click)="openType(null)" data-testid="g-c-type-new">{{ i18n.t('g.c.type.new') }}</button></div>
          }
          <div class="ph-card ph-joined" data-testid="g-c-types">
            @for (t of types(); track t['id']) {
              <section class="ph-sec">
                <div class="ph-row"><h3>{{ t['name'] }}</h3><b class="ph-accent">{{ tsh(t['amount']) }}</b></div>
                <div class="ph-line"><span>{{ i18n.t('g.freq.' + t['frequency']) }}@if (t['frequency'] === 'monthly') { · {{ i18n.t('g.c.day', t['due_day']) }} }</span>
                  <span><span class="ph-badge" [class]="t['active'] ? 'ph-good' : 'ph-bad'">{{ t['active'] ? i18n.t('g.running') : i18n.t('g.stopped') }}</span>
                    @if (t['mandatory']) { <span class="ph-badge ph-warn">{{ i18n.t('g.c.mandatory') }}</span> }</span></div>
                @if (t['description']) { <p class="ph-muted">{{ t['description'] }}</p> }
                @if (can('manage_contributions')) {
                  <div class="g-acts">
                    <button type="button" class="btn-outline ph-btn" (click)="openType(t)">{{ i18n.t('g.edit') }}</button>
                    @if (t['active']) { <button type="button" class="btn-primary is-success ph-btn" (click)="openRaise(t)" [attr.data-testid]="'g-c-raise-' + t['id']">{{ i18n.t('g.c.raise') }}</button> }
                  </div>
                }
              </section>
            } @empty { <section class="ph-sec"><p class="ph-muted">{{ i18n.t('g.c.types.none') }}</p></section> }
          </div>
        }
        @case ('promises') {
          <div class="ph-card ph-joined" data-testid="g-c-promises">
            @for (p of promises(); track p['id']) {
              <section class="ph-sec">
                <div class="ph-row"><h3>{{ p['member_name'] }}</h3><span class="ph-badge" [class]="tone(p['state'])">{{ status(p['state']) }}</span></div>
                <div class="ph-line"><span>{{ p['obligation_label'] || i18n.t('g.c.any') }}</span><b>{{ tsh(p['amount']) }}</b></div>
                <div class="ph-line"><span class="ph-muted">{{ i18n.t('g.c.promised.on', day(p['promised_on'])) }}</span><span class="ph-muted">{{ p['note'] }}</span></div>
                @if ((p['state'] === 'due' || p['state'] === 'open' || p['state'] === 'upcoming') && can('record_payments')) {
                  <div class="g-acts"><button type="button" class="btn-outline ph-btn" (click)="cancelPromise(p)">{{ i18n.t('g.c.promise.cancel') }}</button></div>
                }
              </section>
            } @empty { <section class="ph-sec"><p class="ph-muted">{{ i18n.t('g.c.promises.none') }}</p></section> }
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

  ngOnInit(): void {
    void this.loadTypes();
    void this.loadOwing(1);
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
