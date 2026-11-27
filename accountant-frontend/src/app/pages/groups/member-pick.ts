import { Component, EventEmitter, Input, Output, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { GroupsApi, Row } from '../../core/groups/groups-api.service';
import { I18nService } from '../../core/i18n.service';

/** A member chosen in a form: id, name, number. */
export interface PickedMember {
  id: number;
  name: string;
  number: string;
}

/**
 * Find a member by name, phone or number and choose them. Searches as one types (a few letters), shows up to eight, and the choice
 * stays shown with a "change" link. [statuses] limits who may be chosen (active members, by default).
 */
@Component({
  selector: 'app-g-member-pick',
  imports: [FormsModule],
  template: `
    <div class="ph-field" data-testid="g-pick">
      <span>{{ label || i18n.t('g.member') }}</span>
      @if (picked(); as p) {
        <div class="ph-row ph-card" style="padding: 8px 12px">
          <b>{{ p.name }} @if (p.number) { <span class="ph-muted">· {{ p.number }}</span> }</b>
          <button type="button" class="btn-outline ph-btn" style="padding: 4px 10px" (click)="clear()" data-testid="g-pick-change">{{ i18n.t('common.change') }}</button>
        </div>
      } @else {
        <input class="modal-input" [ngModel]="q()" (ngModelChange)="search($event)" [placeholder]="i18n.t('g.pick.ph')" data-testid="g-pick-q" name="gPickQ" autocomplete="off" />
        @if (hits().length) {
          <div class="ph-card" style="padding: 4px 0; margin-top: 4px; max-height: 240px; overflow: auto">
            @for (m of hits(); track m['id']) {
              <button type="button" class="g-hit" (click)="choose(m)" [attr.data-testid]="'g-pick-' + m['id']">
                {{ m['full_name'] }} <span class="ph-muted">{{ m['member_number'] || m['application_ref'] || '' }} · {{ m['phone'] }}</span>
              </button>
            }
          </div>
        } @else if (q().trim().length >= 2 && !searching()) {
          <p class="ph-muted" style="margin-top: 4px">{{ i18n.t('g.pick.none') }}</p>
        }
      }
    </div>
  `,
  styles: [
    `
      .g-hit { display: block; width: 100%; text-align: left; padding: 7px 12px; font-size: 14px; font-weight: 600; cursor: pointer; text-transform: none; letter-spacing: 0; }
      .g-hit:hover { background: rgba(32, 184, 206, 0.15); }
    `,
  ],
})
export class MemberPick {
  private readonly api = inject(GroupsApi);
  protected readonly i18n = inject(I18nService);

  @Input() label = '';
  /** Which member statuses can be chosen ('' = any). */
  @Input() status = 'active';
  @Input() set value(v: PickedMember | null) {
    this.picked.set(v);
  }
  @Output() readonly picked$ = new EventEmitter<PickedMember | null>();

  protected readonly picked = signal<PickedMember | null>(null);
  protected readonly q = signal('');
  protected readonly hits = signal<Row[]>([]);
  protected readonly searching = signal(false);
  private ticket = 0;

  protected async search(text: string): Promise<void> {
    this.q.set(text);
    const ask = ++this.ticket;
    if (text.trim().length < 2) {
      this.hits.set([]);
      return;
    }
    this.searching.set(true);
    try {
      const page = await this.api.page('/members', 'members', { q: text, status: this.status || null });
      if (ask === this.ticket) this.hits.set(page.items.slice(0, 8));
    } catch {
      if (ask === this.ticket) this.hits.set([]);
    } finally {
      if (ask === this.ticket) this.searching.set(false);
    }
  }

  protected choose(m: Row): void {
    const p: PickedMember = { id: Number(m['id']), name: String(m['full_name'] ?? ''), number: String(m['member_number'] ?? m['application_ref'] ?? '') };
    this.picked.set(p);
    this.hits.set([]);
    this.q.set('');
    this.picked$.emit(p);
  }

  protected clear(): void {
    this.picked.set(null);
    this.picked$.emit(null);
  }
}
