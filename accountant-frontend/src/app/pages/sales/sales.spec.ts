import { TestBed } from '@angular/core/testing';

import { SaleRow } from '../../core/models';
import { byTestId, configure, mountSlot, settle, text, type } from '../../testing';
import { SalesPage } from './sales';

const sale = (over: Partial<SaleRow> = {}): SaleRow => ({
  id: 1, number: 'S-20261105-0001', total: 30000, paid_total: 30000, payment_status: 'paid', customer_name: 'Mama Neema', created_at: '2026-11-05 07:30:00',
  items: [{ product_name: 'Soda', qty: 3, total: 3000 }, { product_name: 'Sugar', qty: 1, total: 27000 }],
  payments: [{ amount: 30000, method: 'mpesa', paid_at: '2026-11-05 07:30:00' }], ...over,
});

async function open(who = {}, returns: unknown[] = [], rows: SaleRow[] = [sale(), sale({ id: 2, number: 'S-2', total: 10000, paid_total: 0, payment_status: 'debt', customer_name: null, items: [], payments: [] })]) {
  const h = configure(who);
  const fixture = TestBed.createComponent(SalesPage);
  fixture.detectChanges();
  h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && !r.url.includes('summary')).flush({ data: rows, meta: { current_page: 1, last_page: 1, per_page: 20, total: rows.length } });
  h.http.expectOne((r) => r.url.endsWith('/sales/summary')).flush({ data: { count: rows.length, total: 40000, paid: 30000, debt: 10000 } });
  h.http.match((r) => r.url.endsWith('/inventory/returns')).forEach((r) => r.flush({ data: returns }));
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

