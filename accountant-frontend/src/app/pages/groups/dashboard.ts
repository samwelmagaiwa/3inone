import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { monthKey } from '../../core/format';
import { Row } from '../../core/groups/groups-api.service';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';

/** Each kind of work that can wait for a leader, and the page where it is done. */
export const G_WAITING: Record<string, string> = {
  payments_to_verify: '/groups/payments',
  applications: '/groups/members',
  members_overdue: '/groups/contributions',
  loans_to_recommend: '/groups/loans',
  loans_to_approve: '/groups/loans',
  loans_to_disburse: '/groups/loans',
  benefits_to_decide: '/groups/welfare',
  projects_to_review: '/groups/projects',
  projects_to_approve: '/groups/projects',
  expenses_to_approve: '/groups/expenses',
  expenses_to_pay: '/groups/expenses',
  dividends_to_approve: '/groups/dividends',
  minutes_to_approve: '/groups/meetings',
  actions_overdue: '/groups/meetings',
  my_actions: '/groups/meetings',
  meetings_to_record: '/groups/meetings',
  hire_charges: '/groups/assets',
  hires_to_decide: '/groups/assets',
  hires_overdue: '/groups/assets',
  votes_to_cast: '/groups/votings',
  guarantees: '/groups/loans',
};

/**
 * The group at a glance (the phone's leaders' dashboard): what waits for this person, the cash on record and the month's money, how
 * much of the month's contributions came in, loans owed, the year's welfare, dividends, hire income and spending, 12 months of money in
 * and out, and the month by kind. Money appears only for whoever sees the group's money.
 */
