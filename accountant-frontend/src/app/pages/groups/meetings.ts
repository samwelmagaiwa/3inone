import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { GBase } from './g-base';
import { MemberPick, PickedMember } from './member-pick';

type Tab = 'meetings' | 'notices' | 'texts' | 'actions';
const NOTICE_KINDS = ['general', 'meeting', 'event', 'bereavement', 'contribution', 'loan', 'asset', 'emergency'];
const TEXT_AUDIENCES = ['all', 'leaders', 'overdue', 'selected'];

/**
 * Meetings, notices and texts: call a meeting (members may be texted), cancel it with a reason, record who came and the minutes, write
 * the resolutions and the actions (who does what by when), the chair approves the minutes; post notices; text members (the number of
 * people and SMS parts is shown before anything is sent); follow the open actions.
 */
@Component({
  selector: 'app-g-meetings',
  imports: [FormsModule, ModalDialogComponent, MemberPick],
  template: `
    <div class="ad ph-page" data-testid="g-meetings">
      <div class="ph-row" style="flex-wrap: wrap">
        <div class="ph-chips">
          <button type="button" class="pill-tab" [class.is-active]="tab() === 'meetings'" (click)="go('meetings')">{{ i18n.t('g.mt.meetings') }}</button>
          <button type="button" class="pill-tab" [class.is-active]="tab() === 'actions'" (click)="go('actions')" data-testid="g-mt-tab-actions">{{ i18n.t('g.mt.actions') }}</button>
          <button type="button" class="pill-tab" [class.is-active]="tab() === 'notices'" (click)="go('notices')" data-testid="g-mt-tab-notices">{{ i18n.t('g.mt.notices') }}</button>
          @if (can('send_texts')) { <button type="button" class="pill-tab" [class.is-active]="tab() === 'texts'" (click)="go('texts')" data-testid="g-mt-tab-texts">{{ i18n.t('g.mt.texts') }}</button> }
        </div>
        <div class="ph-row" style="gap: 6px">
          @if (tab() === 'meetings' && can('call_meetings')) { <button type="button" class="btn-primary ph-btn" (click)="openCall()" data-testid="g-mt-call">{{ i18n.t('g.mt.call') }}</button> }
          @if (tab() === 'notices' && can('post_announcements')) { <button type="button" class="btn-primary ph-btn" (click)="openNotice()" data-testid="g-mt-notice-new">{{ i18n.t('g.mt.notice.new') }}</button> }
          @if (tab() === 'texts' && can('send_texts')) { <button type="button" class="btn-primary ph-btn" (click)="openText()" data-testid="g-mt-text-new">{{ i18n.t('g.mt.text.new') }}</button> }
        </div>
      </div>
      @if (error()) { <section class="ph-card"><p>{{ error() }}</p></section> }

      @switch (tab()) {
        @case ('meetings') {
          <div class="ph-card ph-joined" data-testid="g-mt-list">
            @for (m of meetings(); track m['id']) {
              <section class="ph-sec">
                <div class="ph-row"><h3>{{ m['title'] }}</h3><span class="ph-badge" [class]="tone(m['status'] === 'held' ? 'done' : m['status'])">{{ status(m['status']) }}</span></div>
                <div class="ph-line"><span>{{ when(m['starts_at']) }}@if (m['venue']) { · {{ m['venue'] }} }</span><span class="ph-muted">{{ m['called_by_name'] }}</span></div>
                @if (m['agenda']) { <p class="ph-muted" style="white-space: pre-line">{{ m['agenda'] }}</p> }
                @if (m['status'] === 'held') {
                  <div class="ph-line"><span>{{ i18n.t('g.mt.present', n(m['present_count'])) }}</span>
                    <span class="ph-badge" [class]="m['minutes_status'] === 'approved' ? 'ph-good' : 'ph-warn'">{{ i18n.t('g.mt.minutes.' + (m['minutes_status'] || 'draft')) }}</span></div>
                }
                @if (m['cancel_reason']) { <p class="ph-bad" style="font-size: 13px">{{ m['cancel_reason'] }}</p> }
                <div class="g-acts">
                  <button type="button" class="btn-outline ph-btn" (click)="openMeeting(m)" [attr.data-testid]="'g-mt-open-' + m['id']">{{ i18n.t('g.open') }}</button>
                  @if (m['status'] === 'scheduled' && can('record_meetings')) { <button type="button" class="btn-primary is-success ph-btn" (click)="openRecord(m)" [attr.data-testid]="'g-mt-record-' + m['id']">{{ i18n.t('g.mt.record') }}</button> }
                  @if (m['status'] === 'scheduled' && can('call_meetings')) { <button type="button" class="btn-primary is-danger ph-btn" (click)="cancel(m)">{{ i18n.t('g.mt.cancel') }}</button> }
                </div>
              </section>
            } @empty { <section class="ph-sec"><p class="ph-muted">{{ i18n.t('g.mt.none') }}</p></section> }
          </div>
        }
        @case ('actions') {
          <div class="ph-card ph-joined" data-testid="g-mt-actions">
            @for (a of actions(); track a['id']) {
              <section class="ph-sec">
                <div class="ph-row"><h3>{{ a['text'] }}</h3><span class="ph-badge" [class]="a['overdue'] ? 'ph-bad' : 'ph-warn'">{{ a['overdue'] ? status('overdue') : status('open') }}</span></div>
                <div class="ph-line"><span class="ph-muted">{{ a['meeting_title'] }} · {{ a['assignee_name'] || '—' }}</span><span>{{ a['due_date'] ? day(a['due_date']) : '' }}</span></div>
                <div class="g-acts"><button type="button" class="btn-primary is-success ph-btn" (click)="markDone(a)">{{ i18n.t('g.mt.done') }}</button></div>
              </section>
            } @empty { <section class="ph-sec"><p class="ph-muted">{{ i18n.t('g.mt.actions.none') }}</p></section> }
          </div>
        }
        @case ('notices') {
          <div class="ph-card ph-joined" data-testid="g-mt-notices">
            @for (n of notices(); track n['id']) {
              <section class="ph-sec">
                <div class="ph-row"><h3>{{ n['title'] }}</h3><span class="ph-badge ph-accent">{{ i18n.t('g.nk.' + (n['category'] || 'general')) }}</span></div>
                <p style="white-space: pre-line">{{ n['body'] }}</p>
                <div class="ph-line"><span class="ph-muted">{{ n['author_name'] }} · {{ when(n['created_at']) }} · {{ i18n.t('g.aud.' + (n['audience'] === 'officers' ? 'leaders' : n['audience'] || 'all')) }}</span>
                  @if (n['expires_on']) { <span class="ph-muted">{{ i18n.t('g.mt.until', day(n['expires_on'])) }}</span> }</div>
                @if (can('post_announcements')) { <div class="g-acts"><button type="button" class="link-btn danger" (click)="removeNotice(n)">{{ i18n.t('g.remove') }}</button></div> }
              </section>
            } @empty { <section class="ph-sec"><p class="ph-muted">{{ i18n.t('g.mt.notices.none') }}</p></section> }
          </div>
        }
        @case ('texts') {
          <div class="ph-card ph-joined" data-testid="g-mt-texts">
            @for (t of texts(); track t['id']) {
              <section class="ph-sec">
                <div class="ph-row"><span>{{ t['body'] }}</span><span class="ph-badge" [class]="tone(t['status'])">{{ status(t['status']) }}</span></div>
                <div class="ph-line"><span class="ph-muted">{{ t['sent_by_name'] }} · {{ when(t['created_at']) }} · {{ i18n.t('g.aud.' + (t['audience'] === 'officers' ? 'leaders' : t['audience'])) }}</span>
                  <span class="ph-muted">{{ i18n.t('g.mt.sent.count', n(t['sent']), n(t['recipients'])) }}</span></div>
              </section>
            } @empty { <section class="ph-sec"><p class="ph-muted">{{ i18n.t('g.mt.texts.none') }}</p></section> }
          </div>
        }
      }
    </div>

    <!-- call a meeting -->
    <app-modal-dialog [show]="callOpen()" [eyebrow]="i18n.t('g.mt.meetings')" [title]="i18n.t('g.mt.call')" size="md" (close)="callOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.pr.title') }} *<input class="modal-input" [(ngModel)]="cf['title']" name="ct" data-testid="g-mtc-title" /></label>
        <label class="ph-field">{{ i18n.t('g.mt.when') }} *<input class="modal-input" type="datetime-local" [(ngModel)]="cf['starts_at']" name="cs" data-testid="g-mtc-when" /></label>
        <label class="ph-field">{{ i18n.t('g.mt.venue') }}<input class="modal-input" [(ngModel)]="cf['venue']" name="cv" /></label>
        <label class="ph-field">{{ i18n.t('g.mt.agenda') }}<textarea class="modal-input" rows="4" [(ngModel)]="cf['agenda']" name="ca"></textarea></label>
        <label class="ph-row"><span>{{ i18n.t('g.mt.notify') }}</span><input type="checkbox" [(ngModel)]="cf['notify']" name="cn" /></label>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="callOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary ph-btn" [disabled]="busy()" (click)="call()" data-testid="g-mtc-save">{{ i18n.t('g.mt.call') }}</button>
      </div>
    </app-modal-dialog>

    <!-- who came, and the minutes -->
    <app-modal-dialog [show]="!!recording()" [eyebrow]="recording()?.['title'] ?? ''" [title]="i18n.t('g.mt.record')" size="lg" (close)="recording.set(null)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <div class="ph-row"><b>{{ i18n.t('g.mt.present', present.size) }}</b>
          <span><button type="button" class="link-btn" (click)="allPresent(true)">{{ i18n.t('g.mt.all.here') }}</button> · <button type="button" class="link-btn" (click)="allPresent(false)">{{ i18n.t('g.mt.none.here') }}</button></span></div>
        <div class="g-people">
          @for (m of activeMembers(); track m['id']) {
            <label class="g-person"><input type="checkbox" [checked]="present.has(m['id'])" (change)="toggle(m['id'])" /> {{ m['full_name'] }}</label>
          }
        </div>
        <label class="ph-field">{{ i18n.t('g.mt.minutes') }}<textarea class="modal-input" rows="6" [(ngModel)]="minutes" name="min"></textarea></label>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="recording.set(null)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-success ph-btn" [disabled]="busy()" (click)="saveRecord()" data-testid="g-mtr-save">{{ i18n.t('g.save') }}</button>
      </div>
    </app-modal-dialog>

    <!-- one meeting: minutes, resolutions, actions -->
    <app-modal-dialog [show]="!!meeting()" [eyebrow]="when(meeting()?.['starts_at'])" [title]="meeting()?.['title'] ?? ''" size="xl" (close)="meeting.set(null)">
      <div slot="body">
        @if (meeting(); as m) {
          <div class="ph-card ph-joined ph-cols">
            <section class="ph-sec">
              <h3>{{ i18n.t('g.mt.minutes') }}</h3>
              <p style="white-space: pre-line">{{ m['minutes'] || i18n.t('g.none') }}</p>
              @if (m['minutes_approved_by_name']) { <p class="ph-good" style="font-size: 13px">{{ i18n.t('g.mt.approved.by', m['minutes_approved_by_name']) }}</p> }
              <div class="g-acts">
                @if (m['status'] === 'held' && m['minutes_status'] !== 'approved' && can('approve_minutes')) {
                  <button type="button" class="btn-primary is-success ph-btn" (click)="approveMinutes(m)" data-testid="g-mt-approve">{{ i18n.t('g.mt.approve') }}</button>
                }
                @if (m['minutes_status'] === 'approved' && can('approve_minutes')) {
                  <button type="button" class="btn-outline ph-btn" (click)="reopen(m)">{{ i18n.t('g.mt.reopen') }}</button>
                }
              </div>
            </section>
            <section class="ph-sec">
              <h3>{{ i18n.t('g.mt.items') }}</h3>
              @for (it of m['items'] ?? []; track it['id']) {
                <div class="ph-line">
                  <span><span class="ph-badge" [class]="it['kind'] === 'resolution' ? 'ph-accent' : 'ph-warn'">{{ i18n.t('g.mt.kind.' + it['kind']) }}</span> {{ it['text'] }}
                    @if (it['assignee_name']) { <span class="ph-muted"> · {{ it['assignee_name'] }}</span> } @if (it['due_date']) { <span class="ph-muted"> · {{ day(it['due_date']) }}</span> }</span>
                  <span>
                    @if (it['kind'] === 'action' && it['status'] !== 'done' && m['minutes_status'] === 'approved') { <button type="button" class="link-btn" (click)="markDone(it, m)">{{ i18n.t('g.mt.done') }}</button> }
                    @if (it['status'] === 'done') { <b class="ph-good">{{ status('done') }}</b> }
                    @if (m['minutes_status'] !== 'approved' && can('record_meetings')) { <button type="button" class="link-btn danger" (click)="removeItem(m, it)">{{ i18n.t('g.remove') }}</button> }
                  </span>
                </div>
              } @empty { <p class="ph-muted">{{ i18n.t('g.none') }}</p> }
              @if (m['status'] === 'held' && m['minutes_status'] !== 'approved' && can('record_meetings')) {
                <div class="ph-card" style="margin-top: 8px">
                  <div class="ph-row" style="gap: 6px; flex-wrap: wrap">
                    <select class="modal-input" style="flex: 1" [(ngModel)]="it['kind']" name="ik"><option value="resolution">{{ i18n.t('g.mt.kind.resolution') }}</option><option value="action">{{ i18n.t('g.mt.kind.action') }}</option></select>
                    @if (it['kind'] === 'action') { <input class="modal-input" style="flex: 1" type="date" [(ngModel)]="it['due_date']" name="idd" /> }
                  </div>
                  <input class="modal-input" style="margin-top: 6px; width: 100%" [(ngModel)]="it['text']" name="it" [placeholder]="i18n.t('g.mt.item.ph')" />
                  @if (it['kind'] === 'action') { <app-g-member-pick [label]="i18n.t('g.mt.who')" [value]="assignee()" (picked$)="assignee.set($event)" /> }
                  <button type="button" class="btn-primary ph-btn" style="margin-top: 6px" (click)="addItem(m)">{{ i18n.t('g.add') }}</button>
                </div>
              }
            </section>
          </div>
        }
      </div>
      <div slot="footer" class="flex gap-2"><button type="button" class="btn-outline ph-btn" (click)="meeting.set(null)">{{ i18n.t('common.close') }}</button></div>
    </app-modal-dialog>

    <!-- a notice -->
    <app-modal-dialog [show]="noticeOpen()" [eyebrow]="i18n.t('g.mt.notices')" [title]="i18n.t('g.mt.notice.new')" size="md" (close)="noticeOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.pr.title') }} *<input class="modal-input" [(ngModel)]="nf['title']" name="nt" data-testid="g-mtn-title" /></label>
        <label class="ph-field">{{ i18n.t('g.mt.message') }} *<textarea class="modal-input" rows="5" [(ngModel)]="nf['body']" name="nb" data-testid="g-mtn-body"></textarea></label>
        <div class="ph-row" style="gap: 10px">
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.kind') }}<select class="modal-input" [(ngModel)]="nf['category']" name="nc">@for (k of noticeKinds; track k) { <option [value]="k">{{ i18n.t('g.nk.' + k) }}</option> }</select></label>
          <label class="ph-field" style="flex: 1">{{ i18n.t('g.mt.for') }}<select class="modal-input" [(ngModel)]="nf['audience']" name="na"><option value="all">{{ i18n.t('g.aud.all') }}</option><option value="leaders">{{ i18n.t('g.aud.leaders') }}</option></select></label>
        </div>
        <label class="ph-field">{{ i18n.t('g.mt.expires') }}<input class="modal-input" type="date" [min]="today()" [(ngModel)]="nf['expires_on']" name="ne" /></label>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="noticeOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary ph-btn" [disabled]="busy()" (click)="postNotice()" data-testid="g-mtn-save">{{ i18n.t('g.mt.post') }}</button>
      </div>
    </app-modal-dialog>

    <!-- a text to members -->
    <app-modal-dialog [show]="textOpen()" [eyebrow]="i18n.t('g.mt.texts')" [title]="i18n.t('g.mt.text.new')" size="md" (close)="textOpen.set(false)">
      <div slot="body" class="ph-page" style="gap: 10px">
        <label class="ph-field">{{ i18n.t('g.mt.to') }}<select class="modal-input" [(ngModel)]="tAudience" name="ta">@for (a of audiences; track a) { <option [value]="a">{{ i18n.t('g.aud.' + a) }}</option> }</select></label>
        @if (tAudience === 'selected') {
          @for (p of tPeople(); track p.id) { <div class="ph-row ph-card" style="padding: 6px 12px"><span>{{ p.name }}</span><button type="button" class="link-btn danger" (click)="dropPerson(p.id)">{{ i18n.t('g.remove') }}</button></div> }
          <app-g-member-pick [label]="i18n.t('g.mt.add.person')" [value]="null" (picked$)="addPerson($event)" />
        }
        <label class="ph-field">{{ i18n.t('g.mt.message') }} ({{ tBody.length }}/640)<textarea class="modal-input" rows="4" maxlength="640" [(ngModel)]="tBody" name="tb" data-testid="g-mtt-body"></textarea></label>
        <p class="ph-muted">{{ i18n.t('g.mt.text.hint') }}</p>
      </div>
      <div slot="footer" class="flex gap-2">
        <button type="button" class="btn-outline ph-btn" (click)="textOpen.set(false)">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary is-warn ph-btn" [disabled]="busy()" (click)="sendText()" data-testid="g-mtt-send">{{ i18n.t('g.mt.send') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [
    `
      .g-acts { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
      .g-acts:empty { display: none; }
      .g-people { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 4px 12px; max-height: 320px; overflow: auto; }
      .g-person { display: flex; gap: 8px; align-items: center; font-size: 14px; cursor: pointer; }
    `,
  ],
})
export class GMeetingsPage extends GBase implements OnInit {
  protected readonly noticeKinds = NOTICE_KINDS;
  protected readonly audiences = TEXT_AUDIENCES;
  protected readonly tab = signal<Tab>('meetings');
  protected readonly error = signal('');
  protected readonly meetings = signal<Row[]>([]);
  protected readonly actions = signal<Row[]>([]);
  protected readonly notices = signal<Row[]>([]);
  protected readonly texts = signal<Row[]>([]);

  protected readonly callOpen = signal(false);
  protected cf: Row = {};
  protected readonly recording = signal<Row | null>(null);
  protected readonly activeMembers = signal<Row[]>([]);
  protected present = new Set<number>();
  protected minutes = '';
  protected readonly meeting = signal<Row | null>(null);
  protected it: Row = { kind: 'resolution', text: '', due_date: '' };
  protected readonly assignee = signal<PickedMember | null>(null);
  protected readonly noticeOpen = signal(false);
  protected nf: Row = {};
  protected readonly textOpen = signal(false);
  protected tAudience = 'all';
  protected tBody = '';
  protected readonly tPeople = signal<PickedMember[]>([]);

  ngOnInit(): void {
    void this.loadMeetings();
  }

  protected go(t: Tab): void {
    this.tab.set(t);
    this.error.set('');
    switch (t) {
      case 'meetings': void this.loadMeetings(); break;
      case 'actions': void this.loadActions(); break;
      case 'notices': void this.loadNotices(); break;
      case 'texts': void this.loadTexts(); break;
    }
  }

  private async list(path: string, key: string, into: (rows: Row[]) => void, query?: Record<string, string>): Promise<void> {
    try {
      into(((await this.api.get(path, query))[key] as Row[]) ?? []);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  loadMeetings(): Promise<void> {
    return this.list('/meetings', 'meetings', (r) => this.meetings.set(r));
  }

  loadActions(): Promise<void> {
    return this.list('/meeting-actions', 'actions', (r) => this.actions.set(r), this.can('record_meetings') ? { scope: 'all' } : undefined);
  }

  loadNotices(): Promise<void> {
    return this.list('/announcements', 'announcements', (r) => this.notices.set(r));
  }

  loadTexts(): Promise<void> {
    return this.list('/messages', 'messages', (r) => this.texts.set(r));
  }

  protected openCall(): void {
    this.cf = { title: '', starts_at: '', venue: '', agenda: '', notify: true };
    this.callOpen.set(true);
  }

  protected async call(): Promise<void> {
    if (String(this.cf['title'] ?? '').trim().length < 3) return this.stop(this.i18n.t('g.need.name'));
    if (!this.cf['starts_at']) return this.stop(this.i18n.t('g.need.when'));
    const body: Row = { title: String(this.cf['title']).trim(), starts_at: String(this.cf['starts_at']).replace('T', ' '), notify: !!this.cf['notify'] };
    if (String(this.cf['venue'] ?? '').trim()) body['venue'] = String(this.cf['venue']).trim();
    if (String(this.cf['agenda'] ?? '').trim()) body['agenda'] = String(this.cf['agenda']).trim();
    if (await this.act(() => this.api.post('/meetings', body), this.i18n.t('g.mt.called'))) {
      this.callOpen.set(false);
      await this.loadMeetings();
    }
  }

  protected async cancel(m: Row): Promise<void> {
    const why = await this.reason(this.i18n.t('g.mt.cancel'), m['title'], this.i18n.t('g.mt.cancel'));
    if (why === null) return;
    if (await this.act(() => this.api.post(`/meetings/${m['id']}/cancel`, { reason: why }), this.i18n.t('g.saved'))) await this.loadMeetings();
  }

  protected async openRecord(m: Row): Promise<void> {
    this.present = new Set<number>(((m['present_ids'] as number[]) ?? []).map(Number));
    this.minutes = m['minutes'] ?? '';
    this.recording.set(m);
    if (!this.activeMembers().length) {
      const all: Row[] = [];
      for (let page = 1; page <= 40; page++) {
        try {
          const p = await this.api.page('/members', 'members', { status: 'active', page });
          all.push(...p.items);
          if (!p.hasMore) break;
        } catch {
          break;
        }
      }
      this.activeMembers.set(all);
    }
  }

  protected toggle(id: number): void {
    const s = new Set(this.present);
    if (s.has(id)) s.delete(id);
    else s.add(id);
    this.present = s;
  }

  protected allPresent(on: boolean): void {
    this.present = on ? new Set(this.activeMembers().map((m) => Number(m['id']))) : new Set();
  }

  protected async saveRecord(): Promise<void> {
    const m = this.recording();
    if (!m) return;
    if (await this.act(() => this.api.post(`/meetings/${m['id']}/record`, { present_ids: [...this.present], minutes: this.minutes.trim() || null }), this.i18n.t('g.saved'))) {
      this.recording.set(null);
      await this.loadMeetings();
    }
  }

  protected openMeeting(m: Row): void {
    this.it = { kind: 'resolution', text: '', due_date: '' };
    this.assignee.set(null);
    this.meeting.set(m);
  }

  private async refreshMeeting(id: number): Promise<void> {
    await this.loadMeetings();
    this.meeting.set(this.meetings().find((x) => Number(x['id']) === id) ?? null);
  }

  protected async addItem(m: Row): Promise<void> {
    if (String(this.it['text'] ?? '').trim().length < 3) return this.stop(this.i18n.t('g.need.text'));
    const body: Row = { kind: this.it['kind'], text: String(this.it['text']).trim() };
    if (this.it['kind'] === 'action') {
      if (this.assignee()) body['assignee_id'] = this.assignee()!.id;
      if (this.it['due_date']) body['due_date'] = this.it['due_date'];
    }
    if (await this.act(() => this.api.post(`/meetings/${m['id']}/items`, body), this.i18n.t('g.saved'))) {
      this.it = { kind: this.it['kind'], text: '', due_date: '' };
      this.assignee.set(null);
      await this.refreshMeeting(Number(m['id']));
    }
  }

  protected async removeItem(m: Row, item: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.remove'), item['text'], this.i18n.t('g.remove'), true))) return;
    if (await this.act(() => this.api.del(`/meetings/${m['id']}/items/${item['id']}`), this.i18n.t('g.saved'))) await this.refreshMeeting(Number(m['id']));
  }

  protected async markDone(a: Row, m?: Row): Promise<void> {
    const meetingId = m ? m['id'] : a['meeting_id'];
    if (!(await this.sure(this.i18n.t('g.mt.done'), a['text'], this.i18n.t('g.mt.done')))) return;
    if (await this.act(() => this.api.post(`/meetings/${meetingId}/items/${a['id']}/done`), this.i18n.t('g.saved'))) {
      if (m) await this.refreshMeeting(Number(m['id']));
      else await this.loadActions();
    }
  }

  protected async approveMinutes(m: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.mt.approve'), this.i18n.t('g.mt.approve.sure'), this.i18n.t('g.mt.approve')))) return;
    if (await this.act(() => this.api.post(`/meetings/${m['id']}/approve-minutes`), this.i18n.t('g.saved'))) {
      await this.refreshMeeting(Number(m['id']));
      await this.ctx.reload();
    }
  }

  protected async reopen(m: Row): Promise<void> {
    const why = await this.reason(this.i18n.t('g.mt.reopen'), m['title'], this.i18n.t('g.mt.reopen'));
    if (why === null) return;
    if (await this.act(() => this.api.post(`/meetings/${m['id']}/reopen-minutes`, { reason: why }), this.i18n.t('g.saved'))) await this.refreshMeeting(Number(m['id']));
  }

  protected openNotice(): void {
    this.nf = { title: '', body: '', category: 'general', audience: 'all', expires_on: '' };
    this.noticeOpen.set(true);
  }

  protected async postNotice(): Promise<void> {
    if (String(this.nf['title'] ?? '').trim().length < 3 || String(this.nf['body'] ?? '').trim().length < 3) return this.stop(this.i18n.t('g.need.text'));
    const body: Row = { title: String(this.nf['title']).trim(), body: String(this.nf['body']).trim(), category: this.nf['category'], audience: this.nf['audience'], ...(this.nf['expires_on'] ? { expires_on: this.nf['expires_on'] } : {}) };
    if (await this.act(() => this.api.post('/announcements', body), this.i18n.t('g.mt.posted'))) {
      this.noticeOpen.set(false);
      await this.loadNotices();
    }
  }

  protected async removeNotice(n: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.remove'), n['title'], this.i18n.t('g.remove'), true))) return;
    if (await this.act(() => this.api.post(`/announcements/${n['id']}/remove`), this.i18n.t('g.saved'))) await this.loadNotices();
  }

  protected openText(): void {
    this.tAudience = 'all';
    this.tBody = '';
    this.tPeople.set([]);
    this.textOpen.set(true);
  }

  protected addPerson(m: PickedMember | null): void {
    if (m && !this.tPeople().some((p) => p.id === m.id)) this.tPeople.set([...this.tPeople(), m]);
  }

  protected dropPerson(id: number): void {
    this.tPeople.set(this.tPeople().filter((p) => p.id !== id));
  }

  /** Shows how many people and SMS parts the text takes, asks, then sends. */
  protected async sendText(): Promise<void> {
    if (this.tBody.trim().length < 2) return this.stop(this.i18n.t('g.need.text'));
    if (this.tAudience === 'selected' && !this.tPeople().length) return this.stop(this.i18n.t('g.need.member'));
    const body: Row = { audience: this.tAudience, body: this.tBody.trim(), ...(this.tAudience === 'selected' ? { member_ids: this.tPeople().map((p) => p.id) } : {}) };
    let est: Row = {};
    if (!(await this.act(async () => (est = await this.api.post('/messages/estimate', body))))) return;
    const msg = this.i18n.t('g.mt.estimate', this.n(est['recipients']), this.n(est['parts_each'], 1), this.n(est['parts_total']));
    if (!(await this.sure(this.i18n.t('g.mt.send'), msg, this.i18n.t('g.mt.send')))) return;
    if (await this.act(() => this.api.post('/messages', body), this.i18n.t('g.mt.sending'))) {
      this.textOpen.set(false);
      await this.loadTexts();
    }
  }
}
