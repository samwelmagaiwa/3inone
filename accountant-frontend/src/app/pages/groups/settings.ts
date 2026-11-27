import { Component, OnInit, computed, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';

import { Row } from '../../core/groups/groups-api.service';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';
import { G_OFFICES } from './members';

type Tab = 'values' | 'methods' | 'offices' | 'codes' | 'logo' | 'log';
const PAY_CHOICES = ['mpesa', 'mixx', 'airtel_money', 'halopesa', 'bank_transfer', 'cash'];
/** The settings in the order the page shows them. */
const KEYS = [
  'joining_fee', 'share_amount', 'shares_required_for', 'member_prefix', 'payment_instructions',
  'loan_interest_rate', 'loan_interest_method', 'loan_multiplier', 'loan_max_months', 'loan_guarantors', 'loan_repayment', 'loan_repayment_days',
  'sms_reminders', 'sms_show_amounts', 'hire_days_rule',
];

/**
 * The group's settings and records: its values (fees, shares, loan terms, reminders ...; a change starts on a day, never rewrites the
 * past, and needs a reason), the payment methods members pay by, who holds each office, invitation codes, the group's logo (the
 * business admin's), and the activity log of everything done.
 */
@Component({
  selector: 'app-g-settings',
  imports: [RowMenuComponent, FormsModule, RouterLink],
  template: `
    <div class="ad ph-page" data-testid="g-settings">
      <div class="g-toolbar">
        <div class="ph-chips g-seg">
          @for (t of tabs(); track t) {
            <button type="button" class="pill-tab" [class.is-active]="tab() === t" (click)="go(t)" [attr.data-testid]="'g-s-tab-' + t">{{ i18n.t('g.s.tab.' + t) }}</button>
          }
        </div>
        @if (tab() === 'codes' || tab() === 'log') {
        <input class="g-search" [ngModel]="find()" (ngModelChange)="find.set($event)" [placeholder]="i18n.t('g.find.ph')" [attr.aria-label]="i18n.t('g.search')" />
        <button type="button" class="btn-outline ph-btn" (click)="go(tab())">{{ i18n.t('ad.apply') }}</button>
        }
        @if (tab() === 'codes') { <button type="button" class="btn-primary ph-btn" (click)="newCode()" [title]="i18n.t('g.s.codes.hint')" data-testid="g-s-code-new">{{ i18n.t('g.s.code.new') }}</button> }
        @if (tab() === 'codes' || tab() === 'log') {
        <span class="g-count">{{ i18n.t('g.count', shownCount()) }}</span>
        }
      </div>
      @if (error()) { <section class="ph-card"><p>{{ error() }}</p></section> }

      @switch (tab()) {
        @case ('values') {
          @if (s(); as s) {
            <div class="ph-card ph-joined ph-cols" data-testid="g-s-values">
              @for (k of keys; track k) {
                @let spec = s['keys']?.[k];
                @if (spec) {
                  <section class="ph-sec">
                    <label class="ph-field">{{ i18n.t('g.set.' + k) }}
                      @if (spec['type'] === 'choice') {
                        <select class="modal-input" [ngModel]="edit[k]" (ngModelChange)="edit[k] = $event" [name]="k" [disabled]="!can('manage_settings')" [attr.data-testid]="'g-set-' + k">
                          @for (c of spec['choices']; track c) { <option [value]="c">{{ c === '' ? '—' : i18n.t('g.setv.' + c) }}</option> }
                        </select>
                      } @else if (k === 'payment_instructions') {
                        <textarea class="modal-input" rows="3" [ngModel]="edit[k]" (ngModelChange)="edit[k] = $event" [name]="k" [disabled]="!can('manage_settings')"></textarea>
                      } @else {
                        <input class="modal-input" [ngModel]="edit[k]" (ngModelChange)="edit[k] = $event" [name]="k" [disabled]="!can('manage_settings')" [attr.data-testid]="'g-set-' + k"
                          [attr.inputmode]="spec['type'] === 'text' ? null : 'decimal'" />
                      }
                    </label>
                    <p class="ph-muted">{{ i18n.t('g.set.' + k + '.hint') }}</p>
                  </section>
                }
              }
            </div>
            @if (can('manage_settings')) {
              <div class="ph-card ph-row" style="flex-wrap: wrap; align-items: end">
                <label class="ph-field" style="flex: 2; min-width: 220px">{{ i18n.t('g.reason') }} *<input class="modal-input" [(ngModel)]="reasonText" name="sr" data-testid="g-s-reason" [placeholder]="i18n.t('g.s.reason.ph')" /></label>
                <label class="ph-field">{{ i18n.t('g.s.from') }}<input class="modal-input" type="date" [min]="today()" [(ngModel)]="effective" name="se" /></label>
                <button type="button" class="btn-primary is-success ph-btn" [disabled]="busy() || !changed().length" (click)="saveValues()" data-testid="g-s-save">{{ i18n.t('g.s.save', changed().length) }}</button>
              </div>
            }
            <h3>{{ i18n.t('g.s.history') }}</h3>
    <div class="table-scroll-container fit-page">
              <table class="grid-table">
                <thead>
                  <tr>
                  <th class="no-col">#</th>
                  <th>{{ i18n.t('g.s.setting') }}</th>
                  <th>{{ i18n.t('g.s.value') }}</th>
                  <th>{{ i18n.t('g.s.from') }}</th>
                  <th>{{ i18n.t('g.reason') }}</th>
                  <th>{{ i18n.t('g.by') }}</th>
                  <th>{{ i18n.t('g.date') }}</th>
                  </tr>
                </thead>
                <tbody>
                  @for (h of s['history'] ?? []; track h['id']) {
                    <tr>
                      <td class="no-col">{{ $index + 1 }}</td>
                      <td class="font-bold">{{ i18n.t('g.set.' + h['key']) }}</td>
                      <td>{{ shown(h['key'], h['value']) }}</td>
                      <td>{{ day(h['effective_from']) }}</td>
                      <td>{{ h['reason'] || '—' }}</td>
                      <td>{{ h['changed_by_name'] || '—' }}</td>
                      <td>{{ when(h['created_at']) }}</td>
                    </tr>
                  } @empty {
                    <tr><td colspan="7" class="ph-muted">{{ i18n.t('g.none') }}</td></tr>
                  }
                </tbody>
              </table>
            </div>
          } @else { <section class="ph-card"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section> }
        }
        @case ('methods') {
          <div class="ph-card ph-joined" data-testid="g-s-methods">
            @if (!methodsConfigured()) { <section class="ph-sec"><p class="ph-warn" style="font-size: 13px">{{ i18n.t('g.s.methods.none') }}</p></section> }
            @for (m of methods_; track $index) {
              <section class="ph-sec">
                <div class="ph-row" style="gap: 6px; flex-wrap: wrap">
                  <select class="modal-input" style="flex: 1" [(ngModel)]="m['method']" [name]="'mm' + $index" [disabled]="!canMethods()">@for (c of payChoices; track c) { <option [value]="c">{{ method(c) }}</option> }</select>
                  @if (m['method'] !== 'cash') {
                    <input class="modal-input" style="flex: 1" [(ngModel)]="m['number']" [name]="'mn' + $index" [placeholder]="m['method'] === 'bank_transfer' ? i18n.t('g.s.account.no') : i18n.t('g.s.number')" [disabled]="!canMethods()" />
                    <input class="modal-input" style="flex: 1" [(ngModel)]="m['account_name']" [name]="'ma' + $index" [placeholder]="i18n.t('g.s.account.name')" [disabled]="!canMethods()" />
                  }
                  @if (m['method'] === 'bank_transfer') { <input class="modal-input" style="flex: 1" [(ngModel)]="m['bank_name']" [name]="'mb' + $index" [placeholder]="i18n.t('g.s.bank')" [disabled]="!canMethods()" /> }
                  @if (canMethods()) { <button type="button" class="link-btn danger" (click)="methods_.splice($index, 1)">{{ i18n.t('g.remove') }}</button> }
                </div>
              </section>
            }
          </div>
          @if (canMethods()) {
            <div class="ph-card ph-row" style="flex-wrap: wrap; align-items: end">
              <button type="button" class="btn-outline ph-btn" (click)="methods_.push({ method: 'mpesa', number: '', account_name: '' })" [disabled]="methods_.length >= 6">{{ i18n.t('g.add') }}</button>
              <label class="ph-field" style="flex: 1; min-width: 220px">{{ i18n.t('g.reason') }} *<input class="modal-input" [(ngModel)]="methodsReason" name="mr" /></label>
              <button type="button" class="btn-primary is-success ph-btn" [disabled]="busy()" (click)="saveMethods()" data-testid="g-s-methods-save">{{ i18n.t('g.save') }}</button>
            </div>
          }
        }
        @case ('offices') {
          <div class="table-scroll-container fit-page" data-testid="g-s-offices">
            <table class="grid-table">
              <thead>
                <tr>
                <th class="no-col">#</th>
                <th>{{ i18n.t('g.office') }}</th>
                <th>{{ i18n.t('g.s.holders') }}</th>
                </tr>
              </thead>
              <tbody>
                @for (o of offices; track o) {
                  <tr>
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td class="font-bold">{{ office(o) }}</td>
                    <td>{{ holders(o) || '—' }}</td>
                  </tr>
                } @empty {
                  <tr><td colspan="3" class="ph-muted">{{ i18n.t('g.none') }}</td></tr>
                }
              </tbody>
            </table>
          </div>
          @if (can('manage_offices')) { <p class="ph-muted">{{ i18n.t('g.s.offices.how') }} <a routerLink="/groups/members" class="link-btn">{{ i18n.t('nav.g.members') }}</a></p> }
        }
        @case ('codes') {
          <div class="table-scroll-container fit-page" data-testid="g-s-codes">
            <table class="grid-table">
              <thead>
                <tr>
                <th class="no-col">#</th>
                <th>{{ i18n.t('g.s.code') }}</th>
                <th class="text-right">{{ i18n.t('g.s.used') }}</th>
                <th>{{ i18n.t('g.status') }}</th>
                <th class="text-right">{{ i18n.t('g.actions') }}</th>
                </tr>
              </thead>
              <tbody>
                @for (c of filtered(codes(), codeKeys); track c['id']) {
                  <tr>
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td><b style="letter-spacing: 0.12em">{{ c['code'] }}</b></td>
                    <td class="text-right">{{ n(c['used']) }}</td>
                    <td><span class="ph-badge" [class]="c['active'] ? 'ph-good' : 'ph-bad'">{{ c['active'] ? i18n.t('g.running') : i18n.t('g.stopped') }}</span></td>
                    <td class="text-right">@if ((c['active'] ? [{ id: 'stop', label: i18n.t('g.s.code.stop'), danger: true }] : []).length) { <app-row-menu [items]="(c['active'] ? [{ id: 'stop', label: i18n.t('g.s.code.stop'), danger: true }] : [])" [testid]="'g-s-code-menu-' + c['id']" (picked)="stopCode(c)" /> } @else { — }</td>
                  </tr>
                } @empty {
                  <tr><td colspan="5" class="ph-muted">{{ i18n.t('g.none') }}</td></tr>
                }
              </tbody>
            </table>
          </div>
        }
        @case ('logo') {
          <div class="ph-card" data-testid="g-s-logo">
            <div class="ph-row" style="justify-content: flex-start; gap: 16px; flex-wrap: wrap">
              <div class="g-logo">@if (ctx.logoUrl(); as url) { <img [src]="url" alt="" /> } @else { <span>{{ (ctx.groupName() || 'G').slice(0, 1) }}</span> }</div>
              <div>
                <p><b>{{ ctx.groupName() }}</b></p>
                <p class="ph-muted">{{ i18n.t('g.s.logo.hint') }}</p>
                <div class="g-acts">
                  <label class="btn-primary ph-btn" style="cursor: pointer">{{ i18n.t('g.s.logo.pick') }}<input type="file" accept="image/png,image/jpeg,image/webp" hidden (change)="upload($event)" data-testid="g-s-logo-file" /></label>
                  <button type="button" class="btn-outline is-danger ph-btn" (click)="removeLogo()">{{ i18n.t('g.s.logo.remove') }}</button>
                </div>
              </div>
            </div>
          </div>
        }
        @case ('log') {
          <div class="table-scroll-container fit-page" data-testid="g-s-log">
            <table class="grid-table">
              <thead>
                <tr>
                <th class="no-col">#</th>
                <th>{{ i18n.t('g.date') }}</th>
                <th>{{ i18n.t('g.s.what') }}</th>
                <th>{{ i18n.t('g.by') }}</th>
                </tr>
              </thead>
              <tbody>
                @for (e of filtered(log(), logKeys); track e['id']) {
                  <tr>
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td>{{ when(e['created_at']) }}</td>
                    <td>{{ e['summary'] || e['action'] }}</td>
                    <td>{{ e['by_name'] || '—' }}</td>
                  </tr>
                } @empty {
                  <tr><td colspan="4" class="ph-muted">{{ i18n.t('g.none') }}</td></tr>
                }
              </tbody>
            </table>
          </div>
          @if (logMore()) { <button type="button" class="btn-outline ph-btn" (click)="loadLog(true)">{{ i18n.t('g.more') }}</button> }
        }
      }
    </div>
  `,
  styles: [
    `
      .g-acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
      .g-logo { width: 96px; height: 96px; border-radius: 50%; overflow: hidden; display: grid; place-items: center; background: #fff; color: #0d6f8f; font-size: 40px; font-weight: 900; border: 2px solid rgba(255, 255, 255, 0.3); }
      .g-logo img { width: 100%; height: 100%; object-fit: cover; }
    `,
  ],
})
export class GSettingsPage extends GBase implements OnInit {
  protected readonly keys = KEYS;
  protected readonly offices = G_OFFICES;
  protected readonly payChoices = PAY_CHOICES;
  protected readonly tab = signal<Tab>('values');
  protected readonly error = signal('');

  protected readonly s = signal<Row | null>(null);
  protected edit: Row = {};
  protected reasonText = '';
  protected effective = '';

  protected methods_: Row[] = [];
  protected readonly methodsConfigured = signal(true);
  protected readonly canMethods = signal(false);
  protected methodsReason = '';
  protected readonly leaders = signal<Row[]>([]);
  protected readonly codes = signal<Row[]>([]);
  protected readonly log = signal<Row[]>([]);
  protected readonly logMore = signal(false);

  /** The tabs this person may open. */
  protected readonly tabs = computed<Tab[]>(() => {
    const t: Tab[] = ['values', 'methods'];
    if (this.can('view_members')) t.push('offices');
    if (this.can('manage_members')) t.push('codes');
    if (this.ctx.isOwner()) t.push('logo');
    if (this.can('view_audit')) t.push('log');
    return t;
  });

  /** The settings changed in the form, not yet saved (read each time the page draws: the form's fields are plain values). */
  protected changed(): string[] {
    const now = this.s()?.['settings'] ?? {};
    return KEYS.filter((k) => this.edit[k] !== undefined && String(this.edit[k] ?? '') !== String(now[k] ?? ''));
  }

  protected readonly codeKeys = ['code'];
  protected readonly logKeys = ['summary', 'action', 'by_name'];

  protected shownCount(): number {
    return this.tab() === 'codes' ? this.filtered(this.codes(), this.codeKeys).length : this.filtered(this.log(), this.logKeys).length;
  }

  ngOnInit(): void {
    void this.go('values');
  }

  protected async go(t: Tab): Promise<void> {
    this.tab.set(t);
    this.error.set('');
    try {
      switch (t) {
        case 'values': return await this.loadValues();
        case 'methods': {
          const d = await this.api.get('/payment-methods');
          this.methods_ = ((d['methods'] as Row[]) ?? []).map((m) => ({ ...m }));
          this.methodsConfigured.set(d['configured'] === true);
          this.canMethods.set(d['can_manage'] === true);
          return;
        }
        case 'offices': {
          const all: Row[] = [];
          for (let page = 1; page <= 40; page++) {
            const p = await this.api.page('/members', 'members', { status: 'active', page });
            all.push(...p.items.filter((m) => !!m['office']));
            if (!p.hasMore) break;
          }
          this.leaders.set(all);
          return;
        }
        case 'codes': return this.codes.set(((await this.api.get('/invitations'))['group'] as Row[]) ?? []);
        case 'log': return await this.loadLog(false);
        default: return;
      }
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  private async loadValues(): Promise<void> {
    const d = await this.api.get('/settings');
    this.s.set(d);
    this.edit = { ...(d['settings'] ?? {}) };
    this.reasonText = '';
    this.effective = this.today();
  }

  /** A setting's value as people read it (a choice by its name). */
  protected shown(key: string, value: string): string {
    const spec = this.s()?.['keys']?.[key];
    if (spec?.['type'] === 'choice') return value === '' ? '—' : this.i18n.t('g.setv.' + value);
    if (spec?.['type'] === 'money') return this.tsh(Number(value) || 0);
    return value;
  }

  protected async saveValues(): Promise<void> {
    const keys = this.changed();
    if (!keys.length) return;
    if (this.reasonText.trim().length < 3) return this.stop(this.i18n.t('g.need.reason'));
    const values: Row = {};
    for (const k of keys) values[k] = this.edit[k];
    const list = keys.map((k) => `${this.i18n.t('g.set.' + k)}: ${this.shown(k, String(this.edit[k] ?? ''))}`).join('\n');
    if (!(await this.sure(this.i18n.t('g.s.save', keys.length), list, this.i18n.t('g.save')))) return;
    if (await this.act(() => this.api.put('/settings', { values, reason: this.reasonText.trim(), ...(this.effective && this.effective !== this.today() ? { effective_from: this.effective } : {}) }), this.i18n.t('g.saved'))) {
      await this.loadValues();
      await this.ctx.reload();
    }
  }

  protected holders(o: string): string {
    return this.leaders().filter((m) => m['office'] === o).map((m) => m['full_name']).join(', ');
  }

  protected async saveMethods(): Promise<void> {
    if (!this.methods_.length) return this.stop(this.i18n.t('g.need.method'));
    if (this.methodsReason.trim().length < 3) return this.stop(this.i18n.t('g.need.reason'));
    const methods = this.methods_.map((m) => {
      const out: Row = { method: m['method'] };
      if (m['method'] !== 'cash') {
        if (String(m['number'] ?? '').trim()) out['number'] = String(m['number']).trim();
        if (String(m['account_name'] ?? '').trim()) out['account_name'] = String(m['account_name']).trim();
      }
      if (m['method'] === 'bank_transfer' && String(m['bank_name'] ?? '').trim()) out['bank_name'] = String(m['bank_name']).trim();
      return out;
    });
    if (await this.act(() => this.api.put('/payment-methods', { methods, reason: this.methodsReason.trim() }), this.i18n.t('g.saved'))) {
      this.methodsReason = '';
      await this.go('methods');
    }
  }

  protected async newCode(): Promise<void> {
    if (await this.act(() => this.api.post('/invitations'), this.i18n.t('g.saved'))) await this.go('codes');
  }

  protected async stopCode(c: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.s.code.stop'), c['code'], this.i18n.t('g.s.code.stop'), true))) return;
    if (await this.act(() => this.api.post(`/invitations/${c['id']}/stop`), this.i18n.t('g.saved'))) await this.go('codes');
  }

  protected async upload(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file) return;
    if (file.size > 2 * 1024 * 1024) return this.stop(this.i18n.t('g.s.logo.big'));
    if (await this.act(() => this.api.uploadLogo(file), this.i18n.t('g.s.logo.saved'))) await this.ctx.reload();
  }

  protected async removeLogo(): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.s.logo.remove'), this.i18n.t('g.s.logo.remove.sure'), this.i18n.t('g.s.logo.remove'), true))) return;
    if (await this.act(() => this.api.removeLogo(), this.i18n.t('g.saved'))) await this.ctx.reload();
  }

  async loadLog(more: boolean): Promise<void> {
    const before = more ? this.log()[this.log().length - 1]?.['id'] : null;
    const entries = ((await this.api.get('/audit', { before })) ['entries'] as Row[]) ?? [];
    this.log.set(more ? [...this.log(), ...entries] : entries);
    this.logMore.set(entries.length >= 50);
  }
}
