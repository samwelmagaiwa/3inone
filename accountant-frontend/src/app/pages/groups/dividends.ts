import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { GBase } from './g-base';

/**
 * Dividends (gawio): a period is closed with the profit the group agreed to share; each member's share is worked out from their
 * savings (at the end of the period, or the average over it), as a rate of savings or as a share of the pool. One leader prepares,
 * another approves and posts it to savings; a period is never paid twice.
 */
@Component({
  selector: 'app-g-dividends',
  imports: [FormsModule, ModalDialogComponent],
  template: `
    <div class="ad ph-page" data-testid="g-dividends">
      <div class="ph-row"><span class="ph-muted">{{ i18n.t('g.d.hint') }}</span>
        @if (can('prepare_dividends')) { <button type="button" class="btn-primary ph-btn" (click)="openPrepare()" data-testid="g-d-new">{{ i18n.t('g.d.prepare') }}</button> }</div>
      @if (error()) { <section class="ph-card"><p>{{ error() }}</p></section> }
      <div class="ph-card ph-joined" data-testid="g-d-list">
        @for (r of runs(); track r['id']) {
          <section class="ph-sec">
            <div class="ph-row"><h3>{{ day(r['period_from']) }} – {{ day(r['period_to']) }}</h3><span class="ph-badge" [class]="tone(r['status'] === 'posted' ? 'done' : r['status'] === 'discarded' ? 'cancelled' : 'pending')">{{ status(r['status']) }}</span></div>
            <div class="ph-line"><span>{{ i18n.t('g.d.pool') }} {{ tsh(r['profit_pool']) }} · {{ i18n.t('g.d.base.' + r['base']) }} · {{ r['method'] === 'rate' ? i18n.t('g.d.rate', r['rate']) : i18n.t('g.d.method.share') }}</span><b class="ph-accent">{{ tsh(r['total']) }}</b></div>
            <div class="ph-line"><span class="ph-muted">{{ i18n.t('g.d.prepared', r['prepared_by_name'] || '—') }}@if (r['approved_by_name']) { · {{ i18n.t('g.d.approved', r['approved_by_name']) }} }</span><span class="ph-muted">{{ r['note'] }}</span></div>
            <div class="g-acts">
              <button type="button" class="btn-outline ph-btn" (click)="open(r)" [attr.data-testid]="'g-d-open-' + r['id']">{{ i18n.t('g.open') }}</button>
              @if (r['status'] === 'draft' && can('approve_dividends')) { <button type="button" class="btn-primary is-success ph-btn" (click)="post(r)" [attr.data-testid]="'g-d-post-' + r['id']">{{ i18n.t('g.d.post') }}</button> }
              @if (r['status'] === 'draft' && can('prepare_dividends')) { <button type="button" class="btn-primary is-danger ph-btn" (click)="discard(r)">{{ i18n.t('g.d.discard') }}</button> }
            </div>
          </section>
        } @empty { <section class="ph-sec"><p class="ph-muted">{{ i18n.t('g.d.none') }}</p></section> }
      </div>
    </div>

    <app-modal-dialog [show]="!!run()" [eyebrow]="i18n.t('nav.g.dividends')" [title]="(run()?.['period_from'] ? day(run()!['period_from']) + ' – ' + day(run()!['period_to']) : '')" size="lg" (close)="run.set(null)">
      <div slot="body">
        <div class="ph-card ph-joined">
          @for (l of run()?.['lines'] ?? []; track l['member_id']) {
            <section class="ph-sec"><div class="ph-line"><span>{{ l['name'] }} <span class="ph-muted">{{ l['member_number'] }}</span></span><span class="ph-muted">{{ i18n.t('g.d.on', tsh(l['base'])) }}</span><b class="ph-good">{{ tsh(l['amount']) }}</b></div></section>
          } @empty { <section class="ph-sec"><p class="ph-muted">{{ i18n.t('g.none') }}</p></section> }
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
