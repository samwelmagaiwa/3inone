import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';

/**
 * Dividends (gawio): a period is closed with the profit the group agreed to share; each member's share is worked out from their
 * savings (at the end of the period, or the average over it), as a rate of savings or as a share of the pool. One leader prepares,
 * another approves and posts it to savings; a period is never paid twice.
 */
@Component({
  selector: 'app-g-dividends',
  imports: [RowMenuComponent, FormsModule, ModalDialogComponent],
  template: `
    <div class="ad ph-page" data-testid="g-dividends">
      <div class="g-toolbar"><span class="ph-muted" style="flex: 1">{{ i18n.t('g.d.hint') }}</span>
        @if (can('prepare_dividends')) { <button type="button" class="btn-primary ph-btn" (click)="openPrepare()" data-testid="g-d-new">{{ i18n.t('g.d.prepare') }}</button> }</div>
      @if (error()) { <section class="ph-card"><p>{{ error() }}</p></section> }
      <div class="table-scroll-container fit-page" data-testid="g-d-list">
          <table class="grid-table">
            <thead>
              <tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('g.d.period') }}</th>
              <th class="text-right">{{ i18n.t('g.d.pool') }}</th>
              <th>{{ i18n.t('g.d.base') }}</th>
              <th>{{ i18n.t('g.d.method') }}</th>
              <th class="text-right">{{ i18n.t('g.d.total') }}</th>
              <th>{{ i18n.t('g.d.prepared.by') }}</th>
              <th>{{ i18n.t('g.d.approved.by') }}</th>
              <th>{{ i18n.t('g.status') }}</th>
              <th>{{ i18n.t('g.note') }}</th>
              <th class="text-right">{{ i18n.t('g.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              @for (r of runs(); track r['id']) {
                <tr>
                  <td class="no-col">{{ $index + 1 }}</td>
                  <td class="font-bold">{{ day(r['period_from']) }} – {{ day(r['period_to']) }}</td>
                  <td class="text-right">{{ tsh(r['profit_pool']) }}</td>
                  <td>{{ i18n.t('g.d.base.' + r['base']) }}</td>
                  <td>{{ r['method'] === 'rate' ? i18n.t('g.d.rate', r['rate']) : i18n.t('g.d.method.share') }}</td>
                  <td class="text-right"><b class="ph-accent">{{ tsh(r['total']) }}</b></td>
                  <td>{{ r['prepared_by_name'] || '—' }}</td>
                  <td>{{ r['approved_by_name'] || '—' }}</td>
                  <td><span class="ph-badge" [class]="tone(r['status'] === 'posted' ? 'done' : r['status'] === 'discarded' ? 'cancelled' : 'pending')">{{ status(r['status']) }}</span></td>
                  <td>{{ r['note'] || '—' }}</td>
                  <td class="text-right">@if (menuFor(r).length) { <app-row-menu [items]="menuFor(r)" [testid]="'g-d-menu-' + r['id']" (picked)="picked($event, r)" /> } @else { — }</td>
                </tr>
              } @empty {
                <tr><td colspan="11" class="ph-muted">{{ i18n.t('g.d.none') }}</td></tr>
              }
            </tbody>
          </table>
        </div>
    </div>

    <app-modal-dialog [show]="!!run()" [eyebrow]="i18n.t('nav.g.dividends')" [title]="(run()?.['period_from'] ? day(run()!['period_from']) + ' – ' + day(run()!['period_to']) : '')" size="lg" (close)="run.set(null)">
      <div slot="body">
        <div class="table-scroll-container fit-page">
          <table class="grid-table">
            <thead>
              <tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('g.member') }}</th>
              <th>{{ i18n.t('g.number') }}</th>
              <th class="text-right">{{ i18n.t('g.d.base.amount') }}</th>
              <th class="text-right">{{ i18n.t('g.d.share') }}</th>
              </tr>
            </thead>
            <tbody>
              @for (l of run()?.['lines'] ?? []; track l['member_id']) {
                <tr>
                  <td class="no-col">{{ $index + 1 }}</td>
                  <td class="font-bold">{{ l['name'] }}</td>
                  <td>{{ l['member_number'] || '—' }}</td>
                  <td class="text-right">{{ tsh(l['base']) }}</td>
                  <td class="text-right"><b class="ph-good">{{ tsh(l['amount']) }}</b></td>
                </tr>
              } @empty {
                <tr><td colspan="5" class="ph-muted">{{ i18n.t('g.none') }}</td></tr>
              }
            </tbody>
          </table>
        </div>
      </div>
      <div slot="footer" class="flex gap-2"><button type="button" class="btn-outline ph-btn" (click)="run.set(null)">{{ i18n.t('common.close') }}</button></div>
    </app-modal-dialog>

    <app-modal-dialog [show]="prepOpen()" [eyebrow]="i18n.t('nav.g.dividends')" [title]="i18n.t('g.d.prepare')" size="md" (close)="prepOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <div class="ph-row" style="gap: 10px">
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.h.from') }}<input class="modal-input" type="date" [(ngModel)]="f['period_from']" name="df" /></label>
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.h.to') }}<input class="modal-input" type="date" [max]="today()" [(ngModel)]="f['period_to']" name="dt" /></label>
        </div>
        <label class="ph-field">{{ i18n.t('g.d.pool') }} *<input class="modal-input" inputmode="numeric" [(ngModel)]="f['profit_pool']" name="dp" data-testid="g-df-pool" /></label>
        <label class="ph-field">{{ i18n.t('g.d.base') }}<select class="modal-input" [(ngModel)]="f['base']" name="db"><option value="closing">{{ i18n.t('g.d.base.closing') }}</option><option value="average">{{ i18n.t('g.d.base.average') }}</option></select></label>
        <label class="ph-field">{{ i18n.t('g.d.method') }}<select class="modal-input" [(ngModel)]="f['method']" name="dm"><option value="rate">{{ i18n.t('g.d.method.rate') }}</option><option value="share">{{ i18n.t('g.d.method.share') }}</option></select></label>
        @if (f['method'] === 'rate') { <label class="ph-field">{{ i18n.t('g.d.rate.percent') }}<input class="modal-input" type="number" step="0.1" min="0.001" max="100" [(ngModel)]="f['rate']" name="dr" /></label> }
        <label class="ph-field">{{ i18n.t('g.note') }} *<input class="modal-input" [(ngModel)]="f['note']" name="dn" data-testid="g-df-note" /></label>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="prepOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary ph-btn" [disabled]="busy()" (click)="prepare()" data-testid="g-df-save">{{ i18n.t('g.d.prepare') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [`.g-acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }`],
})
export class GDividendsPage extends GBase implements OnInit {
  protected readonly runs = signal<Row[]>([]);
  protected readonly error = signal('');
  protected readonly run = signal<Row | null>(null);
  protected readonly prepOpen = signal(false);
  protected f: Row = {};

  ngOnInit(): void {
    void this.load();
  }

  protected menuFor(r: Row): MenuItem[] {
    const items: MenuItem[] = [{ id: 'open', label: this.i18n.t('g.open'), testid: 'g-d-open-' + r['id'] }];
    if (r['status'] === 'draft' && this.can('approve_dividends')) items.push({ id: 'post', label: this.i18n.t('g.d.post'), primary: true, testid: 'g-d-post-' + r['id'] });
    if (r['status'] === 'draft' && this.can('prepare_dividends')) items.push({ id: 'discard', label: this.i18n.t('g.d.discard'), danger: true });
    return items;
  }

  protected picked(id: string, r: Row): void {
    if (id === 'open') void this.open(r);
    if (id === 'post') void this.post(r);
    if (id === 'discard') void this.discard(r);
  }

  async load(): Promise<void> {
    this.error.set('');
    try {
      this.runs.set(((await this.api.get('/dividends'))['runs'] as Row[]) ?? []);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  protected async open(r: Row): Promise<void> {
    try {
      this.run.set((await this.api.get(`/dividends/${r['id']}`))['run'] ?? r);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  protected openPrepare(): void {
    const y = new Date().getFullYear();
    this.f = { period_from: `${y}-01-01`, period_to: this.today(), profit_pool: '', base: 'closing', method: 'rate', rate: 2, note: '' };
    this.prepOpen.set(true);
  }

  protected async prepare(): Promise<void> {
    const pool = this.amount(this.f['profit_pool']);
    if (pool < 1) return this.stop(this.i18n.t('g.need.amount'));
    if (String(this.f['note'] ?? '').trim().length < 3) return this.stop(this.i18n.t('g.need.reason'));
    const body: Row = { period_from: this.f['period_from'], period_to: this.f['period_to'], profit_pool: pool, base: this.f['base'], method: this.f['method'], note: String(this.f['note']).trim(), ...(this.f['method'] === 'rate' ? { rate: Number(this.f['rate']) } : {}) };
    let run: Row = {};
    if (await this.act(async () => (run = (await this.api.post('/dividends', body))['run'] ?? {}), this.i18n.t('g.d.prepared.ok'))) {
      this.prepOpen.set(false);
      await this.load();
      if (run['id']) this.run.set(run);
    }
  }

  protected async post(r: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.d.post'), `${this.tsh(r['total'])}\n${this.i18n.t('g.d.post.sure')}`, this.i18n.t('g.d.post')))) return;
    if (await this.act(() => this.api.post(`/dividends/${r['id']}/post`), this.i18n.t('g.d.posted'))) await Promise.all([this.load(), this.ctx.reload()]);
  }

  protected async discard(r: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.d.discard'), `${this.day(r['period_from'])} – ${this.day(r['period_to'])}`, this.i18n.t('g.d.discard'), true))) return;
    if (await this.act(() => this.api.post(`/dividends/${r['id']}/discard`), this.i18n.t('g.saved'))) await this.load();
  }
}
