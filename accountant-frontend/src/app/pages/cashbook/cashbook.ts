import { HttpClient } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { dayLabel, dayOf, parseAmount, serverMessage, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';

const API = environment.apiUrl;

type Period = 'today' | 'month' | 'last';
const PERIODS: Period[] = ['today', 'month', 'last'];
export const PLACES = ['cash', 'mobile', 'bank'] as const;
export type Place = (typeof PLACES)[number];

const num = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const text = (v: unknown): string => (v === null || v === undefined ? '' : String(v));
const obj = (v: unknown): Record<string, unknown> => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {});

export interface CashDay {
  date: string;
  in: number;
  out: number;
  closing: number;
  counted: number | null;
  difference: number;
}

export interface CashPlace {
  place: Place;
  opening: number;
  in: number;
  out: number;
  closing: number;
  days: CashDay[];
}

export interface CashMove {
  id: number;
  kind: string;
  method: string;
  movedOn: string;
  note: string;
  amount: number;
}

export interface Cashbook {
  places: CashPlace[];
  moves: CashMove[];
}

/** The cashbook as the server sends it (cash, mobile money and bank, day by day, and the owner's own moves). */
export function readCashbook(j: Record<string, unknown>): Cashbook {
  const places = obj(j['places']);

  return {
    places: PLACES.map((p) => {
      const d = obj(places[p]);
      const days = Array.isArray(d['days']) ? (d['days'] as unknown[]) : [];

      return {
        place: p,
        opening: num(d['opening']),
        in: num(d['in']),
        out: num(d['out']),
        closing: num(d['closing']),
        days: days.map((r) => {
          const o = obj(r);
          const c = o['count'] && typeof o['count'] === 'object' ? obj(o['count']) : null;

          return { date: text(o['date']), in: num(o['in']), out: num(o['out']), closing: num(o['closing']), counted: c ? num(c['counted']) : null, difference: c ? num(c['difference']) : 0 };
        }),
      };
    }),
    moves: (Array.isArray(j['moves']) ? (j['moves'] as unknown[]) : []).map((m) => {
      const o = obj(m);

      return { id: num(o['id']), kind: text(o['kind']), method: text(o['method']), movedOn: text(o['moved_on']), note: text(o['note']), amount: num(o['amount']) };
    }),
  };
}

export function cashRange(p: Period, now: Date): [string, string] {
  const t = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  if (p === 'today') return [dayOf(t), dayOf(t)];
  if (p === 'last') return [dayOf(new Date(t.getFullYear(), t.getMonth() - 1, 1)), dayOf(new Date(t.getFullYear(), t.getMonth(), 0))];

  return [dayOf(new Date(t.getFullYear(), t.getMonth(), 1)), dayOf(t)];
}

