import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';

const STATUSES = ['', 'submitted', 'active', 'suspended', 'exited', 'rejected', 'deceased'];
export const G_OFFICES = ['mwenyekiti', 'makamu_mwenyekiti', 'mweka_hazina', 'mweka_hazina_msaidizi', 'katibu', 'katibu_msaidizi', 'mwenyekiti_miradi', 'kamati_miradi'];
/** action => the statuses it starts from (GroupMembers::MOVES). */
const MOVES: Record<string, string[]> = {
  approve: ['submitted'],
  reject: ['submitted'],
  suspend: ['active'],
  reinstate: ['suspended'],
  exit: ['active', 'suspended'],
  deceased: ['active', 'suspended'],
};
const RELATIONSHIPS = ['parent', 'spouse', 'child', 'parent_in_law', 'other'];
const FIELDS = ['full_name', 'phone', 'alt_phone', 'email', 'nida', 'date_of_birth', 'gender', 'region', 'district', 'ward', 'street', 'occupation', 'notes'];

/**
 * The members: find, filter by status, add (an application, or someone who was a member before the app with their old number and the
 * day they joined), change details, approve or move on, give an office, give a sign-in, and see each member's file and money.
 */
@Component({
  selector: 'app-g-members',
  imports: [FormsModule, ModalDialogComponent, RowMenuComponent],
  template: `
    <div class="ad ph-page" data-testid="g-members">
      <div class="g-toolbar">
        <div class="ph-chips g-seg">
          @for (s of statuses; track s) {
            <button type="button" class="pill-tab" [class.is-active]="status_() === s" (click)="pickStatus(s)" [attr.data-testid]="'g-mst-' + (s || 'all')">{{ s ? status(s) : i18n.t('g.all') }}</button>
          }
        </div>
        <input class="g-search" [ngModel]="q()" (ngModelChange)="q.set($event)" (keyup.enter)="load(1)" [placeholder]="i18n.t('g.pick.ph')" [attr.aria-label]="i18n.t('g.search')" data-testid="g-m-q" />
        <button type="button" class="btn-outline ph-btn" (click)="load(1)">{{ i18n.t('ad.apply') }}</button>
        @if (can('manage_members')) {
          <button type="button" class="btn-primary ph-btn" (click)="openNew()" data-testid="g-m-new">{{ i18n.t('g.m.add') }}</button>
        }
        <span class="g-count">{{ i18n.t('g.count', total()) }}</span>
      </div>

      @if (error()) {
        <section class="ph-card"><p>{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load(page())">{{ i18n.t('pl.retry') }}</button></section>
      } @else {
        <div class="table-scroll-container fit-page" data-testid="g-m-list">
          <table class="grid-table">
            <thead>
              <tr>
                <th class="no-col">#</th>
                <th>{{ i18n.t('g.name') }}</th>
                <th>{{ i18n.t('g.number') }}</th>
                <th>{{ i18n.t('g.f.phone') }}</th>
                <th>{{ i18n.t('g.office') }}</th>
                <th>{{ i18n.t('g.status') }}</th>
                <th>{{ i18n.t('g.f.joined_on') }}</th>
                <th class="text-right">{{ i18n.t('g.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              @for (m of rows(); track m['id']; let i = $index) {
                <tr [attr.data-testid]="'g-m-' + m['id']">
                  <td class="no-col">{{ rowNo(i, page()) }}</td>
                  <td class="font-bold">{{ m['full_name'] }}</td>
                  <td>{{ m['member_number'] || m['application_ref'] || '—' }}</td>
                  <td>{{ m['phone'] }}</td>
                  <td>{{ m['office'] ? office(m['office']) : '—' }}</td>
                  <td><span class="ph-badge" [class]="tone(m['status'])">{{ status(m['status']) }}</span></td>
                  <td>{{ m['joined_on'] ? day(m['joined_on']) : '—' }}</td>
                  <td class="text-right"><app-row-menu [items]="menuFor(m)" [testid]="'g-m-menu-' + m['id']" (picked)="picked($event, m)" /></td>
                </tr>
              } @empty {
                <tr><td colspan="8" class="ph-muted">{{ i18n.t('g.m.empty') }}</td></tr>
              }
            </tbody>
          </table>
        </div>
        <div class="ph-row">
          <button type="button" class="btn-outline ph-btn" [disabled]="page() <= 1" (click)="load(page() - 1)">{{ i18n.t('g.prev') }}</button>
          <span class="ph-muted">{{ i18n.t('g.page', page()) }}</span>
          <button type="button" class="btn-outline ph-btn" [disabled]="!more()" (click)="load(page() + 1)">{{ i18n.t('g.next') }}</button>
        </div>
      }
    </div>

    <!-- add or change a member -->
    <app-modal-dialog [show]="formOpen()" [eyebrow]="i18n.t('nav.g.members')" [title]="editId() ? i18n.t('g.m.edit') : i18n.t('g.m.add')" size="lg" (close)="formOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 10px; grid-template-columns: repeat(auto-fill, minmax(min(260px, 100%), 1fr))">
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.full_name') }} *<input class="modal-input" [(ngModel)]="f['full_name']" name="fn" data-testid="g-f-name" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.phone') }} *<input class="modal-input" type="tel" [(ngModel)]="f['phone']" name="fp" placeholder="07XXXXXXXX" data-testid="g-f-phone" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.alt_phone') }}<input class="modal-input" type="tel" [(ngModel)]="f['alt_phone']" name="fap" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.email') }}<input class="modal-input" type="email" [(ngModel)]="f['email']" name="fe" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.nida') }}<input class="modal-input" [(ngModel)]="f['nida']" name="fni" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.date_of_birth') }}<input class="modal-input" type="date" [(ngModel)]="f['date_of_birth']" name="fdob" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.gender') }}
          <select class="modal-input" [(ngModel)]="f['gender']" name="fg"><option value="">—</option><option value="male">{{ i18n.t('g.male') }}</option><option value="female">{{ i18n.t('g.female') }}</option></select></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.occupation') }}<input class="modal-input" [(ngModel)]="f['occupation']" name="fo" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.region') }}<input class="modal-input" [(ngModel)]="f['region']" name="fr" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.district') }}<input class="modal-input" [(ngModel)]="f['district']" name="fd" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.ward') }}<input class="modal-input" [(ngModel)]="f['ward']" name="fw" /></label>
        <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.street') }}<input class="modal-input" [(ngModel)]="f['street']" name="fs" /></label>
        @if (!editId()) {
          <label class="ph-field" style="grid-column: 1 / -1">{{ i18n.t('g.f.notes') }}<textarea class="modal-input" rows="2" [(ngModel)]="f['notes']" name="fnotes"></textarea></label>
          @if (can('approve_members')) {
            <label class="ph-row ph-card" style="grid-column: 1 / -1; cursor: pointer">
              <span><b>{{ i18n.t('g.m.existing') }}</b><br /><span class="ph-muted">{{ i18n.t('g.m.existing.hint') }}</span></span>
              <input type="checkbox" [(ngModel)]="existing" name="fex" data-testid="g-f-existing" />
            </label>
            @if (existing) {
              <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.member_number') }}<input class="modal-input" [(ngModel)]="f['member_number']" name="fmn" [placeholder]="i18n.t('g.m.number.auto')" /></label>
              <label class="ph-field" style="grid-column: auto">{{ i18n.t('g.f.joined_on') }}<input class="modal-input" type="date" [(ngModel)]="f['joined_on']" name="fj" [max]="today()" /></label>
            }
          }
        }
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="formOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-success ph-btn" [disabled]="busy()" (click)="save()" data-testid="g-f-save">{{ i18n.t('g.save') }}</button>
      </div>
    </app-modal-dialog>

    <!-- a member's file -->
    <app-modal-dialog [show]="!!file()" [eyebrow]="i18n.t('nav.g.members')" [title]="file()?.['member']?.['full_name'] ?? ''" size="xl" (close)="file.set(null)">
      <div slot="body">
        @if (file(); as fl) {
          @let m = fl['member'];
          <div class="ph-page" style="gap: 10px">
            <div class="ph-tiles">
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.status') }}</span><b [class]="tone(m['status'])">{{ status(m['status']) }}</b></div>
              <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.number') }}</span><b>{{ m['member_number'] || m['application_ref'] || '—' }}</b></div>
              @for (b of balances(fl); track b[0]) {
                <div class="ph-tile"><span class="ph-muted">{{ cat(b[0]) }}</span><b>{{ tsh(b[1]) }}</b></div>
              }
            </div>
            <div class="ph-card ph-joined ph-cols">
              <section class="ph-sec">
                <h3>{{ i18n.t('g.details') }}</h3>
                <div class="ph-line"><span>{{ i18n.t('g.f.phone') }}</span><b>{{ m['phone'] }}</b></div>
                @if (m['alt_phone']) { <div class="ph-line"><span>{{ i18n.t('g.f.alt_phone') }}</span><b>{{ m['alt_phone'] }}</b></div> }
                @if (m['email']) { <div class="ph-line"><span>{{ i18n.t('g.f.email') }}</span><b>{{ m['email'] }}</b></div> }
                @if (m['nida'] || m['nida_masked']) { <div class="ph-line"><span>{{ i18n.t('g.f.nida') }}</span><b>{{ m['nida'] || m['nida_masked'] }}</b></div> }
                @if (m['date_of_birth']) { <div class="ph-line"><span>{{ i18n.t('g.f.date_of_birth') }}</span><b>{{ day(m['date_of_birth']) }}</b></div> }
                @if (m['gender']) { <div class="ph-line"><span>{{ i18n.t('g.f.gender') }}</span><b>{{ i18n.t('g.' + m['gender']) }}</b></div> }
                @if (m['occupation']) { <div class="ph-line"><span>{{ i18n.t('g.f.occupation') }}</span><b>{{ m['occupation'] }}</b></div> }
                @if (place(m)) { <div class="ph-line"><span>{{ i18n.t('g.place') }}</span><b>{{ place(m) }}</b></div> }
                @if (m['joined_on']) { <div class="ph-line"><span>{{ i18n.t('g.f.joined_on') }}</span><b>{{ day(m['joined_on']) }}</b></div> }
                @if (m['referrer_name']) { <div class="ph-line"><span>{{ i18n.t('g.referrer') }}</span><b>{{ m['referrer_name'] }}</b></div> }
                <div class="ph-line"><span>{{ i18n.t('g.office') }}</span><b>{{ office(m['office']) }}</b></div>
                <div class="ph-line"><span>{{ i18n.t('g.signin') }}</span><b [class.ph-good]="m['has_sign_in']">{{ m['has_sign_in'] ? i18n.t('g.yes') : i18n.t('g.no') }}</b></div>
                @if (m['status_reason']) { <div class="ph-line"><span>{{ i18n.t('g.reason') }}</span><b>{{ m['status_reason'] }}</b></div> }
              </section>
              <section class="ph-sec">
                <h3>{{ i18n.t('g.actions') }}</h3>
                @if ((fl['approval_blockers'] ?? []).length) {
                  <p class="ph-warn" style="font-size: 13px">{{ i18n.t('g.m.blocked') }}</p>
                  @for (x of fl['approval_blockers']; track $index) { <p class="ph-muted">• {{ x['message'] ?? x }}</p> }
                }
                <div class="g-acts">
                  @if (can('manage_members')) {
                    <button type="button" class="btn-outline ph-btn" (click)="openEdit(m)" data-testid="g-m-edit">{{ i18n.t('g.m.edit') }}</button>
                  }
                  @if (can('approve_members')) {
                    @for (a of movesFor(m['status']); track a) {
                      <button type="button" class="btn-primary ph-btn" [class.is-success]="a === 'approve' || a === 'reinstate'" [class.is-danger]="a !== 'approve' && a !== 'reinstate'"
                        (click)="move(m, a)" [attr.data-testid]="'g-m-move-' + a">{{ i18n.t('g.move.' + a) }}</button>
                    }
                  }
                  @if (can('manage_members') && (m['status'] === 'active' || m['status'] === 'suspended')) {
                    <button type="button" class="btn-primary is-info ph-btn" (click)="signIn(m)" data-testid="g-m-signin">{{ m['has_sign_in'] ? i18n.t('g.signin.reset') : i18n.t('g.signin.give') }}</button>
                  }
                </div>
                @if (can('manage_offices') && m['status'] === 'active') {
                  <div class="ph-row" style="margin-top: 10px; flex-wrap: wrap">
                    <label class="ph-field" style="flex: 1">{{ i18n.t('g.office') }}
                      <select class="modal-input" [ngModel]="officeChoice()" (ngModelChange)="officeChoice.set($event)" name="office" data-testid="g-m-office">
                        <option value="">{{ i18n.t('g.office.none') }}</option>
                        @for (o of offices; track o) { <option [value]="o">{{ office(o) }}</option> }
                      </select></label>
                    <button type="button" class="btn-primary ph-btn" [disabled]="busy() || officeChoice() === (m['office'] ?? '')" (click)="setOffice(m)" data-testid="g-m-office-save">{{ i18n.t('g.save') }}</button>
                  </div>
                }
                @if (password(); as pw) {
                  <div class="ph-card" style="margin-top: 10px" data-testid="g-m-password">
                    <p class="ph-muted">{{ i18n.t('g.signin.once') }}</p>
                    <div class="ph-line"><span>{{ i18n.t('g.signin.login') }}</span><b>{{ pw['login'] }}</b></div>
                    <div class="ph-line"><span>{{ i18n.t('g.signin.password') }}</span><b class="ph-accent">{{ pw['temporary_password'] }}</b></div>
                  </div>
                }
              </section>
              <section class="ph-sec">
                <div class="ph-row"><h3>{{ i18n.t('g.dependants') }}</h3>
                  @if (can('manage_members')) { <button type="button" class="btn-outline ph-btn" (click)="addDependant(m)" data-testid="g-m-dep-add">{{ i18n.t('g.add') }}</button> }</div>
                @if (depOpen()) {
                  <div class="ph-row" style="flex-wrap: wrap; gap: 6px; margin: 6px 0">
                    <input class="modal-input" style="flex: 2" [(ngModel)]="dep['name']" name="dn" [placeholder]="i18n.t('g.f.full_name')" />
                    <select class="modal-input" style="flex: 1" [(ngModel)]="dep['relationship']" name="dr">
                      @for (r of relationships; track r) { <option [value]="r">{{ i18n.t('g.rel.' + r) }}</option> }
                    </select>
                    <input class="modal-input" style="flex: 1" [(ngModel)]="dep['phone']" name="dp" [placeholder]="i18n.t('g.f.phone')" />
                    <button type="button" class="btn-primary is-success ph-btn" (click)="saveDependant(m)">{{ i18n.t('g.save') }}</button>
                  </div>
                }
                @for (x of fl['dependants'] ?? []; track x['id']) {
                  <div class="ph-line"><span>{{ x['name'] }} <span class="ph-muted">· {{ i18n.t('g.rel.' + x['relationship']) }}</span></span>
                    @if (can('manage_members')) { <button type="button" class="link-btn danger" (click)="removeDependant(m, x)">{{ i18n.t('common.delete') }}</button> }</div>
                } @empty { <p class="ph-muted">{{ i18n.t('g.none') }}</p> }
              </section>
              <section class="ph-sec">
                <h3>{{ i18n.t('g.history') }}</h3>
                @for (e of (fl['events'] ?? []).slice(0, 12); track $index) {
                  <div class="ph-line"><span>{{ eventText(e) }}</span><b class="ph-muted">{{ when(e['created_at']) }}</b></div>
                } @empty { <p class="ph-muted">{{ i18n.t('g.none') }}</p> }
              </section>
            </div>
          </div>
        }
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="file.set(null)">{{ i18n.t('common.close') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [`.g-acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }`],
})
export class GMembersPage extends GBase implements OnInit {
  protected readonly statuses = STATUSES;
  protected readonly offices = G_OFFICES;
  protected readonly relationships = RELATIONSHIPS;

  protected readonly status_ = signal('');
  protected readonly q = signal('');
  protected readonly rows = signal<Row[]>([]);
  protected readonly page = signal(1);
  protected readonly more = signal(false);
  protected readonly total = signal(0);
  protected readonly error = signal('');

  protected readonly formOpen = signal(false);
  protected readonly editId = signal<number | null>(null);
  protected f: Row = {};
  protected existing = false;

  protected readonly file = signal<Row | null>(null);
  protected readonly officeChoice = signal('');
  protected readonly password = signal<Row | null>(null);
  protected readonly depOpen = signal(false);
  protected dep: Row = {};

  ngOnInit(): void {
    void this.load(1);
  }

  /** The status chip chosen ('' = every status); status() is the word for a status. */
  protected pickStatus(s: string): void {
    this.status_.set(s);
    void this.load(1);
  }

  async load(page: number): Promise<void> {
    this.error.set('');
    try {
      const p = await this.api.page('/members', 'members', { status: this.status_() || null, q: this.q() || null, page });
      this.rows.set(p.items);
      this.page.set(p.page);
      this.more.set(p.hasMore);
      this.total.set(p.total);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  /** The three-dots menu of a member's row: what this person may do with them now. */
  protected menuFor(m: Row): MenuItem[] {
    const items: MenuItem[] = [{ id: 'open', label: this.i18n.t('g.open'), primary: true, testid: 'g-m-open-' + m['id'] }];
    if (this.can('manage_members')) items.push({ id: 'edit', label: this.i18n.t('g.m.edit') });
    if (this.can('approve_members')) {
      for (const a of this.movesFor(m['status'])) items.push({ id: 'move:' + a, label: this.i18n.t('g.move.' + a), danger: a !== 'approve' && a !== 'reinstate', primary: a === 'approve' || a === 'reinstate' });
    }
    if (this.can('manage_members') && (m['status'] === 'active' || m['status'] === 'suspended')) {
      items.push({ id: 'signin', label: m['has_sign_in'] ? this.i18n.t('g.signin.reset') : this.i18n.t('g.signin.give') });
    }
    return items;
  }

  protected async picked(id: string, m: Row): Promise<void> {
    if (id === 'open') return this.open(Number(m['id']));
    if (id.startsWith('move:')) return this.move(m, id.slice(5));
    if (id === 'signin') {
      await this.open(Number(m['id']));
      return this.signIn(this.file()?.['member'] ?? m);
    }
    if (id === 'edit') {
      await this.open(Number(m['id']));
      const member = this.file()?.['member'];
      this.file.set(null);
      if (member) this.openEdit(member);
    }
  }

  protected place(m: Row): string {
    return ['street', 'ward', 'district', 'region'].map((k) => m[k]).filter((x) => !!x).join(', ');
  }

  protected balances(fl: Row): [string, number][] {
    return Object.entries((fl['balances'] ?? {}) as Record<string, number>).filter(([, v]) => Number(v) !== 0);
  }

  protected movesFor(s: string): string[] {
    return Object.keys(MOVES).filter((a) => MOVES[a].includes(s));
  }

  protected eventText(e: Row): string {
    const what = e['kind'] === 'status' ? `${this.status(e['from_value']) || '—'} → ${this.status(e['to_value'])}` : e['kind'] === 'office' ? `${this.office(e['from_value'])} → ${this.office(e['to_value'])}` : String(e['kind'] ?? '');
    return `${what}${e['reason'] ? ' · ' + e['reason'] : ''}${e['by_name'] ? ' · ' + e['by_name'] : ''}`;
  }

  protected openNew(): void {
    this.f = { gender: '' };
    this.existing = false;
    this.editId.set(null);
    this.formOpen.set(true);
  }

  protected openEdit(m: Row): void {
    this.f = {};
    for (const k of FIELDS) this.f[k] = m[k] ?? '';
    if (this.f['nida'] === '' && m['nida_masked']) delete this.f['nida'];
    this.editId.set(Number(m['id']));
    this.formOpen.set(true);
  }

  protected async save(): Promise<void> {
    const body: Row = {};
    for (const k of FIELDS) {
      const v = typeof this.f[k] === 'string' ? this.f[k].trim() : this.f[k];
      if (v !== undefined && v !== '' && v !== null) body[k] = v;
      else if (this.editId() && k in this.f && k !== 'full_name' && k !== 'phone') body[k] = null;
    }
    const id = this.editId();
    if (!id && this.existing) {
      body['existing'] = true;
      if (this.f['member_number']?.trim()) body['member_number'] = this.f['member_number'].trim();
      if (this.f['joined_on']) body['joined_on'] = this.f['joined_on'];
    }
    let saved: Row = {};
    const ok = await this.act(async () => {
      saved = id ? await this.api.put(`/members/${id}`, body) : await this.api.post('/members', body);
    }, id ? this.i18n.t('g.saved') : this.existing ? this.i18n.t('g.m.added.existing') : this.i18n.t('g.m.added'));
    if (!ok) return;
    this.formOpen.set(false);
    await this.load(this.page());
    if (id) this.showFile(saved);
  }

  protected async open(id: number): Promise<void> {
    this.password.set(null);
    this.depOpen.set(false);
    try {
      this.showFile(await this.api.get(`/members/${id}`));
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  private showFile(fl: Row): void {
    this.file.set(fl);
    this.officeChoice.set(fl['member']?.['office'] ?? '');
  }

  protected async move(m: Row, action: string): Promise<void> {
    const needsReason = action !== 'approve' && action !== 'reinstate';
    const title = `${this.i18n.t('g.move.' + action)}: ${m['full_name']}`;
    let reason: string | null = null;
    if (needsReason) {
      reason = await this.reason(title, this.i18n.t('g.move.why'), this.i18n.t('g.move.' + action));
      if (reason === null) return;
    } else if (!(await this.sure(title, this.i18n.t('g.move.sure'), this.i18n.t('g.move.' + action)))) {
      return;
    }
    let fl: Row = {};
    if (await this.act(async () => (fl = await this.api.post(`/members/${m['id']}/status`, { action, ...(reason ? { reason } : {}) })), this.i18n.t('g.saved'))) {
      this.showFile(fl);
      await this.load(this.page());
    }
  }

  protected async setOffice(m: Row): Promise<void> {
    const to = this.officeChoice();
    if (!(await this.sure(this.i18n.t('g.office'), `${m['full_name']}: ${this.office(m['office'])} → ${this.office(to)}`, this.i18n.t('g.save')))) return;
    let fl: Row = {};
    if (await this.act(async () => (fl = await this.api.put(`/members/${m['id']}/office`, { office: to || null, replace: true })), this.i18n.t('g.saved'))) {
      this.showFile(fl);
      await this.load(this.page());
    }
  }

  protected async signIn(m: Row): Promise<void> {
    const reset = m['has_sign_in'] === true;
    const msg = reset ? this.i18n.t('g.signin.reset.sure') : this.i18n.t('g.signin.give.sure');
    if (!(await this.sure(reset ? this.i18n.t('g.signin.reset') : this.i18n.t('g.signin.give'), msg, this.i18n.t('g.yes')))) return;
    let r: Row = {};
    if (await this.act(async () => (r = await this.api.post(`/members/${m['id']}/sign-in`, reset ? { reset: true } : {})))) {
      this.password.set(r);
      const fl = this.file();
      if (fl) this.file.set({ ...fl, member: { ...fl['member'], has_sign_in: true } });
    }
  }

  protected addDependant(m: Row): void {
    this.dep = { name: '', relationship: 'child', phone: '' };
    this.depOpen.set(!this.depOpen());
    void m;
  }

  protected async saveDependant(m: Row): Promise<void> {
    const body: Row = { name: String(this.dep['name'] ?? '').trim(), relationship: this.dep['relationship'] };
    if (String(this.dep['phone'] ?? '').trim()) body['phone'] = String(this.dep['phone']).trim();
    let fl: Row = {};
    if (await this.act(async () => (fl = await this.api.post(`/members/${m['id']}/dependants`, body)), this.i18n.t('g.saved'))) {
      this.depOpen.set(false);
      this.showFile(fl);
    }
  }

  protected async removeDependant(m: Row, x: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.dependants'), `${x['name']}`, this.i18n.t('common.delete'), true))) return;
    let fl: Row = {};
    if (await this.act(async () => (fl = await this.api.del(`/members/${m['id']}/dependants/${x['id']}`)), this.i18n.t('g.saved'))) this.showFile(fl);
  }
}