describe('sales', () => {
  it('starts with today and shows how many, how much, how much came in and how much is owed', async () => {
    const { el } = await open();

    expect(text(byTestId(el, 'sales-count')!)).toBe('2');
    expect(text(byTestId(el, 'sales-total')!)).toBe('TSH 40,000');
    expect(text(byTestId(el, 'sales-paid')!)).toBe('TSH 30,000');
    expect(text(byTestId(el, 'sales-debt')!)).toBe('TSH 10,000');
  });

  it('lists each sale with its customer (or "walk-in"), what was in it, and its state', async () => {
    const { el } = await open();

    const first = text(byTestId(el, 'sale-row-1')!);
    expect(first).toContain('S-20261105-0001');
    expect(first).toContain('Mama Neema');
    expect(first).toContain('Soda ×3, Sugar ×1');
    expect(first).toContain('Paid');
    const second = text(byTestId(el, 'sale-row-2')!);
    expect(second).toContain('Walk-in customer');
    expect(second).toContain('On credit');
  });

  it('shows "Showing 1-2 of 2" above a bordered grid, and a header sorts the sales on the page', async () => {
    const { fixture, el } = await open();

    expect(text(byTestId(el, 'list-showing')!)).toBe('Showing 1–2 of 2');
    expect(el.querySelector('table.grid-table')).not.toBeNull();
    const totalHead = Array.from(el.querySelectorAll('.grid-sort')).find((b) => text(b as HTMLElement).startsWith('Total')) as HTMLElement;
    totalHead.click();
    totalHead.click(); // descending: the biggest sale first
    await settle(fixture);
    const rows = Array.from(el.querySelectorAll('[data-testid^="sale-row-"]')).map((r) => r.getAttribute('data-testid'));
    expect(rows).toEqual(['sale-row-1', 'sale-row-2']);
    totalHead.click(); // ascending: the smallest first
    await settle(fixture);
    expect(Array.from(el.querySelectorAll('[data-testid^="sale-row-"]')).map((r) => r.getAttribute('data-testid'))).toEqual(['sale-row-2', 'sale-row-1']);
  });

  it('clicking a sale opens what was sold and how it was paid', async () => {
    const { fixture, el } = await open();

    byTestId(el, 'sale-row-1')!.click();
    await settle(fixture);

    expect(el.querySelector('.sale-detail')).not.toBeNull();
    expect(text(el.querySelector('.sale-detail') as HTMLElement)).toContain('Sugar ×1');
    expect(text(el.querySelector('.sale-detail') as HTMLElement)).toContain('M-Pesa');
    byTestId(el, 'sale-row-1')!.click();
    await settle(fixture);
    expect(el.querySelector('.sale-detail')).toBeNull();
  });

  it('a status button asks the server for just those sales, in the list and in the totals', async () => {
    const { h, fixture, el } = await open();

    byTestId(el, 'status-debt')!.click();
    const list = h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && r.params.get('status') === 'debt');
    h.http.expectOne((r) => r.url.endsWith('/sales/summary') && r.params.get('status') === 'debt').flush({ data: { count: 1, total: 10000, paid: 0, debt: 10000 } });
    list.flush({ data: [sale({ id: 2, payment_status: 'debt', paid_total: 0 })], meta: { total: 1 } });
    await settle(fixture);

    expect(byTestId(el, 'sale-row-1')).toBeNull();
    expect(byTestId(el, 'sale-row-2')).not.toBeNull();
  });

  it('the date picker changes the day asked for (today to begin with)', async () => {
    const { h, fixture, el } = await open();
    const input = byTestId(el, 'sales-date') as HTMLInputElement;
    expect(input.value).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(byTestId(el, 'period-today')).toBeNull(); // no week, month or year buttons any more

    input.value = '2026-10-15';
    input.dispatchEvent(new Event('change', { bubbles: true }));
    const list = h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && r.params.get('from') === '2026-10-15');
    expect(list.request.params.get('to')).toBe('2026-10-15');
    list.flush({ data: [], meta: { total: 0 } });
    h.http.expectOne((r) => r.url.endsWith('/sales/summary')).flush({ data: { count: 0, total: 0, paid: 0, debt: 0 } });
    await settle(fixture);
    expect(text(byTestId(el, 'sales-empty')!)).toContain('No sales in this period.');
  });

  it('searching waits for a pause in typing, then asks the server once', async () => {
    vi.useFakeTimers();
    try {
      const { h, el } = await open();
      type(el, 'input[type=text]', 'ne');
      type(el, 'input[type=text]', 'neema');
      h.http.expectNone((r) => r.params.get('q') === 'neema');

      vi.advanceTimersByTime(400);
      const list = h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && r.params.get('q') === 'neema');
      h.http.expectOne((r) => r.url.endsWith('/sales/summary')).flush({ data: { count: 0, total: 0, paid: 0, debt: 0 } });
      list.flush({ data: [], meta: { total: 0 } });
    } finally {
      vi.useRealTimers();
    }
  });

  it('a cancelled sale is shown as cancelled', async () => {
    const { el } = await open({}, [], [sale({ cancelled_at: '2026-11-05 09:00:00' })]);
    expect(text(byTestId(el, 'sale-row-1')!)).toContain('Cancelled');
  });

  it('a failed load offers to try again', async () => {
    const h = configure({});
    const fixture = TestBed.createComponent(SalesPage);
    fixture.detectChanges();
    h.http.match(() => true).forEach((r) => r.flush({ message: 'Server busy' }, { status: 500, statusText: 'Error' }));
    await settle(fixture);
    expect((fixture.nativeElement as HTMLElement).querySelector('[role=alert]')?.textContent).toContain('Server busy');
  });
});

