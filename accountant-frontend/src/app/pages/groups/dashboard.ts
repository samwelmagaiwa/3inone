import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { monthKey } from '../../core/format';
import { Row } from '../../core/groups/groups-api.service';
import { MenuItem, RowMenuComponent } from '../../shared/components/row-menu/row-menu';
import { GBase } from './g-base';
import { GColor, GPieChart, GRoseChart, GSlice } from './g-charts';

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
  imports: [RowMenuComponent, FormsModule, RouterLink, GRoseChart, GPieChart],
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
          <!-- The charts, drawn like the school dashboard: white cards, coloured titles, the figures on the charts -->
          <div class="g-charts" data-testid="g-charts">
            <section class="g-ccard g-wide" data-testid="g-mix">
              <h3 class="g-ctitle">{{ i18n.t('g.ch.mix') }}</h3>
              @if (mixIn().length) {
                <app-g-rose [slices]="mixIn()" [label]="i18n.t('g.ch.mix')" />
              } @else {
                <p class="g-cempty">{{ i18n.t('g.none.month') }}</p>
              }
              @if (mixOut().length) {
                <p class="g-cfoot"><span>{{ i18n.t('g.ch.out') }}:</span>
                  @for (o of mixOut(); track o.label) { <b class="g-cbad">{{ o.label }} {{ tsh(o.value) }}</b> }
                </p>
              }
            </section>

            <section class="g-ccard" data-testid="g-collection">
              <h3 class="g-ctitle">{{ i18n.t('g.collection') }}</h3>
              @let c = m['contributions'] ?? {};
              <app-g-pie [slices]="collection()" [label]="i18n.t('g.collection')" [empty]="i18n.t('g.ch.nothing')" />
              <p class="g-cfoot">{{ tsh(c['collected'] ?? 0) }} / {{ tsh(c['expected'] ?? 0) }} · <b class="g-cgood">{{ rate(c) }}%</b></p>
              <p class="g-cfoot">{{ i18n.t('g.overdue.amount') }}: <b [class.g-cbad]="(c['overdue_amount'] ?? 0) > 0">{{ tsh(c['overdue_amount'] ?? 0) }}</b> · {{ i18n.t('g.overdue.members') }}: <b>{{ c['overdue_members'] ?? 0 }}</b></p>
            </section>

            <section class="g-ccard" data-testid="g-loans-chart">
              <h3 class="g-ctitle">{{ i18n.t('g.loans.now') }}</h3>
              @let l = m['loans'] ?? {};
              <app-g-pie [slices]="loanSlices()" [ring]="true" [label]="i18n.t('g.loans.now')" [empty]="i18n.t('g.ch.no.loans')" />
              <p class="g-cfoot">{{ i18n.t('g.loans.owed') }}</p>
              <p class="g-cbig">{{ tsh((l['principal'] ?? 0) + (l['interest'] ?? 0)) }}</p>
              <p class="g-cfoot">{{ i18n.t('g.loans.running') }}: <b>{{ l['running'] ?? 0 }}</b> · {{ i18n.t('g.loans.late') }}: <b [class.g-cbad]="(l['overdue'] ?? 0) > 0">{{ l['overdue'] ?? 0 }}</b></p>
            </section>

            <section class="g-ccard" data-testid="g-year">
              <h3 class="g-ctitle">{{ i18n.t('g.year') }}</h3>
              <p class="g-csub">{{ month().slice(0, 4) }}</p>
              <app-g-pie [slices]="yearSlices()" [ring]="true" [label]="i18n.t('g.year')" [empty]="i18n.t('g.ch.nothing')" />
              <p class="g-cfoot">{{ i18n.t('g.ch.net') }}</p>
              <p class="g-cbig" [class.g-cbad]="yearNet() < 0">{{ tsh(yearNet()) }}</p>
            </section>

            <section class="g-ccard g-trend-card" data-testid="g-trend">
              <h3 class="g-ctitle">{{ i18n.t('g.trend') }}</h3>
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
              <p class="g-ckeys"><span><i class="g-in"></i>{{ i18n.t('g.in') }}</span><span><i class="g-out"></i>{{ i18n.t('g.out') }}</span></p>
            </section>
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
      /* The chart cards: the same dark glass as every Groups card; the charts keep their eight colours, the words are light */
      .g-charts { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 16px; margin: 14px 0; }
      .g-ccard { background: rgba(255, 255, 255, 0.1); border: 1px solid rgba(255, 255, 255, 0.18); border-radius: 18px; padding: 18px 18px 16px; color: #fff; min-width: 0; text-align: center; }
      .g-wide { grid-column: span 2; }
      .g-trend-card { grid-column: span 3; }
      .g-ccard h3.g-ctitle { margin: 0 0 6px; font-size: 20px; font-weight: 800; color: #fff !important; letter-spacing: -0.01em; }
      .g-csub { margin: 0 0 6px; font-size: 15px; color: rgba(255, 255, 255, 0.7); }
      .g-cfoot { margin: 6px 0 0; font-size: 14px; color: rgba(255, 255, 255, 0.72); }
      .g-cfoot b { color: #fff; }
      .g-cfoot .g-cbad, b.g-cbad { color: #ff8a8a; margin-left: 6px; }
      .g-cgood { color: #6fd08c !important; }
      .g-cbig { margin: 2px 0 0; font-size: 24px; font-weight: 800; color: #6fd08c; }
      .g-cbig.g-cbad { color: #ff8a8a; }
      .g-cempty { color: rgba(255, 255, 255, 0.6); margin: 40px 0; }
      .g-chart { display: grid; grid-template-columns: repeat(12, 1fr); gap: 8px; align-items: end; height: 230px; margin-top: 10px; }
      .g-col { display: grid; grid-template-rows: 1fr auto; height: 100%; gap: 6px; text-align: center; font-size: 12px; font-weight: 700; color: rgba(255, 255, 255, 0.75); }
      .g-pair { display: flex; align-items: flex-end; justify-content: center; gap: 3px; height: 100%; }
      .g-pair i { display: block; width: 38%; min-height: 2px; border-radius: 5px 5px 0 0; }
      .g-in { background: #6fd08c; border: 1.5px solid #3fba68; }
      .g-out { background: #ee8585; border: 1.5px solid #e46262; }
      .g-ckeys { display: flex; justify-content: center; gap: 16px; margin: 10px 0 0; font-size: 14px; font-weight: 700; color: rgba(255, 255, 255, 0.8); }
      .g-ckeys span { display: inline-flex; align-items: center; gap: 6px; }
      .g-ckeys i { display: inline-block; width: 18px; height: 18px; border-radius: 50%; }
      @media (max-width: 1280px) { .g-charts { grid-template-columns: repeat(2, minmax(0, 1fr)); } .g-trend-card { grid-column: 1 / -1; } }
      @media (max-width: 760px) { .g-charts { grid-template-columns: 1fr; } .g-wide, .g-trend-card { grid-column: auto; } }
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

  /** The colour each kind of money keeps on every chart. */
  private static readonly KIND: Record<string, GColor> = {
    savings: 'green', contribution: 'purple', shares: 'blue', joining_fee: 'yellow', hire: 'teal', loan_repayment: 'red', welfare: 'violet', expense: 'gray',
    loan_disbursement: 'red', dividend: 'violet', opening_balance: 'gray',
  };

  private mix(): Row[] {
    return (this.d()?.['money']?.['mix'] as Row[] | undefined) ?? [];
  }

  /** The month's money in, kind by kind (the flower chart). */
  protected readonly mixIn = computed<GSlice[]>(() =>
    this.mix().filter((x) => this.n(x['in']) > 0).map((x) => ({ label: this.cat(x['category']), value: this.n(x['in']), color: GDashboardPage.KIND[x['category']] ?? 'gray', full: this.tsh(this.n(x['in'])) })),
  );

  /** The month's money out, kind by kind (written under the flower chart). */
  protected readonly mixOut = computed(() => this.mix().filter((x) => this.n(x['out']) > 0).map((x) => ({ label: this.cat(x['category']), value: this.n(x['out']) })));

  /** This month's contributions: what came in, and what is still to come. */
  protected readonly collection = computed<GSlice[]>(() => {
    const c: Row = this.d()?.['money']?.['contributions'] ?? {};
    const got = Math.min(this.n(c['collected']), this.n(c['expected']));
    const left = Math.max(0, this.n(c['expected']) - got);
    return [
      { label: this.i18n.t('g.ch.collected'), value: got, color: 'blue', full: this.tsh(got) },
      { label: this.i18n.t('g.ch.unpaid'), value: left, color: 'red', full: this.tsh(left) },
    ];
  });

  /** The loans now: what is on time, and what is late (arrears). */
  protected readonly loanSlices = computed<GSlice[]>(() => {
    const l: Row = this.d()?.['money']?.['loans'] ?? {};
    const owed = this.n(l['principal']) + this.n(l['interest']);
    const late = Math.min(this.n(l['arrears']), owed);
    return [
      { label: this.i18n.t('g.ch.on.time'), value: Math.max(0, owed - late), color: 'green', full: this.tsh(Math.max(0, owed - late)) },
      { label: this.i18n.t('g.loans.arrears'), value: late, color: 'red', full: this.tsh(late) },
    ];
  });

  /** The year so far: hire income, dividends, welfare paid and group spending. */
  protected readonly yearSlices = computed<GSlice[]>(() => {
    const y: Row = this.d()?.['money']?.['year'] ?? {};
    return ([['g.year.hire', 'hire_income', 'green'], ['g.year.dividends', 'dividends', 'purple'], ['g.year.welfare', 'welfare_paid', 'yellow'], ['g.year.spent', 'expenses', 'red']] as [string, string, GColor][])
      .map(([key, field, color]) => ({ label: this.i18n.t(key), value: Math.max(0, this.n(y[field])), color, full: this.tsh(this.n(y[field])) }));
  });

  /** What the year's hire brought in, less the welfare paid and the group's spending. */
  protected readonly yearNet = computed(() => {
    const y: Row = this.d()?.['money']?.['year'] ?? {};
    return this.n(y['hire_income']) - this.n(y['welfare_paid']) - this.n(y['expenses']);
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