@Component({
  selector: 'app-g-dashboard',
  imports: [RowMenuComponent, FormsModule, RouterLink],
  template: `
    <div class="ad ph-page" data-testid="g-dashboard">
      <div class="g-toolbar">
        <input class="g-select" type="month" [ngModel]="month()" (ngModelChange)="pickMonth($event)" [attr.aria-label]="i18n.t('g.month')" data-testid="g-dash-month" />
        <button type="button" class="btn-outline ph-btn" (click)="load()" data-testid="g-dash-refresh">{{ i18n.t('common.refresh') }}</button>
      </div>

      @if (error()) {
        <section class="ph-card"><p data-testid="g-dash-error">{{ error() }}</p><button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('pl.retry') }}</button></section>
      } @else if (!d()) {
        <section class="ph-card"><p class="ph-muted">{{ i18n.t('pl.loading') }}</p></section>
      } @else {
        @let data = d()!;
        @let m = data['money'];
        <div class="ph-tiles g-tiles-row" data-testid="g-tiles">
          @if (m) {
            <div class="ph-tile" data-testid="g-cash"><span class="ph-muted">{{ i18n.t('g.cash') }}</span><b class="ph-accent">{{ tsh(m['cash_on_record']) }}</b></div>
            <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.month.in') }}</span><b class="ph-good">{{ tsh(m['month_in']) }}</b></div>
            <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.month.out') }}</span><b class="ph-bad">{{ tsh(m['month_out']) }}</b></div>
            <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.savings') }}</span><b>{{ tsh(m['savings']) }}</b></div>
            <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.shares') }}</span><b>{{ tsh(m['shares']) }}</b></div>
            @if (m['pending_count'] > 0) {
              <a class="ph-tile g-link" routerLink="/groups/payments"><span class="ph-muted">{{ i18n.t('g.pending') }}</span><b class="ph-warn">{{ m['pending_count'] }}</b></a>
            }
          }
          <a class="ph-tile g-link" routerLink="/groups/members" data-testid="g-active"><span class="ph-muted">{{ i18n.t('g.members.active') }}</span><b>{{ data['members']?.['active'] ?? 0 }}</b></a>
          @if (data['members']?.['applications'] > 0) {
            <a class="ph-tile g-link" routerLink="/groups/members"><span class="ph-muted">{{ i18n.t('g.applications') }}</span><b class="ph-warn">{{ data['members']['applications'] }}</b></a>
          }
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.joined.month') }}</span><b>{{ data['members']?.['joined_in_month'] ?? 0 }}</b></div>
        </div>

        @if (m) {
          <div class="ph-card ph-joined ph-cols">
            <section class="ph-sec" data-testid="g-collection">
              <h3>{{ i18n.t('g.collection') }}</h3>
              @let c = m['contributions'] ?? {};
              <div class="g-bar"><i [style.width.%]="rate(c)"></i></div>
              <div class="ph-row"><span class="ph-muted">{{ tsh(c['collected'] ?? 0) }} / {{ tsh(c['expected'] ?? 0) }}</span><b class="ph-accent">{{ rate(c) }}%</b></div>
              <div class="ph-line"><span>{{ i18n.t('g.overdue.amount') }}</span><b [class.ph-bad]="(c['overdue_amount'] ?? 0) > 0">{{ tsh(c['overdue_amount'] ?? 0) }}</b></div>
              <div class="ph-line"><span>{{ i18n.t('g.overdue.members') }}</span><b>{{ c['overdue_members'] ?? 0 }}</b></div>
            </section>
            <section class="ph-sec">
              <h3>{{ i18n.t('g.loans.now') }}</h3>
              @let l = m['loans'] ?? {};
              <div class="ph-line"><span>{{ i18n.t('g.loans.owed') }}</span><b>{{ tsh((l['principal'] ?? 0) + (l['interest'] ?? 0)) }}</b></div>
              <div class="ph-line"><span>{{ i18n.t('g.loans.arrears') }}</span><b [class.ph-bad]="(l['arrears'] ?? 0) > 0">{{ tsh(l['arrears'] ?? 0) }}</b></div>
              <div class="ph-line"><span>{{ i18n.t('g.loans.running') }}</span><b>{{ l['running'] ?? 0 }}</b></div>
              <div class="ph-line"><span>{{ i18n.t('g.loans.late') }}</span><b [class.ph-bad]="(l['overdue'] ?? 0) > 0">{{ l['overdue'] ?? 0 }}</b></div>
            </section>
            <section class="ph-sec">
              <h3>{{ i18n.t('g.year') }}</h3>
              @let y = m['year'] ?? {};
              <div class="ph-line"><span>{{ i18n.t('g.year.welfare') }}</span><b>{{ tsh(y['welfare_paid'] ?? 0) }}</b></div>
              <div class="ph-line"><span>{{ i18n.t('g.year.dividends') }}</span><b>{{ tsh(y['dividends'] ?? 0) }}</b></div>
              <div class="ph-line"><span>{{ i18n.t('g.year.hire') }}</span><b>{{ tsh(y['hire_income'] ?? 0) }}</b></div>
              <div class="ph-line"><span>{{ i18n.t('g.year.spent') }}</span><b>{{ tsh(y['expenses'] ?? 0) }}</b></div>
            </section>
            <section class="ph-sec">
              <h3>{{ i18n.t('g.mix') }}</h3>
              @for (x of m['mix'] ?? []; track x['category']) {
                <div class="ph-line"><span>{{ cat(x['category']) }}</span><b><span class="ph-good">+{{ tsh(x['in']) }}</span> · <span class="ph-bad">-{{ tsh(x['out']) }}</span></b></div>
              } @empty {
                <p class="ph-muted">{{ i18n.t('g.none.month') }}</p>
              }
            </section>
          </div>

          <div class="ph-card" data-testid="g-trend">
            <h3>{{ i18n.t('g.trend') }}</h3>
            <div class="g-chart">
              @for (t of m['trend'] ?? []; track t['month']) {
                <div class="g-col" [title]="t['month'] + ': +' + tsh(t['in']) + ' / -' + tsh(t['out'])">
                  <div class="g-pair">
                    <i class="g-in" [style.height.%]="pct(t['in'])"></i>
                    <i class="g-out" [style.height.%]="pct(t['out'])"></i>
                  </div>
                  <span>{{ t['month'].slice(5) }}</span>
                </div>
              }
            </div>
            <p class="ph-muted"><span class="ph-good">■</span> {{ i18n.t('g.in') }} &nbsp; <span class="ph-bad">■</span> {{ i18n.t('g.out') }}</p>
          </div>
        }

        @if (data['next_meeting']; as nm) {
          <a class="ph-card g-link" routerLink="/groups/meetings" data-testid="g-next-meeting">
            <h3>{{ i18n.t('g.next.meeting') }}</h3>
            <div class="ph-row"><span>{{ nm['title'] }}</span><b class="ph-warn">{{ when(nm['starts_at']) }}</b></div>
            @if (nm['venue']) { <p class="ph-muted">{{ nm['venue'] }}</p> }
          </a>
        }
      }

      @if (waiting().length) {
        <h3>{{ i18n.t('g.waiting') }}</h3>
<div class="table-scroll-container fit-page" data-testid="g-waiting">
          <table class="grid-table g-grid">
            <thead>
              <tr>
              <th class="no-col">#</th>
              <th>{{ i18n.t('g.what') }}</th>
              <th class="text-right">{{ i18n.t('g.count.short') }}</th>
              <th class="text-right">{{ i18n.t('g.actions') }}</th>
              </tr>
            </thead>
            <tbody>
              @for (w of waiting(); track w.key) {
                <tr>
                  <td class="no-col">{{ $index + 1 }}</td>
                  <td class="font-bold"><a class="g-link" [routerLink]="w.path" [attr.data-testid]="'g-wait-' + w.key">{{ i18n.t('g.wait.' + w.key) }}</a></td>
                  <td class="text-right"><b class="ph-warn">{{ w.count }}</b></td>
                  <td class="text-right"><app-row-menu [items]="orNone([{ id: 'open', label: i18n.t('g.open'), primary: true }])" [testid]="'g-wait-menu-' + w.key" (picked)="go(w.path)" /></td>
                </tr>
              } @empty {
                <tr><td colspan="4" class="ph-muted">{{ i18n.t('g.none') }}</td></tr>
              }
            </tbody>
          </table>
        </div>
      }
    </div>
  `,
  styles: [
    `
      .g-link { cursor: pointer; text-decoration: none; color: inherit; }
      a.ph-card.g-link { display: block; }
      a.ph-row.g-link { display: flex; }
      a.ph-tile.g-link { display: grid; }
      /* The figures in ONE row on a computer screen: equal columns, the amounts never broken in two */
      @media (min-width: 1100px) {
        .g-tiles-row { grid-template-columns: none; grid-auto-flow: column; grid-auto-columns: minmax(0, 1fr); }
        .g-tiles-row .ph-tile { padding: 9px 10px; min-width: 0; }
        .g-tiles-row .ph-tile b { font-size: clamp(12px, 0.8vw, 17px); white-space: nowrap; letter-spacing: -0.01em; }
        .g-tiles-row .ph-tile .ph-muted { font-size: 11px; line-height: 1.25; }
      }
      a.ph-tile.g-link:hover, a.ph-card.g-link:hover { border-color: #20b8ce; }
      .g-bar { height: 10px; border-radius: 99px; background: rgba(255, 255, 255, 0.18); overflow: hidden; margin: 8px 0 4px; }
      .g-bar i { display: block; height: 100%; background: linear-gradient(90deg, #1ba3c7, #20b8ce); }
      .g-chart { display: grid; grid-template-columns: repeat(12, 1fr); gap: 6px; align-items: end; height: 170px; margin-top: 8px; }
      .g-col { display: grid; grid-template-rows: 1fr auto; height: 100%; gap: 4px; text-align: center; font-size: 11px; opacity: 0.9; }
      .g-pair { display: flex; align-items: flex-end; justify-content: center; gap: 2px; height: 100%; }
      .g-pair i { display: block; width: 40%; min-height: 2px; border-radius: 4px 4px 0 0; }
      .g-in { background: #10b981; }
      .g-out { background: #ef4444; }
    `,
  ],
})
export class GDashboardPage extends GBase implements OnInit {
  private readonly router = inject(Router);
  protected readonly month = signal(monthKey(new Date()));
  protected readonly d = signal<Row | null>(null);
  protected readonly error = signal('');
  private ticket = 0;

