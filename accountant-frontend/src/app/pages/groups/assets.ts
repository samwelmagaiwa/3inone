import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';
import { MemberPick, PickedMember } from './member-pick';

const HIRE_FILTERS = ['open', 'requested', 'approved', 'issued', 'returned', 'closed', 'declined', 'cancelled'];
const EVENTS = ['maintenance', 'repair', 'damage', 'loss', 'adjust', 'retire'];
type HireAct = 'pay' | 'issue' | 'return' | 'charge';

/**
 * The group's things (chairs, tents, a sound system ...): the register with its keeper and history, and hiring them out. A hire is
 * confirmed by the keeper, paid (verified by someone else), handed over, brought back (damaged and missing counted), charged for damage
 * when need be, and closed.
 */
@Component({
  selector: 'app-g-assets',
  imports: [RowMenuComponent, FormsModule, ModalDialogComponent, MemberPick],
  template: `
    <div class="ad ph-page" data-testid="g-assets">
      <div class="g-toolbar">
        <div class="ph-chips g-seg">
          <button type="button" class="pill-tab" [class.is-active]="tab() === 'assets'" (click)="tab.set('assets'); loadAssets()">{{ i18n.t('g.a.register') }}</button>
          <button type="button" class="pill-tab" [class.is-active]="tab() === 'hires'" (click)="tab.set('hires'); loadHires()" data-testid="g-a-tab-hires">{{ i18n.t('g.a.hires') }}</button>
        </div>
        @if (tab() === 'hires') {
          <span class="g-sep"></span>
          <div class="ph-chips g-seg">
            @for (s of hireFilters; track s) {
              <button type="button" class="pill-tab" [class.is-active]="hireFilter() === s" (click)="hireFilter.set(s); loadHires()">{{ s === 'open' ? i18n.t('g.l.open') : status(s) }}</button>
            }
          </div>
        }
        <input class="g-search" [ngModel]="find()" (ngModelChange)="find.set($event)" [placeholder]="i18n.t('g.find.ph')" [attr.aria-label]="i18n.t('g.search')" />
        <button type="button" class="btn-outline ph-btn" (click)="tab() === 'assets' ? loadAssets() : loadHires()">{{ i18n.t('ad.apply') }}</button>
        @if (tab() === 'assets' && can('manage_assets')) { <button type="button" class="btn-primary ph-btn" (click)="openAsset(null)" data-testid="g-a-new">{{ i18n.t('g.a.new') }}</button> }
        @if (tab() === 'hires') { <button type="button" class="btn-primary is-success ph-btn" (click)="openHire()" data-testid="g-h-new">{{ i18n.t('g.h.new') }}</button> }
        <span class="g-count">{{ i18n.t('g.count', shownCount()) }}</span>
      </div>
      @if (error()) { <section class="ph-card"><p>{{ error() }}</p></section> }

      @if (tab() === 'assets') {
        <div class="table-scroll-container fit-page" data-testid="g-a-list">
          <table class="grid-table g-grid">
            <thead>
              <tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('g.a.code') }}</th>
              <th>{{ i18n.t('g.name') }}</th>
              <th>{{ i18n.t('g.a.category') }}</th>
              <th class="text-right">{{ i18n.t('g.a.quantity') }}</th>
              <th class="text-right">{{ i18n.t('g.a.free') }}</th>
              <th>{{ i18n.t('g.a.keeper') }}</th>
              <th class="text-right">{{ i18n.t('g.a.hire.rate') }}</th>
              <th>{{ i18n.t('g.a.condition') }}</th>
              <th>{{ i18n.t('g.a.location') }}</th>
              <th class="text-right">{{ i18n.t('g.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              @for (a of filtered(assets(), assetKeys); track a['id']) {
                <tr>
                  <td class="no-col">{{ $index + 1 }}</td>
                  <td>{{ a['code'] }}</td>
                  <td class="font-bold">{{ a['name'] }}</td>
                  <td>{{ a['category'] || '—' }}</td>
                  <td class="text-right">{{ a['quantity'] }}</td>
                  <td class="text-right">{{ n(a['free_today'], n(a['quantity'])) }}</td>
                  <td>{{ a['custodian_name'] || '—' }}</td>
                  <td class="text-right">{{ a['hire_rate'] ? tsh(a['hire_rate']) : '—' }}</td>
                  <td>{{ a['condition'] ? i18n.t('g.cond.' + a['condition']) : '—' }}</td>
                  <td>{{ a['location'] || '—' }}</td>
                  <td class="text-right"><app-row-menu [items]="orNone(assetMenu())" [testid]="'g-a-menu-' + a['id']" (picked)="assetPicked($event, a)" /></td>
                </tr>
              } @empty {
                <tr><td colspan="11" class="ph-muted">{{ i18n.t('g.a.none') }}</td></tr>
              }
            </tbody>
          </table>
        </div>
      } @else {
        <div class="table-scroll-container fit-page" data-testid="g-h-list">
          <table class="grid-table g-grid">
            <thead>
              <tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('g.reference') }}</th>
              <th>{{ i18n.t('g.h.who') }}</th>
              <th>{{ i18n.t('g.f.phone') }}</th>
              <th>{{ i18n.t('g.h.what') }}</th>
              <th class="text-right">{{ i18n.t('g.a.quantity') }}</th>
              <th>{{ i18n.t('g.h.from') }}</th>
              <th>{{ i18n.t('g.h.to') }}</th>
              <th class="text-right">{{ i18n.t('g.d.total') }}</th>
              <th class="text-right">{{ i18n.t('g.paid') }}</th>
              <th class="text-right">{{ i18n.t('g.l.left') }}</th>
              <th>{{ i18n.t('g.status') }}</th>
              <th class="text-right">{{ i18n.t('g.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              @for (h of filtered(hires(), hireKeys); track h['id']) {
                <tr>
                  <td class="no-col">{{ $index + 1 }}</td>
                  <td>{{ h['reference'] }}</td>
                  <td class="font-bold">{{ h['who'] }}</td>
                  <td>{{ h['phone'] || '—' }}</td>
                  <td>{{ h['asset_name'] }}</td>
                  <td class="text-right">{{ h['quantity'] }}</td>
                  <td>{{ day(h['start_date']) }}</td>
                  <td>{{ day(h['end_date']) }}</td>
                  <td class="text-right">{{ tsh(h['total'] ?? h['amount']) }}</td>
                  <td class="text-right">{{ tsh(h['paid'] ?? 0) }}</td>
                  <td class="text-right"><span [class.ph-bad]="h['balance'] > 0">{{ tsh(h['balance'] ?? 0) }}</span></td>
                  <td><span class="ph-badge" [class]="tone(h['state'] === 'overdue' ? 'overdue' : h['status'])">{{ h['state'] === 'overdue' ? status('overdue') : status(h['status']) }}</span></td>
                  <td class="text-right"><app-row-menu [items]="orNone(hireMenu(h))" [testid]="'g-h-menu-' + h['id']" (picked)="hirePicked($event, h)" /></td>
                </tr>
              } @empty {
                <tr><td colspan="13" class="ph-muted">{{ i18n.t('g.h.none') }}</td></tr>
              }
            </tbody>
          </table>
        </div>
      }
    </div>

    <!-- an asset -->
    <app-modal-dialog [show]="assetOpen()" [eyebrow]="i18n.t('g.a.register')" [title]="af['id'] ? i18n.t('g.edit') : i18n.t('g.a.new')" size="lg" (close)="assetOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 10px; grid-template-columns: repeat(auto-fill, minmax(min(240px, 100%), 1fr))">
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.a.code') }} *<input class="modal-input" [(ngModel)]="af['code']" name="ac" placeholder="VITI-01" data-testid="g-af-code" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.name') }} *<input class="modal-input" [(ngModel)]="af['name']" name="an" data-testid="g-af-name" /></label>
        @if (!af['id']) { <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.a.quantity') }} *<input class="modal-input" type="number" min="1" [(ngModel)]="af['quantity']" name="aq" data-testid="g-af-qty" /></label> }
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.a.category') }}<input class="modal-input" [(ngModel)]="af['category']" name="acat" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.a.condition') }}<select class="modal-input" [(ngModel)]="af['condition']" name="acond"><option value="">—</option>@for (c of ['good', 'fair', 'poor']; track c) { <option [value]="c">{{ i18n.t('g.cond.' + c) }}</option> }</select></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.a.location') }}<input class="modal-input" [(ngModel)]="af['location']" name="aloc" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.a.hire.rate') }}<input class="modal-input" inputmode="numeric" [(ngModel)]="af['hire_rate']" name="ahr" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.a.late.rate') }}<input class="modal-input" inputmode="numeric" [(ngModel)]="af['late_rate']" name="alr" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.a.cost') }}<input class="modal-input" inputmode="numeric" [(ngModel)]="af['cost']" name="acost" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.a.acquired') }}<input class="modal-input" type="date" [max]="today()" [(ngModel)]="af['acquired_on']" name="aacq" /></label>
        <label class="ph-field" style="grid-column: 1 / -1">{{ i18n.t('g.description') }}<input class="modal-input" [(ngModel)]="af['description']" name="adesc" /></label>
        <div style="grid-column: 1 / -1"><app-g-member-pick [label]="i18n.t('g.a.keeper')" [value]="keeper()" (picked$)="keeper.set($event)" /></div>
        <label class="ph-row" style="grid-column: 1 / -1"><span>{{ i18n.t('g.a.visible') }}</span><input type="checkbox" [(ngModel)]="af['visible']" name="avis" /></label>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="assetOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-success ph-btn" [disabled]="busy()" (click)="saveAsset()" data-testid="g-af-save">{{ i18n.t('g.save') }}</button>
      </div>
    </app-modal-dialog>

    <!-- an asset's history -->
    <app-modal-dialog [show]="!!detail()" [eyebrow]="detail()?.['asset']?.['code'] ?? ''" [title]="detail()?.['asset']?.['name'] ?? ''" size="md" (close)="detail.set(null)">
      <div slot="body">
        <div class="table-scroll-container fit-page">
          <table class="grid-table g-grid">
            <thead>
              <tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('g.kind') }}</th>
              <th class="text-right">{{ i18n.t('g.a.quantity') }}</th>
              <th class="text-right">{{ i18n.t('g.a.cost') }}</th>
              <th>{{ i18n.t('g.note') }}</th>
              <th>{{ i18n.t('g.by') }}</th>
              <th>{{ i18n.t('g.date') }}</th>
              </tr>
            </thead>
            <tbody>
              @for (e of detail()?.['events'] ?? []; track $index) {
                <tr>
                  <td class="no-col">{{ $index + 1 }}</td>
                  <td>{{ i18n.t('g.ev.' + e['kind']) }}</td>
                  <td class="text-right">{{ e['quantity'] || '—' }}</td>
                  <td class="text-right">{{ e['cost'] ? tsh(e['cost']) : '—' }}</td>
                  <td class="g-long" [title]="e['note'] || '—'">{{ e['note'] || '—' }}</td>
                  <td>{{ e['by_name'] || '—' }}</td>
                  <td>{{ when(e['created_at']) }}</td>
                </tr>
              } @empty {
                <tr><td colspan="7" class="ph-muted">{{ i18n.t('g.none') }}</td></tr>
              }
            </tbody>
          </table>
        </div>
      </div>
      <div slot="footer" class="flex gap-2"><button type="button" class="btn-outline ph-btn" (click)="detail.set(null)">{{ i18n.t('common.close') }}</button></div>
    </app-modal-dialog>

    <!-- something happened to an asset -->
    <app-modal-dialog [show]="!!eventFor()" [eyebrow]="eventFor()?.['name'] ?? ''" [title]="i18n.t('g.a.event')" size="sm" (close)="eventFor.set(null)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.kind') }}<select class="modal-input" [(ngModel)]="ev['kind']" name="ek">@for (k of events; track k) { <option [value]="k">{{ i18n.t('g.ev.' + k) }}</option> }</select></label>
        @if (ev['kind'] === 'adjust') {
          <label class="ph-field">{{ i18n.t('g.a.direction') }}<select class="modal-input" [(ngModel)]="ev['direction']" name="ed"><option value="up">{{ i18n.t('g.a.up') }}</option><option value="down">{{ i18n.t('g.a.down') }}</option></select></label>
        }
        <label class="ph-field">{{ i18n.t('g.a.quantity') }}<input class="modal-input" type="number" min="1" [(ngModel)]="ev['quantity']" name="eq" /></label>
        <label class="ph-field">{{ i18n.t('g.a.cost') }}<input class="modal-input" inputmode="numeric" [(ngModel)]="ev['cost']" name="ec" /></label>
        <label class="ph-field">{{ i18n.t('g.note') }} *<input class="modal-input" [(ngModel)]="ev['note']" name="en" /></label>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="eventFor.set(null)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-warn ph-btn" [disabled]="busy()" (click)="saveEvent()">{{ i18n.t('g.save') }}</button>
      </div>
    </app-modal-dialog>

    <!-- a hire written for a member or someone outside -->
    <app-modal-dialog [show]="hireOpen()" [eyebrow]="i18n.t('g.a.hires')" [title]="i18n.t('g.h.new')" size="md" (close)="hireOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.h.what') }}<select class="modal-input" [(ngModel)]="hf['asset_id']" name="ha" data-testid="g-hf-asset">@for (a of assets(); track a['id']) { <option [ngValue]="a['id']">{{ a['name'] }} ({{ a['quantity'] }})</option> }</select></label>
        <div class="ph-row" style="gap: 10px">
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.a.quantity') }}<input class="modal-input" type="number" min="1" [(ngModel)]="hf['quantity']" name="hq" /></label>
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.h.from') }}<input class="modal-input" type="date" [(ngModel)]="hf['start_date']" name="hs" /></label>
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.h.to') }}<input class="modal-input" type="date" [(ngModel)]="hf['end_date']" name="he" /></label>
        </div>
        <label class="ph-row"><span>{{ i18n.t('g.h.outsider') }}</span><input type="checkbox" [(ngModel)]="outsider" name="ho" /></label>
        @if (outsider) {
          <label class="ph-field">{{ i18n.t('g.f.full_name') }}<input class="modal-input" [(ngModel)]="hf['customer_name']" name="hcn" /></label>
          <label class="ph-field">{{ i18n.t('g.f.phone') }}<input class="modal-input" [(ngModel)]="hf['customer_phone']" name="hcp" placeholder="07XXXXXXXX" /></label>
        } @else {
          <app-g-member-pick [value]="hirer()" (picked$)="hirer.set($event)" />
        }
        <label class="ph-field">{{ i18n.t('g.h.purpose') }}<input class="modal-input" [(ngModel)]="hf['purpose']" name="hp" /></label>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="hireOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-success ph-btn" [disabled]="busy()" (click)="saveHire()" data-testid="g-hf-save">{{ i18n.t('g.save') }}</button>
      </div>
    </app-modal-dialog>

    <!-- a step of a hire -->
    <app-modal-dialog [show]="!!acting()" [eyebrow]="acting()?.['h']?.['who'] ?? ''" [title]="actTitle()" size="sm" (close)="acting.set(null)">
      <div slot="body" class="ph-page" style="gap: 10px">
        @switch (acting()?.['kind']) {
          @case ('pay') {
            <label class="ph-field">{{ i18n.t('g.amount') }}<input class="modal-input" inputmode="numeric" [(ngModel)]="x['amount']" name="xa" /></label>
            <label class="ph-field">{{ i18n.t('g.method') }}<select class="modal-input" [(ngModel)]="x['method']" name="xm">@for (m of methods; track m) { <option [value]="m">{{ method(m) }}</option> }</select></label>
            @if (x['method'] !== 'cash') { <label class="ph-field">{{ i18n.t('g.ref') }}<input class="modal-input" [(ngModel)]="x['ref']" name="xr" /></label> }
            <p class="ph-muted">{{ i18n.t('g.p.waits') }}</p>
          }
          @case ('issue') {
            <label class="ph-field">{{ i18n.t('g.h.handed') }}<input class="modal-input" type="number" min="1" [(ngModel)]="x['quantity']" name="xq" /></label>
            <label class="ph-field">{{ i18n.t('g.h.condition') }}<input class="modal-input" [(ngModel)]="x['condition']" name="xc" /></label>
          }
          @case ('return') {
            <label class="ph-field">{{ i18n.t('g.h.returned') }}<input class="modal-input" type="number" min="0" [(ngModel)]="x['returned']" name="xre" /></label>
            <label class="ph-field">{{ i18n.t('g.h.damaged') }}<input class="modal-input" type="number" min="0" [(ngModel)]="x['damaged']" name="xd" /></label>
            <label class="ph-field">{{ i18n.t('g.h.missing') }}<input class="modal-input" type="number" min="0" [(ngModel)]="x['missing']" name="xmi" /></label>
            <label class="ph-field">{{ i18n.t('g.note') }}<input class="modal-input" [(ngModel)]="x['note']" name="xn" /></label>
          }
          @case ('charge') {
            <label class="ph-field">{{ i18n.t('g.h.charge.amount') }}<input class="modal-input" inputmode="numeric" [(ngModel)]="x['amount']" name="xca" /></label>
            <label class="ph-field">{{ i18n.t('g.reason') }} *<input class="modal-input" [(ngModel)]="x['note']" name="xcn" /></label>
          }
        }
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="acting.set(null)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary ph-btn" [class.is-success]="acting()?.['kind'] === 'pay'" [disabled]="busy()" (click)="doAct()">{{ i18n.t('g.save') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [`.g-acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; } .g-acts:empty { display: none; }`],
})
export class GAssetsPage extends GBase implements OnInit {
  protected readonly hireFilters = HIRE_FILTERS;
  protected readonly events = EVENTS;
  protected readonly tab = signal<'assets' | 'hires'>('assets');
  protected readonly assets = signal<Row[]>([]);
  protected readonly hires = signal<Row[]>([]);
  protected readonly hireFilter = signal('open');
  protected readonly error = signal('');

  protected readonly assetOpen = signal(false);
  protected af: Row = {};
  protected readonly keeper = signal<PickedMember | null>(null);
  protected readonly detail = signal<Row | null>(null);
  protected readonly eventFor = signal<Row | null>(null);
  protected ev: Row = {};
  protected readonly hireOpen = signal(false);
  protected hf: Row = {};
  protected outsider = false;
  protected readonly hirer = signal<PickedMember | null>(null);
  protected readonly acting = signal<{ kind: HireAct; h: Row } | null>(null);
  protected x: Row = {};

  protected readonly assetKeys = ['code', 'name', 'category', 'custodian_name', 'location'];
  protected readonly hireKeys = ['who', 'reference', 'asset_name', 'phone'];

  protected shownCount(): number {
    return this.tab() === 'assets' ? this.filtered(this.assets(), this.assetKeys).length : this.filtered(this.hires(), this.hireKeys).length;
  }

  ngOnInit(): void {
    void this.loadAssets();
  }

  protected assetMenu(): MenuItem[] {
    const items: MenuItem[] = [{ id: 'open', label: this.i18n.t('g.a.history') }];
    if (this.can('manage_assets')) {
      items.push({ id: 'edit', label: this.i18n.t('g.edit') });
      items.push({ id: 'event', label: this.i18n.t('g.a.event') });
    }
    return items;
  }

  protected assetPicked(id: string, a: Row): void {
    if (id === 'open') void this.openDetail(a);
    if (id === 'edit') this.openAsset(a);
    if (id === 'event') this.openEvent(a);
  }

  protected hireMenu(h: Row): MenuItem[] {
    const items: MenuItem[] = [];
    const s = h['status'];
    if (s === 'requested') {
      items.push({ id: 'approve', label: this.i18n.t('g.approve'), primary: true, testid: 'g-h-approve-' + h['id'] });
      items.push({ id: 'decline', label: this.i18n.t('g.turn.down'), danger: true });
    }
    if ((s === 'approved' || s === 'returned' || s === 'issued') && h['balance'] > 0) items.push({ id: 'pay', label: this.i18n.t('g.h.take.pay'), primary: true });
    if (s === 'approved') items.push({ id: 'issue', label: this.i18n.t('g.h.issue') });
    if (s === 'issued') items.push({ id: 'return', label: this.i18n.t('g.h.return') });
    if (s === 'returned' && this.can('decide_hire_charges') && (this.n(h['damaged_quantity']) + this.n(h['missing_quantity'])) > 0 && h['damage_charge'] === null) {
      items.push({ id: 'charge', label: this.i18n.t('g.h.charge'), danger: true });
    }
    if (s === 'returned' && !(h['balance'] > 0)) items.push({ id: 'close', label: this.i18n.t('g.h.close') });
    return items;
  }

  protected hirePicked(id: string, h: Row): void {
    switch (id) {
      case 'approve': void this.decide(h, true); break;
      case 'decline': void this.decide(h, false); break;
      case 'close': void this.close(h); break;
      default: this.openAct(h, id as HireAct);
    }
  }

  protected actTitle(): string {
    switch (this.acting()?.kind) {
      case 'pay': return this.i18n.t('g.h.take.pay');
      case 'issue': return this.i18n.t('g.h.issue');
      case 'return': return this.i18n.t('g.h.return');
      case 'charge': return this.i18n.t('g.h.charge');
      default: return '';
    }
  }

  async loadAssets(): Promise<void> {
    this.error.set('');
    try {
      this.assets.set(((await this.api.get('/assets'))['assets'] as Row[]) ?? []);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  async loadHires(): Promise<void> {
    this.error.set('');
    try {
      this.hires.set(((await this.api.get('/hires', { status: this.hireFilter() }))['hires'] as Row[]) ?? []);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  protected openAsset(a: Row | null): void {
    this.af = a ? { ...a } : { quantity: 1, condition: 'good', visible: true };
    for (const k of ['hire_rate', 'late_rate', 'cost']) this.af[k] = this.af[k] === null || this.af[k] === undefined ? '' : String(this.af[k]);
    this.keeper.set(a?.['custodian_id'] ? { id: Number(a['custodian_id']), name: String(a['custodian_name'] ?? ''), number: '' } : null);
    this.assetOpen.set(true);
  }

  protected async saveAsset(): Promise<void> {
    const code = String(this.af['code'] ?? '').trim();
    const name = String(this.af['name'] ?? '').trim();
    if (!code || name.length < 2) return this.stop(this.i18n.t('g.need.name'));
    const money = (v: unknown) => (String(v ?? '').trim() === '' ? null : this.amount(v));
    const body: Row = {
      code, name,
      category: String(this.af['category'] ?? '').trim() || null,
      description: String(this.af['description'] ?? '').trim() || null,
      condition: this.af['condition'] || null,
      location: String(this.af['location'] ?? '').trim() || null,
      acquired_on: this.af['acquired_on'] || null,
      cost: money(this.af['cost']),
      hire_rate: money(this.af['hire_rate']),
      late_rate: money(this.af['late_rate']),
      custodian_id: this.keeper()?.id ?? null,
      visible: !!this.af['visible'],
    };
    const id = this.af['id'];
    if (!id) body['quantity'] = Number(this.af['quantity']) || 1;
    if (await this.act(() => (id ? this.api.put(`/assets/${id}`, body) : this.api.post('/assets', body)), this.i18n.t('g.saved'))) {
      this.assetOpen.set(false);
      await this.loadAssets();
    }
  }

  protected async openDetail(a: Row): Promise<void> {
    try {
      this.detail.set(await this.api.get(`/assets/${a['id']}`));
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  protected openEvent(a: Row): void {
    this.ev = { kind: 'maintenance', quantity: 1, cost: '', note: '', direction: 'down' };
    this.eventFor.set(a);
  }

  protected async saveEvent(): Promise<void> {
    const a = this.eventFor();
    if (!a) return;
    if (String(this.ev['note'] ?? '').trim().length < 3) return this.stop(this.i18n.t('g.need.reason'));
    const body: Row = { kind: this.ev['kind'], note: String(this.ev['note']).trim(), quantity: Number(this.ev['quantity']) || null, cost: String(this.ev['cost'] ?? '').trim() ? this.amount(this.ev['cost']) : null };
    if (this.ev['kind'] === 'adjust') body['direction'] = this.ev['direction'];
    if (await this.act(() => this.api.post(`/assets/${a['id']}/events`, body), this.i18n.t('g.saved'))) {
      this.eventFor.set(null);
      await this.loadAssets();
    }
  }

  protected async openHire(): Promise<void> {
    if (!this.assets().length) await this.loadAssets();
    this.hf = { asset_id: this.assets()[0]?.['id'] ?? null, quantity: 1, start_date: this.today(), end_date: this.today(), purpose: '' };
    this.outsider = false;
    this.hirer.set(null);
    this.hireOpen.set(true);
  }

  protected async saveHire(): Promise<void> {
    if (!this.hf['asset_id']) return this.stop(this.i18n.t('g.need.asset'));
    const body: Row = { asset_id: this.hf['asset_id'], quantity: Number(this.hf['quantity']) || 1, start_date: this.hf['start_date'], end_date: this.hf['end_date'], ...(String(this.hf['purpose'] ?? '').trim() ? { purpose: String(this.hf['purpose']).trim() } : {}) };
    if (this.outsider) {
      body['customer_name'] = String(this.hf['customer_name'] ?? '').trim();
      body['customer_phone'] = String(this.hf['customer_phone'] ?? '').trim();
    } else {
      const m = this.hirer();
      if (!m) return this.stop(this.i18n.t('g.need.member'));
      body['member_id'] = m.id;
    }
    if (await this.act(() => this.api.post('/hires', body), this.i18n.t('g.saved'))) {
      this.hireOpen.set(false);
      this.tab.set('hires');
      await this.loadHires();
    }
  }

  protected async decide(h: Row, approve: boolean): Promise<void> {
    let note: string | null = null;
    if (!approve) {
      note = await this.reason(this.i18n.t('g.turn.down'), `${h['who']} · ${h['asset_name']} × ${h['quantity']}`, this.i18n.t('g.turn.down'));
      if (note === null) return;
    } else if (!(await this.sure(this.i18n.t('g.approve'), `${h['who']} · ${h['asset_name']} × ${h['quantity']} · ${this.day(h['start_date'])}`, this.i18n.t('g.approve')))) {
      return;
    }
    if (await this.act(() => this.api.post(`/hires/${h['id']}/decide`, { approve, ...(note ? { note } : {}) }), this.i18n.t('g.saved'))) await Promise.all([this.loadHires(), this.ctx.reload()]);
  }

  protected openAct(h: Row, kind: HireAct): void {
    switch (kind) {
      case 'pay': this.x = { amount: String(h['balance'] ?? ''), method: 'cash', ref: '' }; break;
      case 'issue': this.x = { quantity: h['quantity'], condition: '' }; break;
      case 'return': this.x = { returned: h['issued_quantity'] ?? h['quantity'], damaged: 0, missing: 0, note: '' }; break;
      case 'charge': this.x = { amount: '', note: '' }; break;
    }
    this.acting.set({ kind, h });
  }

  protected async doAct(): Promise<void> {
    const a = this.acting();
    if (!a) return;
    const id = a.h['id'];
    let call: () => Promise<unknown>;
    switch (a.kind) {
      case 'pay': {
        const amount = this.amount(this.x['amount']);
        if (amount < 1) return this.stop(this.i18n.t('g.need.amount'));
        call = () => this.api.post(`/hires/${id}/pay`, { amount, method: this.x['method'], ...(String(this.x['ref'] ?? '').trim() ? { external_ref: String(this.x['ref']).trim() } : {}) });
        break;
      }
      case 'issue':
        call = () => this.api.post(`/hires/${id}/issue`, { quantity: Number(this.x['quantity']) || 1, ...(String(this.x['condition'] ?? '').trim() ? { condition: String(this.x['condition']).trim() } : {}) });
        break;
      case 'return':
        call = () => this.api.post(`/hires/${id}/return`, { returned: Number(this.x['returned']) || 0, damaged: Number(this.x['damaged']) || 0, missing: Number(this.x['missing']) || 0, ...(String(this.x['note'] ?? '').trim() ? { note: String(this.x['note']).trim() } : {}) });
        break;
      case 'charge':
        if (String(this.x['note'] ?? '').trim().length < 3) return this.stop(this.i18n.t('g.need.reason'));
        call = () => this.api.post(`/hires/${id}/charge`, { amount: this.amount(this.x['amount']), note: String(this.x['note']).trim() });
        break;
    }
    if (await this.act(call, this.i18n.t('g.saved'))) {
      this.acting.set(null);
      await this.loadHires();
    }
  }

  protected async close(h: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.h.close'), `${h['who']} · ${h['asset_name']}`, this.i18n.t('g.h.close')))) return;
    if (await this.act(() => this.api.post(`/hires/${h['id']}/close`), this.i18n.t('g.saved'))) await this.loadHires();
  }
}
