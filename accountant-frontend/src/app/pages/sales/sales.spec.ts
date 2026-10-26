import { TestBed } from '@angular/core/testing';

import { SaleRow } from '../../core/models';
import { byTestId, configure, settle, text, type } from '../../testing';
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

  it('a period button changes the dates asked for', async () => {
    const { h, fixture, el } = await open();

    byTestId(el, 'period-year')!.click();
    const list = h.http.expectOne((r) => r.url.endsWith('/inventory/sales') && r.params.get('from')?.endsWith('-01-01') === true);
    expect(list.request.params.get('to')).toMatch(/^\d{4}-\d{2}-\d{2}$/);
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