  protected readonly waiting = computed(() =>
    Object.entries(this.ctx.waiting())
      .filter(([k, n]) => n > 0 && G_WAITING[k])
      .map(([key, count]) => ({ key, count, path: G_WAITING[key] })),
  );

  /** The highest month in the trend, so the bars share one scale. */
  private readonly top = computed(() => {
    const t: Row[] = this.d()?.['money']?.['trend'] ?? [];
    return Math.max(1, ...t.map((x) => Math.max(Number(x['in']) || 0, Number(x['out']) || 0)));
  });

  protected go(path: string): void {
    void this.router.navigate([path]);
  }

  ngOnInit(): void {
    void this.ctx.reload();
    void this.load();
  }

  protected pickMonth(v: string): void {
    if (!/^\d{4}-\d{2}$/.test(v ?? '')) return;
    this.month.set(v);
    void this.load();
  }

  protected rate(c: Row): number {
    const expected = Number(c['expected']) || 0;
    return expected <= 0 ? 0 : Math.min(100, Math.round(((Number(c['collected']) || 0) * 100) / expected));
  }

  protected pct(v: unknown): number {
    return Math.round(((Number(v) || 0) * 100) / this.top());
  }

  async load(): Promise<void> {
    const ask = ++this.ticket;
    this.error.set('');
    try {
      const d = await this.api.get('/dashboard', { month: this.month() });
      if (ask === this.ticket) this.d.set(d);
    } catch (e) {
      if (ask === this.ticket) {
        this.d.set(null);
        this.error.set(this.failed(e));
      }
    }
  }
}
