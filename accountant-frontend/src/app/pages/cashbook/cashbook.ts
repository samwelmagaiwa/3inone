import { HttpClient } from '@angular/common/http';
import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { dayLabel, dayOf, parseAmount, serverMessage, tsh } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';

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
  imports: [FormsModule, ModalDialogComponent, RowMenuComponent],
  template: `
    <div class="ad ph-page" data-testid="cashbook-page">
      <!-- the period, the two actions and what each place should hold stay pinned while the tables scroll -->
      <div class="g-pin">
        <div class="g-toolbar">
          <div class="ph-chips g-seg">
            @for (p of periods; track p) {
              <button type="button" class="pill-tab" [class.is-active]="period() === p" [attr.data-testid]="'cb-period-' + p" (click)="pick(p)">{{ periodName(p) }}</button>
            }
          </div>
          <span class="ph-muted">{{ rangeLabel() }}</span>
          <span class="g-grow"></span>
          <button type="button" class="btn-outline ph-btn" (click)="openCount()" data-testid="cb-count">{{ i18n.t('cb.count') }}</button>
          <button type="button" class="btn-primary ph-btn" (click)="openMove()" data-testid="cb-move">{{ i18n.t('cb.move') }}</button>
        </div>
        @if (book(); as b) {
          <div class="ph-tiles g-tiles-row" data-testid="cb-tiles">
            @for (p of b.places; track p.place) {
              <div [class]="'ph-tile g-t-' + placeColour(p.place)"><span class="ph-muted">{{ placeName(p.place) }} · {{ i18n.t('cb.should') }}</span><b [attr.data-testid]="'cb-closing-' + p.place">{{ tsh(p.closing) }}</b></div>
            }
            <div class="ph-tile g-t-teal"><span class="ph-muted">{{ i18n.t('st.total') }}</span><b class="ph-accent">{{ tsh(totalHeld(b)) }}</b></div>
            <div class="ph-tile g-t-green"><span class="ph-muted">{{ i18n.t('cb.in') }}</span><b class="ph-good">{{ tsh(sumOf(b, 'in')) }}</b></div>
            <div class="ph-tile g-t-red"><span class="ph-muted">{{ i18n.t('cb.out') }}</span><b class="ph-bad">{{ tsh(sumOf(b, 'out')) }}</b></div>
          </div>
        }
      </div>
      @if (result()) { <section class="ph-card cb-wide" data-testid="cb-result"><p>{{ result() }}</p></section> }

      @if (error()) {
        <section class="ph-card cb-wide"><p data-testid="cb-error">{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (!book()) {
        <section class="ph-card cb-wide"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else {
        @let b = book()!;
        <!-- each place on one line: where it started, what came in and went out, what it should hold -->
        <section class="cb-wide" data-testid="cb-joined">
          <h3 class="cb-title">{{ i18n.t('cb.by.place') }}</h3>
          <div class="table-scroll-container fit-page">
            <table class="grid-table g-grid" data-testid="cb-places">
              <thead><tr>
                <th class="no-col">#</th><th>{{ i18n.t('cb.place') }}</th><th class="text-right">{{ i18n.t('cb.opening') }}</th>
                <th class="text-right">{{ i18n.t('cb.in') }}</th><th class="text-right">{{ i18n.t('cb.out') }}</th><th class="text-right">{{ i18n.t('cb.should') }}</th>
              </tr></thead>
              <tbody>
                @for (p of b.places; track p.place) {
                  <tr [attr.data-testid]="'cb-place-' + p.place">
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td class="font-bold">{{ placeName(p.place) }}</td>
                    <td class="text-right">{{ tsh(p.opening) }}</td>
                    <td class="text-right"><span class="ph-good">{{ tsh(p.in) }}</span></td>
                    <td class="text-right"><span class="ph-bad">{{ tsh(p.out) }}</span></td>
                    <td class="text-right"><b>{{ tsh(p.closing) }}</b></td>
                  </tr>
                }
              </tbody>
              <tfoot><tr>
                <td class="no-col"></td><td class="font-bold">{{ i18n.t('st.total') }}</td>
                <td class="text-right"><b>{{ tsh(sumOf(b, 'opening')) }}</b></td><td class="text-right"><b>{{ tsh(sumOf(b, 'in')) }}</b></td>
                <td class="text-right"><b>{{ tsh(sumOf(b, 'out')) }}</b></td><td class="text-right"><b>{{ tsh(totalHeld(b)) }}</b></td>
              </tr></tfoot>
            </table>
          </div>
        </section>

        <!-- day by day for one place at a time, with what was counted and the difference -->
        <section class="cb-wide" data-testid="cb-days">
          <div class="cb-head-row">
            <h3 class="cb-title">{{ i18n.t('cb.days') }}</h3>
            <div class="ph-chips g-seg">
              @for (p of places; track p) {
                <button type="button" class="pill-tab" [class.is-active]="dayPlace() === p" (click)="dayPlace.set(p)" [attr.data-testid]="'cb-days-' + p">{{ placeName(p) }}</button>
              }
            </div>
          </div>
          @let pl = placeOf(b, dayPlace());
          <div class="table-scroll-container fit-page">
            <table class="grid-table g-grid">
              <thead><tr>
                <th class="no-col">#</th><th>{{ i18n.t('g.date') }}</th><th class="text-right">{{ i18n.t('cb.in') }}</th><th class="text-right">{{ i18n.t('cb.out') }}</th>
                <th class="text-right">{{ i18n.t('cb.should') }}</th><th class="text-right">{{ i18n.t('cb.counted') }}</th><th class="text-right">{{ i18n.t('cb.difference') }}</th>
              </tr></thead>
              <tbody>
                @for (d of pl?.days ?? []; track d.date) {
                  <tr>
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td>{{ day(d.date) }}</td>
                    <td class="text-right">{{ d.in ? tsh(d.in) : '—' }}</td>
                    <td class="text-right">{{ d.out ? tsh(d.out) : '—' }}</td>
                    <td class="text-right"><b>{{ tsh(d.closing) }}</b></td>
                    <td class="text-right">{{ d.counted === null ? '—' : tsh(d.counted) }}</td>
                    <td class="text-right">
                      @if (d.counted === null) { — } @else if (d.difference === 0) { <span class="ph-good">{{ i18n.t('cb.ok') }}</span> }
                      @else { <b [class.ph-bad]="d.difference < 0" [class.ph-warn]="d.difference > 0">{{ d.difference < 0 ? '−' : '+' }}{{ tsh(Math.abs(d.difference)) }}</b> }
                    </td>
                  </tr>
                } @empty {
                  <tr><td colspan="7" class="ph-muted">{{ i18n.t('cb.no.days') }}</td></tr>
                }
              </tbody>
            </table>
          </div>
        </section>

        <!-- what the owner put in or took out, each with its three dots -->
        <section class="cb-wide">
          <h3 class="cb-title">{{ i18n.t('cb.owner.moves') }}</h3>
          <div class="table-scroll-container fit-page">
            <table class="grid-table g-grid" data-testid="cb-moves">
              <thead><tr>
                <th class="no-col">#</th><th>{{ i18n.t('g.date') }}</th><th>{{ i18n.t('g.kind') }}</th><th>{{ i18n.t('cb.place') }}</th>
                <th>{{ i18n.t('g.note') }}</th><th class="text-right">{{ i18n.t('cb.amount') }}</th><th class="text-right">{{ i18n.t('g.actions') }}</th>
              </tr></thead>
              <tbody>
                @for (m of b.moves; track m.id) {
                  <tr [attr.data-testid]="'cb-move-' + m.id">
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td>{{ day(m.movedOn) }}</td>
                    <td class="font-bold">{{ kindName(m.kind) }}</td>
                    <td>{{ placeName(m.method) }}</td>
                    <td class="g-long" [title]="m.note || '—'">{{ m.note || '—' }}</td>
                    <td class="text-right"><b [class.ph-good]="m.kind !== 'owner_withdrawal'" [class.ph-bad]="m.kind === 'owner_withdrawal'">{{ tsh(m.amount) }}</b></td>
                    <td class="text-right"><app-row-menu [items]="moveMenu" [testid]="'cb-remove-' + m.id" (picked)="removeMove(m)" /></td>
                  </tr>
                } @empty {
                  <tr><td colspan="7" class="ph-muted">{{ i18n.t('cb.no.moves') }}</td></tr>
                }
              </tbody>
            </table>
          </div>
        </section>
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
        <button type="button" class="btn-primary is-success" [disabled]="busy()" (click)="saveMove()" data-testid="cb-move-save">{{ i18n.t('common.save') }}</button>
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
        <button type="button" class="btn-primary is-success" [disabled]="busy()" (click)="saveCount()" data-testid="cb-count-save">{{ i18n.t('cb.compare') }}</button>
      </div>
    </app-modal-dialog>
  `,
  styles: [
    `
      .cb-wide { grid-column: 1 / -1; }
      h3.cb-title { margin: 6px 0 8px; font-size: 16px; font-weight: 900; }
      .cb-head-row { display: flex; align-items: center; justify-content: space-between; gap: 10px; flex-wrap: wrap; margin-bottom: 8px; }
      .cb-head-row h3.cb-title { margin: 0; }
      .g-grow { flex: 1; }
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
  /** The place whose days are shown. */
  protected readonly dayPlace = signal<string>('cash');
  protected readonly day = dayLabel;
  protected get moveMenu(): MenuItem[] {
    return [{ id: 'remove', label: this.i18n.t('cb.remove'), danger: true }];
  }
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

  protected placeColour(p: string): string {
    return p === 'cash' ? 'green' : p === 'mobile' ? 'blue' : 'purple';
  }

  protected placeOf(b: Cashbook, p: string): CashPlace | undefined {
    return b.places.find((x) => x.place === p);
  }

  protected sumOf(b: Cashbook, what: 'opening' | 'in' | 'out'): number {
    return b.places.reduce((a, p) => a + p[what], 0);
  }

  protected totalHeld(b: Cashbook): number {
    return b.places.reduce((a, p) => a + p.closing, 0);
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
