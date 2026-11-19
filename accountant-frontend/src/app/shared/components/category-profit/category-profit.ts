import { Component, computed, inject, input } from '@angular/core';

import { tsh } from '../../../core/format';
import { I18nService } from '../../../core/i18n.service';
import { ByCategoryData, CategoryBlock, CategoryItem, MonthlyReport, ProfitByCategory } from '../../../core/models';

/**
 * What each CATEGORY earned in the month, in one place: its goods and its services each with their items and a subtotal (a service's goods
 * used up are named under it), the category's total, and at the end the totals of all the goods, all the services and everything. The owner
 * reads profit; anyone else reads what each category sold. It follows the colour of the card it sits in.
 */
@Component({
  selector: 'app-category-profit',
  template: `
    @if (blocks().length) {
      <div class="cp" data-testid="cat-section">
        <p class="cp-eyebrow">{{ i18n.t('cat.eyebrow') }}</p>
        <h3 class="cp-title">{{ i18n.t(owner() ? 'cat.title' : 'cat.title.sales') }}</h3>
        @for (c of blocks(); track $index) {
          <details class="cp-block" [attr.data-testid]="'cat-' + (c.category ?? 'none')">
            <summary class="cp-sum">
              <span class="cp-name" [class.is-services]="!!c.services" [class.is-goods]="!!c.goods && !c.services" [attr.data-testid]="'cat-name-' + (c.category ?? 'none')">
                {{ c.category ?? i18n.t('cat.none') }}
                @if (c.services) { <em class="cp-tag is-services">{{ i18n.t('cat.services') }}</em> }
                @if (c.goods) { <em class="cp-tag is-goods">{{ i18n.t('cat.goods') }}</em> }
                <small>{{ i18n.t('cat.sales.of') }} {{ tsh(c.total.sales) }}</small>
              </span>
              <b [attr.data-testid]="'cat-total-' + (c.category ?? 'none')">{{ tsh(val(c.total)) }}</b>
            </summary>
            <div class="cp-body">
              @if (c.goods; as g) {
                <p class="cp-kind">{{ i18n.t('cat.goods') }}</p>
                @for (i of g.items; track i.name) {
                  <div class="cp-line"><span>{{ i.name }} ×{{ i.qty }}</span><b>{{ tsh(val(i)) }}</b></div>
                }
                <div class="cp-line cp-sub"><span>{{ i18n.t('cat.sub.goods') }}</span><b [attr.data-testid]="'cat-sub-goods-' + (c.category ?? 'none')">{{ tsh(val(g)) }}</b></div>
              }
              @if (c.services; as s) {
                <p class="cp-kind">{{ i18n.t('cat.services') }}</p>
                @for (i of s.items; track i.name) {
                  <div class="cp-line"><span>{{ i.name }} ×{{ i.qty }}</span><b>{{ tsh(val(i)) }}</b></div>
                  @if (owner()) {
                    <p class="cp-note" [attr.data-testid]="'cat-used-' + i.name">{{ i18n.t('cat.sold') }} {{ tsh(i.sales) }} − {{ i18n.t('cat.used') }} {{ tsh(i.cost) }}{{ materials(i) }}</p>
                  }
                }
                <div class="cp-line cp-sub"><span>{{ i18n.t('cat.sub.services') }}</span><b [attr.data-testid]="'cat-sub-services-' + (c.category ?? 'none')">{{ tsh(val(s)) }}</b></div>
              }
              @if (c.goods && c.services) {
                <div class="cp-line cp-sub"><span>{{ i18n.t('cat.total') }}</span><b>{{ tsh(val(c.total)) }}</b></div>
              }
            </div>
          </details>
        }
        @if (totals(); as t) {
          <div class="cp-totals">
            <div class="cp-line"><span>{{ i18n.t('cat.totals.goods') }}</span><b data-testid="cat-totals-goods">{{ tsh(val(t.goods)) }}</b></div>
            <div class="cp-line"><span>{{ i18n.t('cat.totals.services') }}</span><b data-testid="cat-totals-services">{{ tsh(val(t.services)) }}</b></div>
            <div class="cp-line cp-all"><span>{{ i18n.t('cat.totals.all') }}</span><b data-testid="cat-totals-all">{{ tsh(val(t.all)) }}</b></div>
          </div>
        }
      </div>
    }
  `,
  styles: [
    `
      :host { display: block; }
      .cp-eyebrow { font-size: 10px; font-weight: 900; letter-spacing: 0.1em; text-transform: uppercase; opacity: 0.6; }
      .cp-title { font-size: 16px; font-weight: 900; margin-bottom: 6px; }
      .cp-block { border-top: 1px solid rgba(127, 127, 127, 0.25); }
      .cp-sum { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 9px 0; cursor: pointer; list-style: none; }
      .cp-sum::-webkit-details-marker { display: none; }
      .cp-sum::before { content: '›'; margin-right: 6px; opacity: 0.6; transition: transform 0.15s; }
      .cp-block[open] > .cp-sum::before { transform: rotate(90deg); }
      .cp-name { flex: 1; min-width: 0; font-weight: 800; }
      .cp-name small { display: block; font-size: 11px; font-weight: 600; opacity: 0.65; color: inherit; }
      /* A category's heading takes the colour of what it sells: services in the title's blue, goods in amber, each with a small tag */
      .cp-name.is-services { color: #2e4dbd; }
      .cp-name.is-goods { color: #b45309; }
      .cp-tag { display: inline-block; margin-left: 8px; padding: 1px 8px; border-radius: 999px; font-size: 9.5px; font-style: normal; font-weight: 900;
        letter-spacing: 0.06em; text-transform: uppercase; vertical-align: 2px; }
      .cp-tag.is-services { color: #2e4dbd; background: rgba(59, 97, 226, 0.12); border: 1px solid rgba(59, 97, 226, 0.35); }
      .cp-tag.is-goods { color: #b45309; background: rgba(245, 158, 11, 0.14); border: 1px solid rgba(245, 158, 11, 0.4); }
      .cp-sum b { font-weight: 900; white-space: nowrap; }
      .cp-body { padding: 0 0 8px 14px; }
      .cp-kind { margin: 6px 0 2px; font-size: 10.5px; font-weight: 900; letter-spacing: 0.08em; text-transform: uppercase; color: #20b8ce; }
      .cp-line { display: flex; justify-content: space-between; gap: 12px; padding: 3px 0; font-size: 13.5px; }
      .cp-line b { white-space: nowrap; font-weight: 700; }
      .cp-sub { font-weight: 800; border-top: 1px dashed rgba(127, 127, 127, 0.3); margin-top: 2px; }
      .cp-sub b { font-weight: 900; }
      .cp-note { margin: -1px 0 4px 10px; font-size: 11.5px; opacity: 0.7; }
      .cp-totals { margin-top: 6px; padding-top: 8px; border-top: 1px solid rgba(127, 127, 127, 0.4); }
      .cp-all { font-size: 15px; font-weight: 900; }
      .cp-all b { font-weight: 900; }
    `,
  ],
})
export class CategoryProfitComponent {
  protected readonly i18n = inject(I18nService);
  protected readonly tsh = tsh;

  /** A month's report (the "This month" page and the dashboard)... */
  readonly report = input<MonthlyReport | null>(null);
  /** ...or the answer for any period (the Sales screen's "By category"). */
  readonly data = input<ByCategoryData | null>(null);

  private readonly source = computed<ProfitByCategory | null>(() => this.data() ?? this.report()?.profit_by_category ?? null);
  protected readonly owner = computed(() => (this.data() ? this.data()!.owner_figures : this.report()?.owner_figures) !== false);
  protected readonly blocks = computed<CategoryBlock[]>(() => this.source()?.categories ?? []);
  protected readonly totals = computed(() => this.source()?.totals ?? null);

  /** Profit for the owner; what was sold for anyone else (the server already leaves the profit at nothing for them). */
  protected val(x: { sales: number; profit: number }): number {
    return Number(this.owner() ? x.profit : x.sales) || 0;
  }

  /** ": Gel ×4 (TSH 6,000), ..." the goods a service used up, or nothing. */
  protected materials(i: CategoryItem): string {
    const list = i.materials ?? [];

    return list.length ? ': ' + list.map((m) => `${m.name} ×${m.qty} (${tsh(m.cost)})`).join(', ') : '';
  }
}
