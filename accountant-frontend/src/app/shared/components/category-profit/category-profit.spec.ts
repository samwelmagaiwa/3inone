import { TestBed } from '@angular/core/testing';
import { describe, expect, it } from 'vitest';

import { byTestId, configure, settle, text } from '../../../testing';
import { MonthlyReport } from '../../../core/models';
import { CategoryProfitComponent } from './category-profit';

const part = (sales: number, cost: number, items: unknown[]) => ({ category: 'Nywele', qty: 5, sales, cost, profit: sales - cost, margin_percent: 80, items });

const report = (over: Partial<MonthlyReport> = {}): MonthlyReport =>
  ({
    owner_figures: true,
    profit_by_category: {
      categories: [
        {
          category: 'Nywele',
          goods: part(15000, 6000, [{ name: 'Shampoo', qty: 3, sales: 15000, cost: 6000, profit: 9000 }]),
          services: part(80000, 6000, [{ name: 'Knotless', qty: 2, sales: 80000, cost: 6000, profit: 74000, materials: [{ name: 'Gel ya nywele', qty: 4, cost: 6000 }] }]),
          total: { sales: 95000, cost: 12000, profit: 83000, margin_percent: 87.4 },
        },
        { category: null, goods: part(600, 300, [{ name: 'Mfuko', qty: 3, sales: 600, cost: 300, profit: 300 }]), services: null, total: { sales: 600, cost: 300, profit: 300, margin_percent: 50 } },
      ],
      totals: { goods: { sales: 15600, profit: 9300 }, services: { sales: 80000, profit: 74000 }, all: { sales: 95600, profit: 83300 } },
    },
    ...over,
  }) as unknown as MonthlyReport;

async function show(r: MonthlyReport | null, lang: 'en' | 'sw' = 'en') {
  const h = configure({});
  h.i18n.setLang(lang);
  const fixture = TestBed.createComponent(CategoryProfitComponent);
  fixture.componentRef.setInput('report', r);
  await settle(fixture);

  return { fixture, el: fixture.nativeElement as HTMLElement };
}

describe('profit by category (web)', () => {
  it('shows each category with its total, its goods and services with subtotals, the goods a service used, and the totals', async () => {
    const { el } = await show(report());

    expect(text(el.querySelector('.cp-title') as HTMLElement)).toBe('Profit by category');
    expect(text(byTestId(el, 'cat-total-Nywele')!)).toBe('TSH 83,000');
    expect(text(byTestId(el, 'cat-sub-goods-Nywele')!)).toBe('TSH 9,000');
    expect(text(byTestId(el, 'cat-sub-services-Nywele')!)).toBe('TSH 74,000');
    expect(text(byTestId(el, 'cat-used-Knotless')!)).toBe('Sold TSH 80,000 − goods used TSH 6,000: Gel ya nywele ×4 (TSH 6,000)');
    // a product with no category is listed apart, with its own name
    expect(text(byTestId(el, 'cat-none')!)).toContain('No category');
    expect(text(byTestId(el, 'cat-totals-goods')!)).toBe('TSH 9,300');
    expect(text(byTestId(el, 'cat-totals-services')!)).toBe('TSH 74,000');
    expect(text(byTestId(el, 'cat-totals-all')!)).toBe('TSH 83,300');
  });

  it('colours each heading by what it sells: services (blue/cyan) or goods only (amber), with a small tag', async () => {
    const { el } = await show(report());

    const mixed = byTestId(el, 'cat-name-Nywele')!;
    expect(mixed.classList.contains('is-services')).toBe(true);
    expect(Array.from(mixed.querySelectorAll('.cp-tag')).map((t) => text(t as HTMLElement))).toEqual(['Services', 'Goods']);

    const goodsOnly = byTestId(el, 'cat-name-none')!;
    expect(goodsOnly.classList.contains('is-goods')).toBe(true);
    expect(goodsOnly.classList.contains('is-services')).toBe(false);
    expect(Array.from(goodsOnly.querySelectorAll('.cp-tag')).map((t) => text(t as HTMLElement))).toEqual(['Goods']);
  });

  it('someone who may not see profit reads what each category sold, with no cost or goods used', async () => {
    const own = report();
    const stripped = { ...own, owner_figures: false } as MonthlyReport;
    const { el } = await show(stripped);

    expect(text(el.querySelector('.cp-title') as HTMLElement)).toBe('Sales by category');
    expect(text(byTestId(el, 'cat-total-Nywele')!)).toBe('TSH 95,000');
    expect(byTestId(el, 'cat-used-Knotless')).toBeNull();
    expect(text(byTestId(el, 'cat-totals-all')!)).toBe('TSH 95,600');
  });

  it('is told in Swahili', async () => {
    const { el } = await show(report(), 'sw');

    expect(text(el.querySelector('.cp-title') as HTMLElement)).toBe('Faida kwa kundi');
    expect(text(byTestId(el, 'cat-used-Knotless')!)).toContain('bidhaa zilizotumika');
    expect(el.textContent).toContain('Jumla ndogo ya huduma');
    expect(el.textContent).toContain('Jumla yote');
  });

  it('shows nothing when the server sends no categories (an older server, or a month with no sales)', async () => {
    const { el } = await show({ owner_figures: true } as MonthlyReport);

    expect(byTestId(el, 'cat-section')).toBeNull();
    expect(el.textContent?.trim()).toBe('');
  });
});