describe('sales by category', () => {
  const answer = {
    from: '2026-11-01', to: '2026-11-30', owner_figures: true,
    categories: [{
      category: 'Nywele', goods: null,
      services: { category: 'Nywele', qty: 2, sales: 80000, cost: 6000, profit: 74000, margin_percent: 92, items: [{ name: 'Knotless', qty: 2, sales: 80000, cost: 6000, profit: 74000, materials: [{ name: 'Gel', qty: 4, cost: 6000 }] }] },
      total: { sales: 80000, cost: 6000, profit: 74000, margin_percent: 92 },
    }],
    totals: { goods: { sales: 0, profit: 0 }, services: { sales: 80000, profit: 74000 }, all: { sales: 80000, profit: 74000 } },
  };

  it('has the two views for someone who may read reports', async () => {
    const { el } = await open({});
    expect(byTestId(el, 'sales-views')).not.toBeNull();
  });

  it('has no "By category" for someone who may not read reports (they would see what each category earned)', async () => {
    const { el } = await open({ permissions: ['inv_create_sales', 'inv_manage_sales'] });
    expect(byTestId(el, 'sales-views')).toBeNull();
  });

  it('opens on this month, asks the server for those days, and shows each category with what it sold and earned', async () => {
    const { h, fixture, el } = await open({});
    byTestId(el, 'view-category')!.click();
    await settle(fixture);

    const ask = h.http.expectOne((r) => r.url.endsWith('/inventory/sales/by-category'));
    const first = new Date();
    const pad = (n: number) => String(n).padStart(2, '0');
    expect(ask.request.params.get('from')).toBe(`${first.getFullYear()}-${pad(first.getMonth() + 1)}-01`);
    ask.flush({ data: answer });
    await settle(fixture);

    expect(byTestId(el, 'sales-categories')).not.toBeNull();
    expect(text(byTestId(el, 'cat-total-Nywele')!)).toBe('TSH 74,000');
    expect(text(byTestId(el, 'cat-totals-all')!)).toBe('TSH 74,000');
    expect(byTestId(el, 'sale-row-1')).toBeNull(); // the list of sales is put away while the categories are read
  });

  it('a date written by hand asks again for those days, and a quick pick fills the dates in', async () => {
    const { h, fixture, el } = await open({});
    byTestId(el, 'view-category')!.click();
    await settle(fixture);
    h.http.expectOne((r) => r.url.endsWith('/inventory/sales/by-category')).flush({ data: answer });
    await settle(fixture);

    type(el, '[data-testid=cat-from]', '2026-10-01');
    type(el, '[data-testid=cat-to]', '2026-10-31');
    await settle(fixture);
    const asked = h.http.match((r) => r.url.endsWith('/inventory/sales/by-category'));
    expect(asked[asked.length - 1].request.params.get('from')).toBe('2026-10-01');
    expect(asked[asked.length - 1].request.params.get('to')).toBe('2026-10-31');
    asked.forEach((r) => r.flush({ data: answer }));

    const quick = byTestId(el, 'cat-quick') as HTMLSelectElement;
    quick.value = 'today';
    quick.dispatchEvent(new Event('change', { bubbles: true }));
    await settle(fixture);
    expect((byTestId(el, 'cat-from') as HTMLInputElement).value).toBe((byTestId(el, 'cat-to') as HTMLInputElement).value);
    h.http.match((r) => r.url.endsWith('/inventory/sales/by-category')).forEach((r) => r.flush({ data: answer }));
  });

  it('says plainly when nothing was sold in the period', async () => {
    const { h, fixture, el } = await open({});
    byTestId(el, 'view-category')!.click();
    await settle(fixture);

    h.http.expectOne((r) => r.url.endsWith('/inventory/sales/by-category')).flush({ data: { from: 'a', to: 'b', owner_figures: true, categories: [], totals: { goods: { sales: 0, profit: 0 }, services: { sales: 0, profit: 0 }, all: { sales: 0, profit: 0 } } } });
    await settle(fixture);

    expect(text(byTestId(el, 'cat-empty')!)).toBe('Nothing was sold in this period.');
  });

  it('goes back to the list of sales', async () => {
    const { h, fixture, el } = await open({});
    byTestId(el, 'view-category')!.click();
    await settle(fixture);
    h.http.expectOne((r) => r.url.endsWith('/inventory/sales/by-category')).flush({ data: answer });
    await settle(fixture);

    byTestId(el, 'view-list')!.click();
    await settle(fixture);

    expect(byTestId(el, 'sale-row-1')).not.toBeNull();
    expect(byTestId(el, 'sales-categories')).toBeNull();
  });
});