@Component({
  selector: 'app-cashbook',
  imports: [FormsModule, ModalDialogComponent],
  template: `
    <div class="ad ph-page" data-testid="cashbook-page">
      <div class="ph-chips">
        @for (p of periods; track p) {
          <button type="button" class="pill-tab" [class.is-active]="period() === p" [attr.data-testid]="'cb-period-' + p" (click)="pick(p)">{{ periodName(p) }}</button>
        }
      </div>
      <p class="ph-muted">{{ rangeLabel() }}</p>
      <div class="ph-row" style="gap: 8px">
        <button type="button" class="btn-primary ph-btn" style="flex: 1" (click)="openMove()" data-testid="cb-move">{{ i18n.t('cb.move') }}</button>
        <button type="button" class="btn-outline ph-btn" style="flex: 1" (click)="openCount()" data-testid="cb-count">{{ i18n.t('cb.count') }}</button>
      </div>
      @if (result()) { <section class="ph-card" data-testid="cb-result"><p>{{ result() }}</p></section> }

      @if (error()) {
        <section class="ph-card"><p data-testid="cb-error">{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (!book()) {
        <section class="ph-card"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else {
        @let b = book()!;
        @for (p of b.places; track p.place) {
          <section class="ph-card" [attr.data-testid]="'cb-place-' + p.place">
            <button type="button" class="cb-head" (click)="toggle(p.place)">
              <span><h3>{{ placeName(p.place) }}</h3><span class="ph-muted">{{ i18n.t('cb.should') }}: </span><b [attr.data-testid]="'cb-closing-' + p.place">{{ tsh(p.closing) }}</b></span>
              <span>{{ open().includes(p.place) ? '▴' : '▾' }}</span>
            </button>
            @if (open().includes(p.place)) {
              <div class="ph-line"><span>{{ i18n.t('cb.opening') }}</span><b>{{ tsh(p.opening) }}</b></div>
              <div class="ph-line"><span>{{ i18n.t('cb.in') }}</span><b>{{ tsh(p.in) }}</b></div>
              <div class="ph-line"><span>{{ i18n.t('cb.out') }}</span><b>{{ tsh(p.out) }}</b></div>
              @for (d of p.days; track d.date) {
                <div class="cb-day">
                  <div class="ph-line"><span>{{ d.date }}</span><b>{{ tsh(d.closing) }}</b></div>
                  <p class="ph-muted">{{ i18n.t('cb.in') }} {{ tsh(d.in) }} · {{ i18n.t('cb.out') }} {{ tsh(d.out) }}@if (d.counted !== null) { · {{ i18n.t('cb.counted') }} {{ tsh(d.counted) }} }
                    @if (d.counted !== null && d.difference !== 0) { <b [class.ph-bad]="d.difference < 0" [class.ph-warn]="d.difference > 0"> {{ d.difference < 0 ? '−' : '+' }} {{ tsh(Math.abs(d.difference)) }}</b> }</p>
                </div>
              }
            }
          </section>
        }
        @if (b.moves.length) {
          <section class="ph-card">
            <h3>{{ i18n.t('cb.owner.moves') }}</h3>
            @for (m of b.moves; track m.id) {
              <div class="ph-row" style="padding: 4px 0" [attr.data-testid]="'cb-move-' + m.id">
                <span>{{ kindName(m.kind) }} · {{ placeName(m.method) }}<br /><span class="ph-muted">{{ m.movedOn }}@if (m.note) { · {{ m.note }} }</span></span>
                <span><b>{{ tsh(m.amount) }}</b> <button type="button" class="btn-outline" style="padding: 0 8px" (click)="removeMove(m)" [attr.aria-label]="i18n.t('cb.remove')" [attr.data-testid]="'cb-remove-' + m.id">×</button></span>
              </div>
            }
          </section>
        }
      }
    </div>

    <app-modal-dialog [show]="dialog() === 'move'" [eyebrow]="i18n.t('nav.ph.money')" [title]="i18n.t('cb.move.title')" size="sm" (close)="dialog.set('')">
      <div slot="body" class="ph-page" style="gap: 12px">
        <div class="ph-chips">
          @for (k of kinds; track k) { <button type="button" class="pill-tab" [class.is-active]="mKind() === k" (click)="mKind.set(k)" [attr.data-testid]="'cb-kind-' + k">{{ kindName(k) }}</button> }
        </div>
        <div class="ph-chips">
          @for (p of places; track p) { <button type="button" class="pill-tab" [class.is-active]="mPlace() === p" (click)="mPlace.set(p)" [attr.data-testid]="'cb-place-pick-' + p">{{ placeName(p) }}</button> }
        </div>
        <label class="ph-field">{{ i18n.t('cb.amount') }}<input class="modal-input" inputmode="numeric" [ngModel]="mAmount()" (ngModelChange)="mAmount.set($event)" data-testid="cb-amount" name="cbAmount" /></label>
        <label class="ph-field">{{ i18n.t('cb.note') }}<input class="modal-input" [ngModel]="mNote()" (ngModelChange)="mNote.set($event)" name="cbNote" /></label>
        @if (problem()) { <p class="ph-bad" data-testid="cb-problem">{{ problem() }}</p> }
      </div>
      <div slot="footer" class="flex gap-2 justify-end">
        <button type="button" class="modal-cancel-btn" (click)="dialog.set('')">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary" [disabled]="busy()" (click)="saveMove()" data-testid="cb-move-save">{{ i18n.t('common.save') }}</button>
      </div>
    </app-modal-dialog>

    <app-modal-dialog [show]="dialog() === 'count'" [eyebrow]="i18n.t('nav.ph.money')" [title]="i18n.t('cb.count.title')" size="sm" (close)="dialog.set('')">
      <div slot="body" class="ph-page" style="gap: 12px">
        <div class="ph-chips">
          @for (p of places; track p) { <button type="button" class="pill-tab" [class.is-active]="mPlace() === p" (click)="mPlace.set(p)">{{ placeName(p) }}</button> }
        </div>
        <label class="ph-field">{{ i18n.t('cb.counted.amount') }}<input class="modal-input" inputmode="numeric" [ngModel]="mAmount()" (ngModelChange)="mAmount.set($event)" data-testid="cb-counted" name="cbCounted" /></label>
        <label class="ph-field">{{ i18n.t('cb.note') }}<input class="modal-input" [ngModel]="mNote()" (ngModelChange)="mNote.set($event)" name="cbNote2" /></label>
        @if (problem()) { <p class="ph-bad" data-testid="cb-problem">{{ problem() }}</p> }
      </div>
      <div slot="footer" class="flex gap-2 justify-end">
        <button type="button" class="modal-cancel-btn" (click)="dialog.set('')">{{ i18n.t('common.cancel') }}</button>
        <button type="button" class="btn-primary" [disabled]="busy()" (click)="saveCount()" data-testid="cb-count-save">{{ i18n.t('cb.compare') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [
    `
      .cb-head { display: flex; justify-content: space-between; align-items: center; width: 100%; text-align: left; background: none; border: 0; color: inherit; cursor: pointer; padding: 0; }
      .cb-day { border-top: 1px solid rgba(255, 255, 255, 0.12); padding: 4px 0; }
    `,
  ],
})
export class CashbookPage implements OnInit {
  private readonly http = inject(HttpClient);
  protected readonly i18n = inject(I18nService);
  protected readonly tsh = tsh;
  protected readonly Math = Math;
  protected readonly periods = PERIODS;
  protected readonly places = PLACES;
  protected readonly kinds = ['owner_deposit', 'owner_withdrawal', 'opening'];

  protected readonly period = signal<Period>('month');
  protected readonly book = signal<Cashbook | null>(null);
  protected readonly error = signal('');
  protected readonly open = signal<string[]>([]);
  protected readonly result = signal('');
  private asked = 0;

  protected readonly dialog = signal<'' | 'move' | 'count'>('');
  protected readonly mKind = signal('owner_deposit');
  protected readonly mPlace = signal<string>('cash');
  protected readonly mAmount = signal('');
  protected readonly mNote = signal('');
  protected readonly problem = signal('');
  protected readonly busy = signal(false);

  protected readonly range = computed(() => cashRange(this.period(), new Date()));
  protected readonly rangeLabel = computed(() => {
    const [a, b] = this.range();

    return a === b ? dayLabel(a) : `${dayLabel(a)} – ${dayLabel(b)}`;
  });

  ngOnInit(): void {
    void this.load();
  }

  protected periodName(p: Period): string {
    return p === 'today' ? this.i18n.t('pl.p.today') : p === 'last' ? this.i18n.t('pl.p.lastMonth') : this.i18n.t('pl.p.thisMonth');
  }

  protected placeName(p: string): string {
    return p === 'cash' ? this.i18n.t('cb.p.cash') : p === 'mobile' ? this.i18n.t('cb.p.mobile') : this.i18n.t('cb.p.bank');
  }

  protected kindName(k: string): string {
    return k === 'opening' ? this.i18n.t('cb.k.opening') : k === 'owner_deposit' ? this.i18n.t('cb.k.deposit') : this.i18n.t('cb.k.withdrawal');
  }

  protected toggle(p: string): void {
    this.open.update((l) => (l.includes(p) ? l.filter((x) => x !== p) : [...l, p]));
  }

  protected pick(p: Period): void {
    this.period.set(p);
    void this.load();
  }

  async load(): Promise<void> {
    const [from, to] = this.range();
    const ticket = ++this.asked;
    this.error.set('');
    try {
      const r = await firstValueFrom(this.http.get<{ data: Record<string, unknown> }>(`${API}/inventory/salon/cashbook`, { params: { from, to } }));
      if (ticket !== this.asked) return;
      this.book.set(readCashbook(r.data ?? {}));
    } catch {
      if (ticket !== this.asked) return;
      this.book.set(null);
      this.error.set(this.i18n.t('pl.error'));
    }
  }

  protected openMove(): void {
    this.mKind.set('owner_deposit');
    this.mPlace.set('cash');
    this.mAmount.set('');
    this.mNote.set('');
    this.problem.set('');
    this.dialog.set('move');
  }

  protected openCount(): void {
    this.mPlace.set('cash');
    this.mAmount.set('');
    this.mNote.set('');
    this.problem.set('');
    this.dialog.set('count');
  }

  protected async saveMove(): Promise<void> {
    const amount = parseAmount(this.mAmount());
    if (!(amount > 0)) {
      this.problem.set(this.i18n.t('cb.err.amount'));
      return;
    }
    this.busy.set(true);
    try {
      await firstValueFrom(this.http.post(`${API}/inventory/salon/cashbook/moves`, { kind: this.mKind(), method: this.mPlace(), amount, ...(this.mNote().trim() ? { note: this.mNote().trim() } : {}) }));
      this.dialog.set('');
      await this.load();
    } catch (e) {
      this.problem.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
    this.busy.set(false);
  }

  protected async saveCount(): Promise<void> {
    const counted = parseAmount(this.mAmount());
    if (!(counted >= 0)) {
      this.problem.set(this.i18n.t('cb.err.counted'));
      return;
    }
    this.busy.set(true);
    try {
      const r = await firstValueFrom(
        this.http.post<{ data?: Record<string, unknown> }>(`${API}/inventory/salon/cashbook/counts`, { method: this.mPlace(), counted, ...(this.mNote().trim() ? { note: this.mNote().trim() } : {}) }),
      );
      const d = obj(r.data);
      const diff = num(d['difference']);
      const expected = num(d['expected']);
      this.result.set(
        diff === 0
          ? this.i18n.t('cb.match')
          : this.i18n.t('cb.diff', tsh(expected), tsh(expected + diff), `${diff < 0 ? '−' : '+'} ${tsh(Math.abs(diff))}`),
      );
      this.dialog.set('');
      await this.load();
    } catch (e) {
      this.problem.set(serverMessage(e) || this.i18n.t('pl.error'));
    }
    this.busy.set(false);
  }

  protected async removeMove(m: CashMove): Promise<void> {
    try {
      await firstValueFrom(this.http.delete(`${API}/inventory/salon/cashbook/moves/${m.id}`));
      await this.load();
    } catch {
      this.error.set(this.i18n.t('pl.error'));
    }
  }
}
