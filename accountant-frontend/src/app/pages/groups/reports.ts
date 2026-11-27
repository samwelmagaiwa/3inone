import { Component, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { GBase } from './g-base';
import { MemberPick, PickedMember } from './member-pick';

/**
 * Reports: the group in numbers for a period (members, money in and out by kind, contributions, loans now, meetings held), one member's
 * statement with every payment and the balance after it, and the exports (the member register and the period's verified payments, as
 * CSV files a spreadsheet opens).
 */
@Component({
  selector: 'app-g-reports',
  imports: [FormsModule, MemberPick],
  template: `
    <div class="ad ph-page" data-testid="g-reports">
      <div class="g-toolbar">
        <input class="g-select" type="date" [(ngModel)]="from" name="rf" [attr.aria-label]="i18n.t('ad.from')" [title]="i18n.t('ad.from')" />
        <input class="g-select" type="date" [(ngModel)]="to" name="rt" [attr.aria-label]="i18n.t('ad.to')" [title]="i18n.t('ad.to')" />
        <button type="button" class="btn-outline ph-btn" (click)="load()" data-testid="g-r-show">{{ i18n.t('ad.apply') }}</button>
        <span style="flex: 1"></span>
        @if (can('view_finance')) { <button type="button" class="btn-primary is-info ph-btn" (click)="exportPayments()" data-testid="g-r-csv-pay">{{ i18n.t('g.r.csv.payments') }}</button> }
        @if (can('view_members')) { <button type="button" class="btn-primary is-info ph-btn" (click)="exportMembers()" data-testid="g-r-csv-members">{{ i18n.t('g.r.csv.members') }}</button> }
      </div>

      @if (can('view_finance')) {
        @if (error()) {
          <section class="ph-card"><p>{{ error() }}</p></section>
        } @else if (r(); as r) {
          <div class="ph-tiles">
            <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.r.joined') }}</span><b>{{ r['members']?.['joined'] ?? 0 }}</b></div>
            <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.r.meetings') }}</span><b>{{ r['meetings_held'] ?? 0 }}</b></div>
            <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.r.expected') }}</span><b>{{ tsh(r['contributions']?.['expected'] ?? 0) }}</b></div>
            <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.r.collected') }}</span><b class="ph-good">{{ tsh(r['contributions']?.['collected'] ?? 0) }}</b></div>
            <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.overdue.amount') }}</span><b class="ph-bad">{{ tsh(r['contributions']?.['overdue_now'] ?? 0) }}</b></div>
          </div>
          <div class="ph-card ph-joined ph-cols">
            <section class="ph-sec">
              <h3>{{ i18n.t('g.r.money') }}</h3>
              @for (k of keys(r['money']); track k) {
                <div class="ph-line"><span>{{ cat(k) }}</span><b><span class="ph-good">+{{ tsh(r['money'][k]['in'] ?? 0) }}</span> · <span class="ph-bad">-{{ tsh(r['money'][k]['out'] ?? 0) }}</span></b></div>
              } @empty { <p class="ph-muted">{{ i18n.t('g.none') }}</p> }
            </section>
            <section class="ph-sec">
              <h3>{{ i18n.t('g.r.members') }}</h3>
              @for (k of keys(r['members']?.['by_status']); track k) {
                <div class="ph-line"><span>{{ status(k) }}</span><b>{{ r['members']['by_status'][k] }}</b></div>
              }
              <h3 style="margin-top: 8px">{{ i18n.t('g.loans.now') }}</h3>
              @for (k of keys(r['loans_now']); track k) {
                <div class="ph-line"><span>{{ i18n.t('g.r.loan.' + k) }}</span><b>{{ k === 'running' || k === 'overdue' || k === 'count' ? r['loans_now'][k] : tsh(r['loans_now'][k]) }}</b></div>
              }
            </section>
          </div>
        }
      }

      <div class="ph-card" data-testid="g-r-statement">
        <h3>{{ i18n.t('g.r.statement') }}</h3>
        <app-g-member-pick [value]="who()" (picked$)="pick($event)" status="" />
        @if (statement(); as s) {
          <div class="ph-tiles" style="margin-top: 8px">
            <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.r.account') }}</span><b class="ph-accent">{{ tsh(s['account'] ?? 0) }}</b></div>
            @for (b of keys(s['balances']); track b) { <div class="ph-tile"><span class="ph-muted">{{ cat(b) }}</span><b>{{ tsh(s['balances'][b]) }}</b></div> }
            <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.r.owes') }}</span><b class="ph-bad">{{ tsh(s['owing_total'] ?? 0) }}</b></div>
          </div>
          <div class="table-scroll-container fit-page" data-testid="g-r-lines">
            <table class="grid-table g-grid">
              <thead>
                <tr>
                <th class="no-col">#</th>
                <th>{{ i18n.t('g.paid.on') }}</th>
                <th>{{ i18n.t('g.kind') }}</th>
                <th>{{ i18n.t('g.p.for') }}</th>
                <th>{{ i18n.t('g.receipt') }}</th>
                <th class="text-right">{{ i18n.t('g.in') }}</th>
                <th class="text-right">{{ i18n.t('g.out') }}</th>
                </tr>
              </thead>
              <tbody>
                @for (l of s['lines'] ?? []; track l['id']) {
                  <tr>
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td>{{ day(l['paid_on'] || l['date']) }}</td>
                    <td>{{ cat(l['category']) }}</td>
                    <td>{{ l['obligation_label'] || '—' }}</td>
                    <td>{{ l['receipt_number'] || l['reference'] }}</td>
                    <td class="text-right"><span class="ph-good">{{ l['direction'] === 'in' ? tsh(l['amount']) : '' }}</span></td>
                    <td class="text-right"><span class="ph-bad">{{ l['direction'] === 'out' ? tsh(l['amount']) : '' }}</span></td>
                  </tr>
                } @empty {
                  <tr><td colspan="7" class="ph-muted">{{ i18n.t('g.r.no.lines') }}</td></tr>
                }
              </tbody>
            </table>
          </div>
        }
      </div>
    </div>
  `,
})
export class GReportsPage extends GBase implements OnInit {
  protected from = `${new Date().getFullYear()}-01-01`;
  protected to = this.today();
  protected readonly r = signal<Row | null>(null);
  protected readonly error = signal('');
  protected readonly who = signal<PickedMember | null>(null);
  protected readonly statement = signal<Row | null>(null);

  ngOnInit(): void {
    if (this.can('view_finance')) void this.load();
  }

  protected keys(o: unknown): string[] {
    return o && typeof o === 'object' ? Object.keys(o as Row) : [];
  }

  async load(): Promise<void> {
    if (!this.can('view_finance')) return;
    this.error.set('');
    try {
      this.r.set(await this.api.get('/reports/summary', { from: this.from, to: this.to }));
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  protected async pick(m: PickedMember | null): Promise<void> {
    this.who.set(m);
    this.statement.set(null);
    if (!m) return;
    try {
      this.statement.set(await this.api.get(`/members/${m.id}/statement`));
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }

  protected exportPayments(): Promise<boolean> {
    return this.act(() => this.api.download('/reports/transactions.csv', `payments-${this.from}-${this.to}.csv`, { from: this.from, to: this.to }));
  }

  protected exportMembers(): Promise<boolean> {
    return this.act(() => this.api.download('/reports/members.csv', `members-${this.today()}.csv`));
  }
}
