import { Component, EventEmitter, Input, OnChanges, Output, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';

/**
 * Previous data: what a member held and owed BEFORE the group used the app, entered by a leader. Totals as of a date (savings, shares,
 * joining fee and each kind of contribution: JAMII, a refundable project contribution, ...), and a loan that was still running. They count
 * at once in the member's account but are records, not cash. What was entered is listed below; a mistake is removed with its three dots.
 */
@Component({
  selector: 'app-g-previous',
  imports: [FormsModule, ModalDialogComponent, RowMenuComponent],
  template: `
    <app-modal-dialog [show]="!!member" [eyebrow]="i18n.t('g.prev.title')" [title]="member?.['full_name'] ?? ''" size="xl" (close)="closed.emit()">
      <div slot="body" data-testid="g-previous">
        <p class="ph-muted" style="margin: 0 0 10px">{{ i18n.t('g.prev.intro') }}</p>

        <section class="ph-card">
          <h3>{{ i18n.t('g.prev.totals') }}</h3>
          <div class="g-prev-grid">
            <label class="ph-field">{{ i18n.t('g.prev.as_of') }} *<input class="modal-input" type="date" [max]="today()" [(ngModel)]="f['as_of']" name="pa" data-testid="g-prev-as-of" /></label>
            <label class="ph-field">{{ i18n.t('g.cat.savings') }}<input class="modal-input" inputmode="numeric" [(ngModel)]="f['savings']" name="ps" placeholder="0" data-testid="g-prev-savings" /></label>
            <label class="ph-field">{{ i18n.t('g.cat.shares') }}<input class="modal-input" inputmode="numeric" [(ngModel)]="f['shares']" name="psh" placeholder="0" /></label>
            <label class="ph-field">{{ i18n.t('g.cat.joining_fee') }}<input class="modal-input" inputmode="numeric" [(ngModel)]="f['joining_fee']" name="pj" placeholder="0" /></label>
            @for (t of types(); track t['id']) {
              <label class="ph-field">
                <span>{{ t['name'] }} @if (t['refundable']) { <span class="ph-badge ph-good">{{ i18n.t('g.c.refundable') }}</span> }</span>
                <input class="modal-input" inputmode="numeric" [(ngModel)]="c[t['id']]" [name]="'pc' + t['id']" placeholder="0" [attr.data-testid]="'g-prev-c-' + t['id']" />
              </label>
            }
            <label class="ph-field" style="grid-column: 1 / -1">{{ i18n.t('g.note') }}<input class="modal-input" [(ngModel)]="f['note']" name="pn" [placeholder]="i18n.t('g.prev.note.ph')" /></label>
          </div>
          @if (!types().length) { <p class="ph-muted">{{ i18n.t('g.prev.no.types') }}</p> }
          <div class="g-prev-foot">
            <span class="ph-muted">{{ i18n.t('g.prev.total') }}: <b>{{ tsh(totalTyped()) }}</b></span>
            <button type="button" class="btn-primary ph-btn" [disabled]="busy()" (click)="saveTotals()" data-testid="g-prev-save">{{ i18n.t('g.prev.save') }}</button>
          </div>
        </section>

        <section class="ph-card">
          <h3>{{ i18n.t('g.prev.loan') }}</h3>
          <div class="g-prev-grid">
            <label class="ph-field">{{ i18n.t('g.prev.loan.amount') }} *<input class="modal-input" inputmode="numeric" [(ngModel)]="l['amount']" name="la" data-testid="g-prev-l-amount" /></label>
            <label class="ph-field">{{ i18n.t('g.prev.loan.left') }} *<input class="modal-input" inputmode="numeric" [(ngModel)]="l['remaining']" name="lr" data-testid="g-prev-l-left" /></label>
            <label class="ph-field">{{ i18n.t('g.prev.loan.instalment') }} *<input class="modal-input" inputmode="numeric" [(ngModel)]="l['instalment']" name="li" data-testid="g-prev-l-inst" /></label>
            <label class="ph-field">{{ i18n.t('g.prev.loan.next') }} *<input class="modal-input" type="date" [(ngModel)]="l['next_due']" name="ln" data-testid="g-prev-l-next" /></label>
            <label class="ph-field">{{ i18n.t('g.prev.loan.given') }}<input class="modal-input" type="date" [max]="today()" [(ngModel)]="l['issued_on']" name="lg" /></label>
            <label class="ph-field">{{ i18n.t('g.l.purpose') }}<input class="modal-input" [(ngModel)]="l['purpose']" name="lp" /></label>
          </div>
          <div class="g-prev-foot">
            <span class="ph-muted">{{ i18n.t('g.prev.loan.hint') }}</span>
            <button type="button" class="btn-primary ph-btn" [disabled]="busy()" (click)="saveLoan()" data-testid="g-prev-l-save">{{ i18n.t('g.prev.loan.save') }}</button>
          </div>
        </section>

        <section class="ph-card">
          <h3>{{ i18n.t('g.prev.entered') }}</h3>
          <div class="table-scroll-container fit-page">
            <table class="grid-table g-grid" data-testid="g-prev-list">
              <thead><tr>
                <th class="no-col">#</th><th>{{ i18n.t('g.prev.as_of') }}</th><th>{{ i18n.t('g.kind') }}</th><th class="text-right">{{ i18n.t('g.amount') }}</th>
                <th>{{ i18n.t('g.note') }}</th><th>{{ i18n.t('g.prev.by') }}</th><th class="text-right">{{ i18n.t('g.actions') }}</th>
              </tr></thead>
              <tbody>
                @for (e of entries(); track e['id']) {
                  <tr>
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td>{{ day(e['paid_on']) }}</td>
                    <td class="font-bold">{{ e['category'] === 'contribution' ? (e['obligation_label'] || cat('contribution')) : cat(e['category']) }}</td>
                    <td class="text-right">{{ tsh(e['amount']) }}</td>
                    <td class="g-long" [title]="e['note'] || '—'">{{ e['note'] || '—' }}</td>
                    <td>{{ e['submitted_by_name'] || '—' }}</td>
                    <td class="text-right"><app-row-menu [items]="removeMenu()" [testid]="'g-prev-e-menu-' + e['id']" (picked)="removeEntry(e)" /></td>
                  </tr>
                }
                @for (x of loans(); track x['id']) {
                  <tr>
                    <td class="no-col">{{ entries().length + $index + 1 }}</td>
                    <td>{{ x['disbursed_on'] ? day(x['disbursed_on']) : '—' }}</td>
                    <td class="font-bold">{{ i18n.t('g.prev.loan.row') }} {{ x['reference'] }}</td>
                    <td class="text-right">{{ tsh(n(x['outstanding'])) }} / {{ tsh(n(x['amount_approved'])) }}</td>
                    <td class="g-long" [title]="x['purpose']">{{ x['purpose'] }}</td>
                    <td>—</td>
                    <td class="text-right"><app-row-menu [items]="orNone(n(x['repaid']) > 0 ? [] : removeMenu())" [testid]="'g-prev-l-menu-' + x['id']" (picked)="removeLoan(x)" /></td>
                  </tr>
                }
                @if (!entries().length && !loans().length) {
                  <tr><td colspan="7" class="ph-muted">{{ i18n.t('g.prev.none') }}</td></tr>
                }
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </app-modal-dialog>
  `,
  styles: [`
    .g-prev-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 10px; }
    .g-prev-foot { display: flex; align-items: center; justify-content: space-between; gap: 10px; margin-top: 12px; flex-wrap: wrap; }
    .ph-card + .ph-card { margin-top: 12px; }
  `],
})
export class GPreviousDialog extends GBase implements OnChanges {
  /** The member whose previous data is entered; null closes the window. */
  @Input() member: Row | null = null;
  @Output() readonly closed = new EventEmitter<void>();
  /** Something was entered or removed: the page reloads what it shows. */
  @Output() readonly changed = new EventEmitter<void>();

  protected readonly types = signal<Row[]>([]);
  protected readonly entries = signal<Row[]>([]);
  protected readonly loans = signal<Row[]>([]);
  protected f: Row = {};
  /** contribution kind id => the amount typed */
  protected c: Record<string, string> = {};
  protected l: Row = {};

  ngOnChanges(): void {
    if (!this.member) return;
    this.f = { as_of: this.today() };
    this.c = {};
    this.l = {};
    void this.load();
  }

  protected removeMenu(): MenuItem[] {
    return [{ id: 'remove', label: this.i18n.t('g.remove'), danger: true }];
  }

  protected totalTyped(): number {
    return ['savings', 'shares', 'joining_fee'].reduce((a, k) => a + this.amount(this.f[k]), 0) + Object.values(this.c).reduce((a, v) => a + this.amount(v), 0);
  }

  private async load(): Promise<void> {
    const id = this.member?.['id'];
    if (!id) return;
    try {
      const d = await this.api.get(`/members/${id}/previous`);
      this.types.set(((d['types'] as Row[]) ?? []).filter((t) => t['active'] !== false));
      this.entries.set((d['entries'] as Row[]) ?? []);
      this.loans.set((d['loans'] as Row[]) ?? []);
    } catch (e) {
      this.stop(this.failed(e));
    }
  }

  protected async saveTotals(): Promise<void> {
    const m = this.member;
    if (!m) return;
    if (!this.f['as_of']) return this.stop(this.i18n.t('g.prev.need.date'));
    if (this.totalTyped() <= 0) return this.stop(this.i18n.t('g.prev.need.amount'));
    const body: Row = { as_of: this.f['as_of'] };
    for (const k of ['savings', 'shares', 'joining_fee']) if (this.amount(this.f[k]) > 0) body[k] = this.amount(this.f[k]);
    body['contributions'] = Object.entries(this.c).filter(([, v]) => this.amount(v) > 0).map(([id, v]) => ({ type_id: Number(id), amount: this.amount(v) }));
    if (String(this.f['note'] ?? '').trim()) body['note'] = String(this.f['note']).trim();
    if (!(await this.sure(this.i18n.t('g.prev.save'), this.i18n.t('g.prev.sure', m['full_name'], this.tsh(this.totalTyped())), this.i18n.t('g.save')))) return;
    if (await this.act(() => this.api.post(`/members/${m['id']}/previous`, body), this.i18n.t('g.saved'))) {
      this.f = { as_of: this.f['as_of'] };
      this.c = {};
      await this.load();
      this.changed.emit();
    }
  }

  protected async saveLoan(): Promise<void> {
    const m = this.member;
    if (!m) return;
    const amount = this.amount(this.l['amount']);
    const remaining = this.amount(this.l['remaining']);
    const instalment = this.amount(this.l['instalment']);
    if (amount < 1 || remaining < 1 || instalment < 1 || !this.l['next_due']) return this.stop(this.i18n.t('g.prev.loan.need'));
    if (remaining > amount) return this.stop(this.i18n.t('g.prev.loan.too.much'));
    const body: Row = { amount, remaining, instalment, next_due: this.l['next_due'] };
    if (this.l['issued_on']) body['issued_on'] = this.l['issued_on'];
    if (String(this.l['purpose'] ?? '').trim()) body['purpose'] = String(this.l['purpose']).trim();
    if (!(await this.sure(this.i18n.t('g.prev.loan.save'), this.i18n.t('g.prev.loan.sure', m['full_name'], this.tsh(remaining)), this.i18n.t('g.save')))) return;
    if (await this.act(() => this.api.post(`/members/${m['id']}/previous/loan`, body), this.i18n.t('g.saved'))) {
      this.l = {};
      await this.load();
      this.changed.emit();
    }
  }

  protected async removeEntry(e: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.remove'), this.i18n.t('g.prev.remove.sure', this.tsh(e['amount'])), this.i18n.t('g.remove'), true))) return;
    if (await this.act(() => this.api.del(`/previous/entries/${e['id']}`), this.i18n.t('g.saved'))) {
      await this.load();
      this.changed.emit();
    }
  }

  protected async removeLoan(x: Row): Promise<void> {
    if (!(await this.sure(this.i18n.t('g.remove'), this.i18n.t('g.prev.remove.sure', this.tsh(this.n(x['outstanding']))), this.i18n.t('g.remove'), true))) return;
    if (await this.act(() => this.api.del(`/previous/loans/${x['id']}`), this.i18n.t('g.saved'))) {
      await this.load();
      this.changed.emit();
    }
  }
}
