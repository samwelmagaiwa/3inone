import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';
import { MemberPick, PickedMember } from './member-pick';

const CATEGORIES = ['leadership', 'project', 'financial', 'policy', 'proposal', 'general'];
const VISIBILITY = ['after_close', 'after_publish', 'live'];

/** "2026-11-27T09:00" for an <input type="datetime-local"> from the server's "2026-11-27 09:00:00". */
function local(v: string | null | undefined): string {
  return v ? String(v).replace(' ', 'T').slice(0, 16) : '';
}

/**
 * Voting: elections (candidates for an office) and decisions (approve / reject / abstain on an agenda), each with its own voters, quorum,
 * threshold, dates, secret or open ballot and when results are shown. Leaders prepare, publish, pause, close, cancel (with a reason),
 * extend, and publish the results; members vote on the phone.
 */
@Component({
  selector: 'app-g-votings',
  imports: [RowMenuComponent, FormsModule, ModalDialogComponent, MemberPick],
  template: `
    <div class="ad ph-page" data-testid="g-votings">
      <div class="g-toolbar">
        <div class="ph-chips g-seg">
          @for (s of vStatuses; track s) {
            <button type="button" class="pill-tab" [class.is-active]="vStatus() === s" (click)="vStatus.set(s)" [attr.data-testid]="'g-v-st-' + (s || 'all')">{{ s ? status(s) : i18n.t('g.all') }}</button>
          }
        </div>
        <input class="g-search" [ngModel]="find()" (ngModelChange)="find.set($event)" [placeholder]="i18n.t('g.find.ph')" [attr.aria-label]="i18n.t('g.search')" />
        <button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('ad.apply') }}</button>
        @if (can('manage_votings')) { <button type="button" class="btn-primary ph-btn" (click)="openForm(null)" data-testid="g-v-new">{{ i18n.t('g.v.new') }}</button> }
        <span class="g-count">{{ i18n.t('g.count', shownCount()) }}</span>
      </div>
      @if (error()) { <section class="ph-card"><p>{{ error() }}</p></section> }
      <div class="table-scroll-container fit-page" data-testid="g-v-list">
          <table class="grid-table">
            <thead>
              <tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('g.reference') }}</th>
              <th>{{ i18n.t('g.pr.title') }}</th>
              <th>{{ i18n.t('g.v.kind') }}</th>
              <th>{{ i18n.t('g.kind') }}</th>
              <th>{{ i18n.t('g.v.opens') }}</th>
              <th>{{ i18n.t('g.v.closes') }}</th>
              <th class="text-right">{{ i18n.t('g.v.turnout.short') }}</th>
              <th>{{ i18n.t('g.status') }}</th>
              <th class="text-right">{{ i18n.t('g.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              @for (v of shown(); track v['id']) {
                <tr>
                  <td class="no-col">{{ $index + 1 }}</td>
                  <td>{{ v['reference'] }}</td>
                  <td class="font-bold">{{ v['title'] }}@if (v['position']) { <span class="ph-muted"> · {{ v['position'] }}</span> }</td>
                  <td>{{ i18n.t('g.v.kind.' + v['kind']) }}</td>
                  <td>{{ i18n.t('g.v.cat.' + v['category']) }}</td>
                  <td>{{ when(v['opens_at']) }}</td>
                  <td>{{ when(v['closes_at']) }}</td>
                  <td class="text-right">{{ v['progress'] ? n(v['progress']['turnout']) + ' / ' + n(v['progress']['eligible'], n(v['eligible_count'])) : '—' }}</td>
                  <td><span class="ph-badge" [class]="tone(v['status'] === 'open' ? 'active' : v['status'])">{{ status(v['status']) }}</span></td>
                  <td class="text-right">@if (menuFor(v).length) { <app-row-menu [items]="menuFor(v)" [testid]="'g-v-menu-' + v['id']" (picked)="picked($event, v)" /> } @else { — }</td>
                </tr>
              } @empty {
                <tr><td colspan="10" class="ph-muted">{{ i18n.t('g.v.none') }}</td></tr>
              }
            </tbody>
          </table>
        </div>
    </div>

    <!-- one voting and its results -->
    <app-modal-dialog [show]="!!voting()" [eyebrow]="voting()?.['reference'] ?? ''" [title]="voting()?.['title'] ?? ''" size="lg" (close)="voting.set(null)">
      <div slot="body">
        @if (voting(); as v) {
          <div class="ph-page" style="gap: 10px">
            @if (v['description']) { <p style="white-space: pre-line">{{ v['description'] }}</p> }
            <div class="ph-tiles">
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.status') }}</span><b>{{ status(v['status']) }}</b></div>
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.v.voters') }}</span><b>{{ v['eligible_count'] }}</b></div>
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.v.quorum') }}</span><b>{{ v['quorum_percent'] }}%</b></div>
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.v.threshold') }}</span><b>{{ v['threshold_percent'] }}%</b></div>
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.v.ballot') }}</span><b>{{ v['secret'] ? i18n.t('g.v.secret') : i18n.t('g.v.open.ballot') }}</b></div>
            </div>
            @if (v['results']; as r) {
              <div class="ph-card ph-joined">
                <section class="ph-sec"><div class="ph-row"><h3>{{ i18n.t('g.v.results') }}</h3>
                  <span class="ph-muted">{{ i18n.t('g.v.turnout', n(r['turnout']), n(r['eligible'])) }} · {{ r['participation_percent'] ?? 0 }}%</span></div>
                  @if (r['quorum_met'] === false) { <p class="ph-bad" style="font-size: 13px">{{ i18n.t('g.v.no.quorum') }}</p> }
                  @if (r['decision']) { <p><b class="ph-accent">{{ i18n.t('g.v.decision.' + r['decision']) }}</b></p> }</section>
                @for (o of r['options'] ?? []; track o['option_id']) {
                  <section class="ph-sec">
                    <div class="ph-row"><span>{{ o['label'] }}@if (o['option_id'] === r['winner_option_id']) { <b class="ph-good"> ✓</b> }</span><b>{{ o['votes'] }} · {{ o['percent'] }}%</b></div>
                    <div class="g-bar"><i [style.width.%]="o['percent']"></i></div>
                  </section>
                }
              </div>
            } @else {
              <div class="ph-card">
                <h3>{{ i18n.t('g.v.options') }}</h3>
                @for (o of v['options'] ?? []; track o['id']) { <p>• {{ o['label'] }}@if (o['description']) { <span class="ph-muted"> · {{ o['description'] }}</span> }</p> }
                <p class="ph-muted">{{ i18n.t('g.v.results.later') }}</p>
              </div>
            }
            @if (can('view_voting_reports') && (v['status'] === 'closed' || v['status'] === 'open' || v['status'] === 'paused')) {
              <button type="button" class="btn-primary is-info ph-btn" (click)="report(v)">{{ i18n.t('g.v.report.csv') }}</button>
            }
          </div>
        }
      </div>
      <div slot="footer" class="flex gap-2"><button type="button" class="btn-outline ph-btn" (click)="voting.set(null)">{{ i18n.t('common.close') }}</button></div>
    </app-modal-dialog>

    <!-- a later closing time -->
    <app-modal-dialog [show]="!!extending()" [eyebrow]="extending()?.['title'] ?? ''" [title]="i18n.t('g.v.extend')" size="sm" (close)="extending.set(null)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.v.closes') }}<input class="modal-input" type="datetime-local" [(ngModel)]="extendTo" name="ext" /></label>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="extending.set(null)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary ph-btn" [disabled]="busy()" (click)="saveExtend()">{{ i18n.t('g.v.extend') }}</button>
      </div>
    </app-modal-dialog>

    <!-- prepare a voting -->
    <app-modal-dialog [show]="formOpen()" [eyebrow]="i18n.t('nav.g.votings')" [title]="vf['id'] ? i18n.t('g.edit') : i18n.t('g.v.new')" size="lg" (close)="formOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.pr.title') }} *<input class="modal-input" [(ngModel)]="vf['title']" name="vt" data-testid="g-vf-title" /></label>
        <div class="ph-row" style="gap: 10px; flex-wrap: wrap">
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.v.kind') }}<select class="modal-input" [(ngModel)]="vf['kind']" name="vk" data-testid="g-vf-kind"><option value="decision">{{ i18n.t('g.v.kind.decision') }}</option><option value="election">{{ i18n.t('g.v.kind.election') }}</option></select></label>
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.kind') }}<select class="modal-input" [(ngModel)]="vf['category']" name="vc">@for (c of categories; track c) { <option [value]="c">{{ i18n.t('g.v.cat.' + c) }}</option> }</select></label>
        </div>
        @if (vf['kind'] === 'election') { <label class="ph-field">{{ i18n.t('g.v.position') }} *<input class="modal-input" [(ngModel)]="vf['position']" name="vp" [placeholder]="i18n.t('g.office.katibu')" /></label> }
        <label class="ph-field">{{ i18n.t('g.description') }}<textarea class="modal-input" rows="3" [(ngModel)]="vf['description']" name="vd"></textarea></label>
        <div class="ph-row" style="gap: 10px; flex-wrap: wrap">
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.v.opens') }} *<input class="modal-input" type="datetime-local" [(ngModel)]="vf['opens_at']" name="vo" data-testid="g-vf-opens" /></label>
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.v.closes') }} *<input class="modal-input" type="datetime-local" [(ngModel)]="vf['closes_at']" name="vcl" data-testid="g-vf-closes" /></label>
        </div>
        <div class="ph-row" style="gap: 10px; flex-wrap: wrap">
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.v.quorum') }} %<input class="modal-input" type="number" min="0" max="100" [(ngModel)]="vf['quorum_percent']" name="vq" /></label>
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.v.threshold') }} %<input class="modal-input" type="number" min="1" max="100" [(ngModel)]="vf['threshold_percent']" name="vth" /></label>
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.v.show.results') }}<select class="modal-input" [(ngModel)]="vf['results_visibility']" name="vrv">@for (r of visibility; track r) { <option [value]="r">{{ i18n.t('g.v.vis.' + r) }}</option> }</select></label>
        </div>
        <label class="ph-row"><span>{{ i18n.t('g.v.secret') }}</span><input type="checkbox" [(ngModel)]="vf['secret']" name="vs" /></label>
        @if (!vf['secret']) { <label class="ph-row"><span>{{ i18n.t('g.v.change') }}</span><input type="checkbox" [(ngModel)]="vf['allow_change']" name="vac" /></label> }
        <label class="ph-row"><span>{{ i18n.t('g.v.progress') }}</span><input type="checkbox" [(ngModel)]="vf['show_progress']" name="vsp" /></label>
        <label class="ph-field">{{ i18n.t('g.v.who') }}<select class="modal-input" [(ngModel)]="vf['eligibility']" name="ve"><option value="active">{{ i18n.t('g.v.who.all') }}</option><option value="selected">{{ i18n.t('g.v.who.selected') }}</option></select></label>
        @if (vf['eligibility'] === 'selected') {
          @for (p of voters(); track p.id) { <div class="ph-row ph-card" style="padding: 6px 12px"><span>{{ p.name }}</span><button type="button" class="link-btn danger" (click)="voters.set(dropFrom(voters(), p.id))">{{ i18n.t('g.remove') }}</button></div> }
          <app-g-member-pick [label]="i18n.t('g.mt.add.person')" [value]="null" (picked$)="voters.set(addTo(voters(), $event))" />
        }
        @if (vf['kind'] === 'election') {
          <h3>{{ i18n.t('g.v.candidates') }}</h3>
          @for (c of candidates(); track c.id) { <div class="ph-row ph-card" style="padding: 6px 12px"><span>{{ c.name }}</span><button type="button" class="link-btn danger" (click)="candidates.set(dropFrom(candidates(), c.id))">{{ i18n.t('g.remove') }}</button></div> }
          <app-g-member-pick [label]="i18n.t('g.v.add.candidate')" [value]="null" (picked$)="candidates.set(addTo(candidates(), $event))" />
        } @else {
          <p class="ph-muted">{{ i18n.t('g.v.decision.hint') }}</p>
        }
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="formOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-success ph-btn" [disabled]="busy()" (click)="save()" data-testid="g-vf-save">{{ i18n.t('g.v.save.draft') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [
    `
      .g-acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; align-items: center; }
      .g-bar { height: 8px; border-radius: 99px; background: rgba(255, 255, 255, 0.18); overflow: hidden; margin: 6px 0; }
      .g-bar i { display: block; height: 100%; background: linear-gradient(90deg, #1ba3c7, #20b8ce); }
    `,
  ],
})
export class GVotingsPage extends GBase implements OnInit {
  protected readonly categories = CATEGORIES;
  protected readonly visibility = VISIBILITY;
  protected readonly rows = signal<Row[]>([]);
  protected readonly error = signal('');
  protected readonly voting = signal<Row | null>(null);
  protected readonly formOpen = signal(false);
  protected vf: Row = {};
  protected readonly voters = signal<PickedMember[]>([]);
  protected readonly candidates = signal<PickedMember[]>([]);
  protected readonly extending = signal<Row | null>(null);
  protected extendTo = '';

  protected readonly vStatuses = ['', 'draft', 'scheduled', 'open', 'paused', 'closed', 'cancelled'];
  protected readonly vStatus = signal('');
  protected readonly keys = ['title', 'reference', 'position', 'series'];

  /** The votings of the chosen status that hold what was typed. */
  protected shown(): Row[] {
    const s = this.vStatus();
    return this.filtered(this.rows(), this.keys).filter((v) => !s || v['status'] === s);
  }

  protected shownCount(): number {
    return this.shown().length;
  }

  ngOnInit(): void {
    void this.load();
  }

  protected menuFor(v: Row): MenuItem[] {
    const s = v['status'];
    const items: MenuItem[] = [{ id: 'open', label: this.i18n.t('g.open'), testid: 'g-v-open-' + v['id'] }];
    if (this.can('manage_votings')) {
      if (s === 'draft') {
        items.push({ id: 'edit', label: this.i18n.t('g.edit') });
        items.push({ id: 'publish', label: this.i18n.t('g.v.publish'), primary: true, testid: 'g-v-publish-' + v['id'] });
        items.push({ id: 'delete', label: this.i18n.t('common.delete'), danger: true });
      }
      if (s === 'open') items.push({ id: 'pause', label: this.i18n.t('g.v.pause') });
      if (s === 'paused') items.push({ id: 'resume', label: this.i18n.t('g.v.resume'), primary: true });
      if (s === 'open' || s === 'paused') items.push({ id: 'close', label: this.i18n.t('g.v.close') });
      if (s === 'scheduled' || s === 'open' || s === 'paused') items.push({ id: 'extend', label: this.i18n.t('g.v.extend') });
      if (s !== 'closed' && s !== 'cancelled') items.push({ id: 'cancel', label: this.i18n.t('g.v.cancel'), danger: true });
    }
    if (s === 'closed' && !v['results_published'] && this.can('publish_voting_results')) items.push({ id: 'publish-results', label: this.i18n.t('g.v.publish.results'), primary: true });
    return items;
  }

  protected picked(id: string, v: Row): void {
    switch (id) {
      case 'open': void this.open(v); break;
      case 'edit': this.openForm(v); break;
      case 'delete': void this.remove(v); break;
      case 'extend': this.extend(v); break;
      case 'cancel': void this.cancel(v); break;
      default: void this.move(v, id as 'publish' | 'pause' | 'resume' | 'close' | 'publish-results');
    }
  }

  async load(): Promise<void> {
    this.error.set('');
    try {
      this.rows.set(((await this.api.get('/votings'))['votings'] as Row[]) ?? []);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  protected addTo(list: PickedMember[], m: PickedMember | null): PickedMember[] {
    return !m || list.some((x) => x.id === m.id) ? list : [...list, m];
  }

  protected dropFrom(list: PickedMember[], id: number): PickedMember[] {
    return list.filter((x) => x.id !== id);
  }

  protected async open(v: Row): Promise<void> {
    try {
      this.voting.set((await this.api.get(`/votings/${v['id']}`))['voting'] ?? v);
    } catch {
      this.voting.set(v);
    }
  }

  protected openForm(v: Row | null): void {
    const now = new Date();
    const inDays = (d: number) => local(new Date(now.getTime() + d * 86400000 - now.getTimezoneOffset() * 60000).toISOString());
    this.vf = v
      ? { ...v, opens_at: local(v['opens_at']), closes_at: local(v['closes_at']) }
      : { kind: 'decision', category: 'general', eligibility: 'active', quorum_percent: 50, threshold_percent: 50, secret: true, allow_change: false, show_progress: true, results_visibility: 'after_close', opens_at: inDays(1), closes_at: inDays(8) };
    this.voters.set([]);
    this.candidates.set(
      v && v['kind'] === 'election' ? ((v['options'] as Row[]) ?? []).filter((o) => o['member_id']).map((o) => ({ id: Number(o['member_id']), name: String(o['label']), number: '' })) : [],
    );
    this.formOpen.set(true);
  }

  protected async save(): Promise<void> {
    const f = this.vf;
    if (String(f['title'] ?? '').trim().length < 3) return this.stop(this.i18n.t('g.need.name'));
    if (!f['opens_at'] || !f['closes_at']) return this.stop(this.i18n.t('g.need.when'));
    if (f['kind'] === 'election' && String(f['position'] ?? '').trim().length < 2) return this.stop(this.i18n.t('g.need.position'));
    if (f['kind'] === 'election' && this.candidates().length < 2) return this.stop(this.i18n.t('g.need.candidates'));
    if (f['eligibility'] === 'selected' && !this.voters().length && !f['id']) return this.stop(this.i18n.t('g.need.member'));
    const body: Row = {
      title: String(f['title']).trim(),
      kind: f['kind'],
      category: f['category'],
      description: String(f['description'] ?? '').trim() || null,
      eligibility: f['eligibility'],
      quorum_percent: Number(f['quorum_percent']) || 0,
      threshold_percent: Number(f['threshold_percent']) || 50,
      secret: !!f['secret'],
      allow_change: !f['secret'] && !!f['allow_change'],
      show_progress: !!f['show_progress'],
      results_visibility: f['results_visibility'],
      opens_at: String(f['opens_at']).replace('T', ' '),
      closes_at: String(f['closes_at']).replace('T', ' '),
    };
    if (f['kind'] === 'election') {
      body['position'] = String(f['position']).trim();
      body['options'] = this.candidates().map((c) => ({ label: c.name, member_id: c.id }));
    }
    if (f['eligibility'] === 'selected' && this.voters().length) body['member_ids'] = this.voters().map((p) => p.id);
    const id = f['id'];
    if (await this.act(() => (id ? this.api.put(`/votings/${id}`, body) : this.api.post('/votings', body)), this.i18n.t('g.v.saved'))) {
      this.formOpen.set(false);
      await this.load();
    }
  }

  protected async move(v: Row, action: 'publish' | 'pause' | 'resume' | 'close' | 'publish-results'): Promise<void> {
    const word = this.i18n.t(action === 'publish-results' ? 'g.v.publish.results' : 'g.v.' + action);
    if (!(await this.sure(word, v['title'], word, action === 'close'))) return;
    if (await this.act(() => this.api.post(`/votings/${v['id']}/${action}`), this.i18n.t('g.saved'))) await this.load();
  }

  protected async cancel(v: Row): Promise<void> {
    const why = await this.reason(this.i18n.t('g.v.cancel'), v['title'], this.i18n.t('g.v.cancel'));
    if (why === null) return;
    if (await this.act(() => this.api.post(`/votings/${v['id']}/cancel`, { reason: why }), this.i18n.t('g.saved'))) await this.load();
  }

  protected extend(v: Row): void {
    this.extendTo = local(v['closes_at']);
    this.extending.set(v);
  }

  protected async saveExtend(): Promise<void> {
    const v = this.extending();
    if (!v) return;
    if (!this.extendTo) return this.stop(this.i18n.t('g.need.when'));
    if (await this.act(() => this.api.post(`/votings/${v['id']}/extend`, { closes_at: this.extendTo.replace('T', ' ') }), this.i18n.t('g.saved'))) {
      this.extending.set(null);
      await this.load();
    }
  }

  protected async remove(v: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('common.delete'), v['title'], this.i18n.t('common.delete'), true))) return;
    if (await this.act(() => this.api.del(`/votings/${v['id']}`), this.i18n.t('g.saved'))) await this.load();
  }

  protected async report(v: Row): Promise<void> {
    await this.act(() => this.api.download(`/votings/${v['id']}/report.csv`, `${v['reference'] ?? 'voting'}.csv`));
  }
}
