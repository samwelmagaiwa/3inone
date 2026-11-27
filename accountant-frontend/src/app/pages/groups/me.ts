import { Component, OnInit, computed, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { Row } from '../../core/groups/groups-api.service';
import { GBase } from './g-base';

/**
 * My account: the signed-in person's own membership, as the phone's Home shows it to a member: who they are in the group, what they
 * hold (savings, shares, fees paid), what they owe and by when, their payments (waiting, verified or turned down) and their loans.
 * Everyone with a member record has it; with ME on it is the whole menu, exactly what an ordinary member sees.
 */
@Component({
  selector: 'app-g-me',
  imports: [FormsModule],
  template: `
    <div class="ad ph-page" data-testid="g-me">
      <div class="g-toolbar">
        <div class="ph-chips g-seg">
          <button type="button" class="pill-tab" [class.is-active]="tab() === 'payments'" (click)="tab.set('payments')" data-testid="g-me-tab-payments">{{ i18n.t('g.me.payments') }}</button>
          <button type="button" class="pill-tab" [class.is-active]="tab() === 'owing'" (click)="tab.set('owing')" data-testid="g-me-tab-owing">{{ i18n.t('g.me.owing') }}</button>
          <button type="button" class="pill-tab" [class.is-active]="tab() === 'loans'" (click)="tab.set('loans')" data-testid="g-me-tab-loans">{{ i18n.t('g.me.loans') }}</button>
        </div>
        <input class="g-search" [ngModel]="find()" (ngModelChange)="find.set($event)" [placeholder]="i18n.t('g.find.ph')" [attr.aria-label]="i18n.t('g.search')" />
        <button type="button" class="btn-outline ph-btn" (click)="load()">{{ i18n.t('ad.apply') }}</button>
        <span class="g-count">{{ i18n.t('g.count', shownCount()) }}</span>
      </div>

      @if (member(); as m) {
        <div class="ph-tiles" data-testid="g-me-tiles">
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.name') }}</span><b>{{ m['full_name'] }}</b></div>
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.number') }}</span><b>{{ m['member_number'] || m['application_ref'] || '—' }}</b></div>
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.status') }}</span><b [class]="tone(m['status'])">{{ status(m['status']) }}</b></div>
          <div class="ph-tile" data-testid="g-me-account"><span class="ph-muted">{{ i18n.t('g.me.account') }}</span><b class="ph-accent">{{ tsh(account()) }}</b></div>
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.savings') }}</span><b>{{ tsh(n(balances()['savings'])) }}</b></div>
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.shares') }}</span><b>{{ tsh(n(balances()['shares'])) }}</b></div>
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.cat.joining_fee') }}</span><b>{{ tsh(n(balances()['joining_fee'])) }}</b></div>
          <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.me.owe') }}</span><b [class.ph-bad]="owedTotal() > 0">{{ tsh(owedTotal()) }}</b></div>
          @if (n(ctx.me()?.['pending']) > 0) { <div class="ph-tile"><span class="ph-muted">{{ i18n.t('g.pending') }}</span><b class="ph-warn">{{ n(ctx.me()?.['pending']) }}</b></div> }
        </div>
      } @else {
        <section class="ph-card"><p class="ph-muted">{{ i18n.t('g.me.none') }}</p></section>
      }

      @if (error()) { <section class="ph-card"><p>{{ error() }}</p></section> }

      @switch (tab()) {
        @case ('payments') {
          <div class="table-scroll-container fit-page" data-testid="g-me-payments">
            <table class="grid-table">
              <thead><tr>
                <th class="no-col">#</th><th>{{ i18n.t('g.paid.on') }}</th><th>{{ i18n.t('g.kind') }}</th><th>{{ i18n.t('g.p.for') }}</th><th>{{ i18n.t('g.method') }}</th>
                <th>{{ i18n.t('g.ref') }}</th><th class="text-right">{{ i18n.t('g.amount') }}</th><th>{{ i18n.t('g.status') }}</th><th>{{ i18n.t('g.receipt') }}</th><th>{{ i18n.t('g.note') }}</th>
              </tr></thead>
              <tbody>
                @for (t of filtered(payments(), paymentKeys); track t['id']) {
                  <tr>
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td>{{ day(t['paid_on']) }}</td>
                    <td class="font-bold">{{ cat(t['category']) }}</td>
                    <td>{{ t['obligation_label'] || '—' }}</td>
                    <td>{{ method(t['method']) }}</td>
                    <td>{{ t['external_ref'] || '—' }}</td>
                    <td class="text-right"><b [class.ph-good]="t['direction'] === 'in'" [class.ph-bad]="t['direction'] === 'out'">{{ t['direction'] === 'out' ? '-' : '+' }}{{ tsh(t['amount']) }}</b></td>
                    <td><span class="ph-badge" [class]="t['reversed_by_id'] ? 'ph-bad' : tone(t['status'])">{{ t['reversed_by_id'] ? status('reversed') : status(t['status']) }}</span></td>
                    <td>{{ t['receipt_number'] || '—' }}</td>
                    <td>{{ t['reject_reason'] || t['note'] || '—' }}</td>
                  </tr>
                } @empty {
                  <tr><td colspan="10" class="ph-muted">{{ i18n.t('g.p.empty') }}</td></tr>
                }
              </tbody>
            </table>
          </div>
        }
        @case ('owing') {
          <div class="table-scroll-container fit-page" data-testid="g-me-owing">
            <table class="grid-table">
              <thead><tr>
                <th class="no-col">#</th><th>{{ i18n.t('g.c.type') }}</th><th>{{ i18n.t('g.c.due.date') }}</th><th class="text-right">{{ i18n.t('g.c.amount.due') }}</th>
                <th class="text-right">{{ i18n.t('g.paid') }}</th><th class="text-right">{{ i18n.t('g.l.left') }}</th><th>{{ i18n.t('g.status') }}</th>
              </tr></thead>
              <tbody>
                @for (o of filtered(owing(), owingKeys); track o['id']) {
                  <tr>
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td class="font-bold">{{ o['label'] || o['type_name'] }}</td>
                    <td>{{ day(o['due_date']) }}</td>
                    <td class="text-right">{{ tsh(n(o['amount_due'])) }}</td>
                    <td class="text-right">{{ tsh(n(o['paid'])) }}</td>
                    <td class="text-right"><b [class.ph-bad]="n(o['remaining']) > 0">{{ tsh(n(o['remaining'])) }}</b></td>
                    <td><span class="ph-badge" [class]="tone(o['state'])">{{ status(o['state']) }}</span></td>
                  </tr>
                } @empty {
                  <tr><td colspan="7" class="ph-muted">{{ i18n.t('g.p.nothing.owed') }}</td></tr>
                }
              </tbody>
            </table>
          </div>
        }
        @case ('loans') {
          <div class="table-scroll-container fit-page" data-testid="g-me-loans">
            <table class="grid-table">
              <thead><tr>
                <th class="no-col">#</th><th>{{ i18n.t('g.reference') }}</th><th>{{ i18n.t('g.l.purpose') }}</th><th class="text-right">{{ i18n.t('g.amount') }}</th>
                <th>{{ i18n.t('g.l.months') }}</th><th class="text-right">{{ i18n.t('g.l.owed') }}</th><th class="text-right">{{ i18n.t('g.loans.arrears') }}</th><th>{{ i18n.t('g.status') }}</th>
              </tr></thead>
              <tbody>
                @for (l of filtered(loans(), loanKeys); track l['id']) {
                  <tr>
                    <td class="no-col">{{ $index + 1 }}</td>
                    <td>{{ l['reference'] }}</td>
                    <td class="font-bold">{{ l['purpose'] }}</td>
                    <td class="text-right">{{ tsh(n(l['amount_approved'], n(l['amount_requested']))) }}</td>
                    <td>{{ l['term_months'] }}</td>
                    <td class="text-right">{{ l['outstanding'] === null || l['outstanding'] === undefined ? '—' : tsh(n(l['outstanding'])) }}</td>
                    <td class="text-right"><span [class.ph-bad]="n(l['arrears']) > 0">{{ n(l['arrears']) ? tsh(n(l['arrears'])) : '—' }}</span></td>
                    <td><span class="ph-badge" [class]="tone(l['state'] === 'overdue' ? 'overdue' : l['status'])">{{ l['state'] === 'overdue' ? status('overdue') : status(l['status']) }}</span></td>
                  </tr>
                } @empty {
                  <tr><td colspan="8" class="ph-muted">{{ i18n.t('g.l.none') }}</td></tr>
                }
              </tbody>
            </table>
          </div>
        }
      }
    </div>
  `,
})
export class GMePage extends GBase implements OnInit {
  protected readonly tab = signal<'payments' | 'owing' | 'loans'>('payments');
  protected readonly payments = signal<Row[]>([]);
  protected readonly loans = signal<Row[]>([]);
  protected readonly error = signal('');
  protected readonly paymentKeys = ['category', 'obligation_label', 'external_ref', 'receipt_number', 'reference', 'status'];
  protected readonly owingKeys = ['label', 'type_name', 'state'];
  protected readonly loanKeys = ['reference', 'purpose', 'status'];

  protected readonly member = computed<Row | null>(() => this.ctx.me()?.['member'] ?? null);
  protected readonly balances = computed<Row>(() => this.ctx.me()?.['balances'] ?? {});
  protected readonly owing = computed<Row[]>(() => this.ctx.me()?.['owing'] ?? []);
  /** What the group holds for them: savings and shares (fees and contributions are paid to the group, not held). */
  protected readonly account = computed(() => this.n(this.balances()['savings']) + this.n(this.balances()['shares']));
  protected readonly owedTotal = computed(() => this.owing().reduce((a, o) => a + this.n(o['remaining']), 0));

  ngOnInit(): void {
    void this.load();
  }

  protected shownCount(): number {
    switch (this.tab()) {
      case 'owing': return this.filtered(this.owing(), this.owingKeys).length;
      case 'loans': return this.filtered(this.loans(), this.loanKeys).length;
      default: return this.filtered(this.payments(), this.paymentKeys).length;
    }
  }

  async load(): Promise<void> {
    this.error.set('');
    await this.ctx.reload();
    if (!this.member()) return;
    try {
      const [t, l] = await Promise.all([this.api.get('/me/transactions'), this.api.get('/me/loans')]);
      this.payments.set((t['transactions'] as Row[]) ?? []);
      this.loans.set((l['loans'] as Row[]) ?? []);
    } catch (e) {
      this.error.set(this.failed(e));
    }
  }
}
