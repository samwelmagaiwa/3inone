import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';
import { MemberPick, PickedMember } from './member-pick';

const STATUSES = ['proposed', 'active', 'completed', 'rejected', 'cancelled', ''];

/**
 * Projects (miradi): a member proposes, the projects committee reviews (yes or no, with a reason), the chair decides, the Projects
 * Chairperson names a manager, logs progress and closes it. The budget is a plan; money still moves only through verified payments.
 */
@Component({
  selector: 'app-g-projects',
  imports: [RowMenuComponent, FormsModule, ModalDialogComponent, MemberPick],
  template: `
    <div class="ad ph-page" data-testid="g-projects">
      <div class="ph-row" style="flex-wrap: wrap">
        <div class="ph-chips">
          @for (s of statuses; track s) {
            <button type="button" class="pill-tab" [class.is-active]="filter() === s" (click)="filter.set(s); load()">{{ s ? status(s) : i18n.t('g.all') }}</button>
          }
        </div>
        <button type="button" class="btn-primary ph-btn" (click)="openForm(null)" data-testid="g-pr-new">{{ i18n.t('g.pr.propose') }}</button>
      </div>
      @if (error()) { <section class="ph-card"><p>{{ error() }}</p></section> }
      <div class="table-scroll-container fit-page" data-testid="g-pr-list">
          <table class="grid-table">
            <thead>
              <tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('g.ref') }}</th>
              <th>{{ i18n.t('g.pr.title') }}</th>
              <th>{{ i18n.t('g.pr.by.short') }}</th>
              <th>{{ i18n.t('g.pr.manager') }}</th>
              <th class="text-right">{{ i18n.t('g.pr.budget') }}</th>
              <th class="text-right">{{ i18n.t('g.pr.spent') }}</th>
              <th class="text-right">{{ i18n.t('g.pr.progress') }}</th>
              <th>{{ i18n.t('g.pr.committee') }}</th>
              <th>{{ i18n.t('g.status') }}</th>
              <th class="text-right">{{ i18n.t('g.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              @for (p of rows(); track p['id']) {
                <tr>
                  <td class="no-col">{{ $index + 1 }}</td>
                  <td>{{ p['reference'] }}</td>
                  <td class="font-bold">{{ p['title'] }}</td>
                  <td>{{ p['proposer_name'] || '—' }}</td>
                  <td>{{ p['manager_name'] || '—' }}</td>
                  <td class="text-right">{{ tsh(p['budget']) }}</td>
                  <td class="text-right">{{ tsh(p['spent'] ?? 0) }}</td>
                  <td class="text-right">{{ p['progress'] ?? 0 }}%</td>
                  <td>{{ i18n.t('g.pr.votes', n(p['supports']), n(p['opposes'])) }}</td>
                  <td><span class="ph-badge" [class]="tone(p['status'])">{{ status(p['status']) }}</span></td>
                  <td class="text-right">@if (menuFor(p).length) { <app-row-menu [items]="menuFor(p)" [testid]="'g-pr-menu-' + p['id']" (picked)="picked($event, p)" /> } @else { — }</td>
                </tr>
              } @empty {
                <tr><td colspan="11" class="ph-muted">{{ i18n.t('g.pr.none') }}</td></tr>
              }
            </tbody>
          </table>
        </div>
    </div>

    <!-- one project -->
    <app-modal-dialog [show]="!!project()" [eyebrow]="project()?.['reference'] ?? ''" [title]="project()?.['title'] ?? ''" size="xl" (close)="project.set(null)">
      <div slot="body">
        @if (project(); as p) {
          <div class="ph-page" style="gap: 10px">
            <div class="ph-tiles">
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.status') }}</span><b [class]="tone(p['status'])">{{ status(p['status']) }}</b></div>
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.pr.budget') }}</span><b>{{ tsh(p['budget']) }}</b></div>
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.pr.committed') }}</span><b>{{ tsh(p['committed'] ?? 0) }}</b></div>
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.pr.spent') }}</span><b class="ph-bad">{{ tsh(p['spent'] ?? 0) }}</b></div>
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.pr.progress') }}</span><b class="ph-accent">{{ p['progress'] ?? 0 }}%</b></div>
            </div>
            <div class="ph-card ph-joined ph-cols">
              <section class="ph-sec">
                <h3>{{ i18n.t('g.details') }}</h3>
                @if (p['description']) { <p style="white-space: pre-line">{{ p['description'] }}</p> }
                @if (p['start_date']) { <div class="ph-line"><span>{{ i18n.t('g.pr.dates') }}</span><b>{{ day(p['start_date']) }} – {{ day(p['end_date']) }}</b></div> }
                <div class="ph-line"><span>{{ i18n.t('g.pr.manager') }}</span><b>{{ p['manager_name'] || '—' }}</b></div>
                @if (p['decision_note']) { <div class="ph-line"><span>{{ i18n.t('g.reason') }}</span><b>{{ p['decision_note'] }}</b></div> }
                @if (p['closing_note']) { <div class="ph-line"><span>{{ i18n.t('g.pr.closing') }}</span><b>{{ p['closing_note'] }}</b></div> }
              </section>
              <section class="ph-sec">
                <h3>{{ i18n.t('g.actions') }}</h3>
                <div class="g-acts">
                  @if (p['status'] === 'proposed' && can('recommend_projects')) {
                    <button type="button" class="btn-primary is-success ph-btn" (click)="review(p, true)" data-testid="g-pr-support">{{ i18n.t('g.pr.support') }}</button>
                    <button type="button" class="btn-primary is-danger ph-btn" (click)="review(p, false)">{{ i18n.t('g.pr.oppose') }}</button>
                  }
                  @if (p['status'] === 'proposed' && can('approve_projects')) {
                    <button type="button" class="btn-primary is-success ph-btn" (click)="decide(p, true)" data-testid="g-pr-approve">{{ i18n.t('g.approve') }}</button>
                    <button type="button" class="btn-primary is-danger ph-btn" (click)="decide(p, false)">{{ i18n.t('g.turn.down') }}</button>
                  }
                  @if ((p['status'] === 'proposed' || p['status'] === 'active') && can('manage_projects')) {
                    <button type="button" class="btn-outline ph-btn" (click)="openForm(p)">{{ i18n.t('g.edit') }}</button>
                  }
                  @if (p['status'] === 'active') {
                    <button type="button" class="btn-primary is-info ph-btn" (click)="openProgress(p)" data-testid="g-pr-progress">{{ i18n.t('g.pr.log') }}</button>
                  }
                  @if (p['status'] === 'active' && can('manage_projects')) {
                    <button type="button" class="btn-primary is-success ph-btn" (click)="close(p, 'completed')">{{ i18n.t('g.pr.complete') }}</button>
                    <button type="button" class="btn-primary is-danger ph-btn" (click)="close(p, 'cancelled')">{{ i18n.t('g.pr.cancel') }}</button>
                  }
                </div>
                <h3 style="margin-top: 10px">{{ i18n.t('g.pr.reviews') }}</h3>
                @for (r of p['reviews'] ?? []; track $index) {
                  <div class="ph-line"><span>{{ r['member_name'] }}@if (r['note']) { <span class="ph-muted"> · {{ r['note'] }}</span> }</span><b [class]="r['supports'] ? 'ph-good' : 'ph-bad'">{{ r['supports'] ? i18n.t('g.pr.support') : i18n.t('g.pr.oppose') }}</b></div>
                } @empty { <p class="ph-muted">{{ i18n.t('g.none') }}</p> }
              </section>
              <section class="ph-sec" style="grid-column: 1 / -1">
                <h3>{{ i18n.t('g.pr.updates') }}</h3>
                @for (u of p['updates'] ?? []; track $index) {
                  <div class="ph-line"><span>{{ u['progress'] }}% · {{ u['note'] }}</span><span class="ph-muted">{{ u['by_name'] }} · {{ when(u['created_at']) }}</span></div>
                } @empty { <p class="ph-muted">{{ i18n.t('g.none') }}</p> }
              </section>
            </div>
          </div>
        }
      </div>
      <div slot="footer" class="flex gap-2"><button type="button" class="btn-outline ph-btn" (click)="project.set(null)">{{ i18n.t('common.close') }}</button></div>
    </app-modal-dialog>

    <!-- propose or change -->
    <app-modal-dialog [show]="formOpen()" [eyebrow]="i18n.t('nav.g.projects')" [title]="pf['id'] ? i18n.t('g.edit') : i18n.t('g.pr.propose')" size="md" (close)="formOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.pr.title') }} *<input class="modal-input" [(ngModel)]="pf['title']" name="pt" data-testid="g-prf-title" /></label>
        <label class="ph-field">{{ i18n.t('g.description') }}<textarea class="modal-input" rows="4" [(ngModel)]="pf['description']" name="pd"></textarea></label>
        <label class="ph-field">{{ i18n.t('g.pr.budget') }} *<input class="modal-input" inputmode="numeric" [(ngModel)]="pf['budget']" name="pb" data-testid="g-prf-budget" /></label>
        <div class="ph-row" style="gap: 10px">
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.h.from') }}<input class="modal-input" type="date" [(ngModel)]="pf['start_date']" name="ps" /></label>
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.h.to') }}<input class="modal-input" type="date" [(ngModel)]="pf['end_date']" name="pe" /></label>
        </div>
        @if (pf['id'] && can('manage_projects')) { <app-g-member-pick [label]="i18n.t('g.pr.manager')" [value]="manager()" (picked$)="manager.set($event)" /> }
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="formOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-success ph-btn" [disabled]="busy()" (click)="save()" data-testid="g-prf-save">{{ i18n.t('g.save') }}</button>
      </div>
    </app-modal-dialog>

    <!-- progress -->
    <app-modal-dialog [show]="!!progressFor()" [eyebrow]="progressFor()?.['title'] ?? ''" [title]="i18n.t('g.pr.log')" size="sm" (close)="progressFor.set(null)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.pr.progress') }} ({{ progressValue }}%)<input type="range" min="0" max="100" step="5" [(ngModel)]="progressValue" name="pv" /></label>
        <label class="ph-field">{{ i18n.t('g.note') }} *<textarea class="modal-input" rows="3" [(ngModel)]="progressNote" name="pn"></textarea></label>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="progressFor.set(null)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-info ph-btn" [disabled]="busy()" (click)="saveProgress()">{{ i18n.t('g.save') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [
    `
      .g-acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
      .g-bar { height: 8px; border-radius: 99px; background: rgba(255, 255, 255, 0.18); overflow: hidden; margin: 6px 0; }
      .g-bar i { display: block; height: 100%; background: linear-gradient(90deg, #1ba3c7, #20b8ce); }
    `,
  ],
})
export class GProjectsPage extends GBase implements OnInit {
  protected readonly statuses = STATUSES;
  protected readonly filter = signal('');
  protected readonly rows = signal<Row[]>([]);
  protected readonly error = signal('');
  protected readonly project = signal<Row | null>(null);
  protected readonly formOpen = signal(false);
  protected pf: Row = {};
  protected readonly manager = signal<PickedMember | null>(null);
  protected readonly progressFor = signal<Row | null>(null);
  protected progressValue = 0;
  protected progressNote = '';

  ngOnInit(): void {
    void this.load();
  }

  protected menuFor(p: Row): MenuItem[] {
    const items: MenuItem[] = [{ id: 'open', label: this.i18n.t('g.open'), testid: 'g-pr-open-' + p['id'] }];
    if (p['status'] === 'proposed' && this.can('recommend_projects')) {
      items.push({ id: 'support', label: this.i18n.t('g.pr.support'), primary: true });
      items.push({ id: 'oppose', label: this.i18n.t('g.pr.oppose'), danger: true });
    }
    if (p['status'] === 'proposed' && this.can('approve_projects')) {
      items.push({ id: 'approve', label: this.i18n.t('g.approve'), primary: true });
      items.push({ id: 'reject', label: this.i18n.t('g.turn.down'), danger: true });
    }
    if ((p['status'] === 'proposed' || p['status'] === 'active') && this.can('manage_projects')) items.push({ id: 'edit', label: this.i18n.t('g.edit') });
    if (p['status'] === 'active') items.push({ id: 'progress', label: this.i18n.t('g.pr.log') });
    return items;
  }

  protected picked(id: string, p: Row): void {
    switch (id) {
      case 'open': void this.open(Number(p['id'])); break;
      case 'support': void this.review(p, true); break;
      case 'oppose': void this.review(p, false); break;
      case 'approve': void this.decide(p, true); break;
      case 'reject': void this.decide(p, false); break;
      case 'edit': this.openForm(p); break;
      case 'progress': this.openProgress(p); break;
    }
  }

  async load(): Promise<void> {
    this.error.set('');
    try {
      this.rows.set(((await this.api.get('/projects', { status: this.filter() || null }))['projects'] as Row[]) ?? []);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  protected async open(id: number): Promise<void> {
    try {
      this.project.set((await this.api.get(`/projects/${id}`))['project'] ?? null);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  private async after(p: Row | null): Promise<void> {
    await Promise.all([p ? this.open(Number(p['id'])) : Promise.resolve(), this.load(), this.ctx.reload()]);
  }

  protected openForm(p: Row | null): void {
    this.pf = p ? { ...p, budget: String(p['budget'] ?? '') } : { budget: '' };
    this.manager.set(p?.['manager_id'] ? { id: Number(p['manager_id']), name: String(p['manager_name'] ?? ''), number: '' } : null);
    this.formOpen.set(true);
  }

  protected async save(): Promise<void> {
    if (String(this.pf['title'] ?? '').trim().length < 3) return this.stop(this.i18n.t('g.need.name'));
    const body: Row = {
      title: String(this.pf['title']).trim(),
      description: String(this.pf['description'] ?? '').trim() || null,
      budget: this.amount(this.pf['budget']),
      start_date: this.pf['start_date'] || null,
      end_date: this.pf['end_date'] || null,
    };
    const id = this.pf['id'];
    if (id && this.can('manage_projects')) body['manager_id'] = this.manager()?.id ?? null;
    let saved: Row = {};
    if (await this.act(async () => (saved = (id ? await this.api.put(`/projects/${id}`, body) : await this.api.post('/projects', body))['project'] ?? {}), this.i18n.t('g.saved'))) {
      this.formOpen.set(false);
      await this.after(id ? saved : null);
    }
  }

  protected async review(p: Row, supports: boolean): Promise<void> {
    let note: string | null = null;
    if (!supports) {
      note = await this.reason(this.i18n.t('g.pr.oppose'), p['title'], this.i18n.t('g.pr.oppose'));
      if (note === null) return;
    } else if (!(await this.sure(this.i18n.t('g.pr.support'), p['title'], this.i18n.t('g.pr.support')))) {
      return;
    }
    if (await this.act(() => this.api.post(`/projects/${p['id']}/review`, { supports, ...(note ? { note } : {}) }), this.i18n.t('g.saved'))) await this.after(p);
  }

  protected async decide(p: Row, approve: boolean): Promise<void> {
    let note: string | null = null;
    if (!approve) {
      note = await this.reason(this.i18n.t('g.turn.down'), p['title'], this.i18n.t('g.turn.down'));
      if (note === null) return;
    } else if (!(await this.sure(this.i18n.t('g.approve'), `${p['title']} · ${this.tsh(p['budget'])}`, this.i18n.t('g.approve')))) {
      return;
    }
    if (await this.act(() => this.api.post(`/projects/${p['id']}/decide`, { approve, ...(note ? { note } : {}) }), this.i18n.t('g.saved'))) await this.after(p);
  }

  protected openProgress(p: Row): void {
    this.progressValue = Number(p['progress'] ?? 0);
    this.progressNote = '';
    this.progressFor.set(p);
  }

  protected async saveProgress(): Promise<void> {
    const p = this.progressFor();
    if (!p) return;
    if (this.progressNote.trim().length < 2) return this.stop(this.i18n.t('g.need.reason'));
    if (await this.act(() => this.api.post(`/projects/${p['id']}/progress`, { progress: Number(this.progressValue), note: this.progressNote.trim() }), this.i18n.t('g.saved'))) {
      this.progressFor.set(null);
      await this.after(p);
    }
  }

  protected async close(p: Row, outcome: 'completed' | 'cancelled'): Promise<void> {
    const note = await this.reason(outcome === 'completed' ? this.i18n.t('g.pr.complete') : this.i18n.t('g.pr.cancel'), p['title'], this.i18n.t('g.save'), outcome === 'cancelled');
    if (note === null) return;
    if (await this.act(() => this.api.post(`/projects/${p['id']}/close`, { outcome, note }), this.i18n.t('g.saved'))) await this.after(p);
  }
}
