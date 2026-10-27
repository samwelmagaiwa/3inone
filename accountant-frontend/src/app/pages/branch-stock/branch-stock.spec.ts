import { TestBed } from '@angular/core/testing';

import { environment } from '../../../environments/environment';
import { byTestId, configure, settle, text, type } from '../../testing';
import { BranchStockPage } from './branch-stock';

const API = environment.apiUrl;

const STOCK = {
  data: {
    branches: [{ id: 1, name: 'Kariakoo' }, { id: 2, name: 'Mbagala' }],
    products: [
      {
        id: 7, name: 'Soda', total: 50, unallocated: 30, over_allocated: false,
        branches: [{ branch_id: 1, name: 'Kariakoo', quantity: 15, min_quantity: 20, low: true }, { branch_id: 2, name: 'Mbagala', quantity: 5, min_quantity: null, low: false }],
      },
    ],
    low: 1,
  },
};

const MOVES = { data: [{ id: 1, product: 'Soda', from: null, to: 'Kariakoo', quantity: 15, by: 'Owner', at: '2026-11-20 09:00' }] };

async function open(stock = STOCK) {
  const h = configure({ permissions: ['inv_view_reports'] });
  const fixture = TestBed.createComponent(BranchStockPage);
  fixture.detectChanges();
  h.http.expectOne({ method: 'GET', url: `${API}/inventory/branch-stock` }).flush(stock);
  h.http.expectOne((r) => r.url === `${API}/inventory/branch-stock/transfers`).flush(MOVES);
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

const click = (el: HTMLElement, id: string) => (byTestId(el, id) as HTMLElement).click();

describe('goods by branch', () => {
  it('shows the whole stock, what is in the main store and what each branch holds, with a low flag and the moves so far', async () => {
    const { el } = await open();

    expect(text(byTestId(el, 'bs-row-7')!)).toContain('Soda');
    expect(text(byTestId(el, 'bs-main-7')!)).toBe('30');
    expect(text(byTestId(el, 'bs-cell-7-1')!)).toContain('15');
    expect(text(byTestId(el, 'bs-cell-7-1')!)).toContain('Low stock');
    expect(text(byTestId(el, 'bs-cell-7-2')!)).toBe('5');
    expect(text(byTestId(el, 'bs-low')!)).toContain('1 shelves');
    expect(text(el)).toContain('Main store → Kariakoo');
  });

  it('says to add branches first when there are none', async () => {
    const { el } = await open({ data: { branches: [], products: [], low: 0 } });

    expect(byTestId(el, 'bs-nobranches')).not.toBeNull();
  });

  it('moves goods from the main store to a branch', async () => {
    const { h, fixture, el } = await open();

    click(el, 'bs-move-7');
    await settle(fixture);
    const to = byTestId(el, 'bs-to') as HTMLSelectElement;
    to.value = '2';
    to.dispatchEvent(new Event('change', { bubbles: true }));
    type(el, '[data-testid="bs-qty"]', '10');
    await settle(fixture);
    click(el, 'bs-save');

    const req = h.http.expectOne({ method: 'POST', url: `${API}/inventory/branch-stock/transfer` });
    expect(req.request.body).toEqual({ product_id: 7, from_branch_id: null, to_branch_id: 2, quantity: 10 });
    req.flush({ message: 'Saved' });
    await settle(fixture);
    h.http.expectOne({ method: 'GET', url: `${API}/inventory/branch-stock` }).flush(STOCK);
    h.http.expectOne((r) => r.url === `${API}/inventory/branch-stock/transfers`).flush(MOVES);
  });

  it('checks the move before sending anything: a place, a number, and enough there', async () => {
    const { h, fixture, el } = await open();

    click(el, 'bs-move-7');
    await settle(fixture);
    click(el, 'bs-save');
    await settle(fixture);
    expect(text(byTestId(el, 'bs-error')!)).toContain('Choose where the goods go');

    const to = byTestId(el, 'bs-to') as HTMLSelectElement;
    to.value = '1';
    to.dispatchEvent(new Event('change', { bubbles: true }));
    await settle(fixture);
    click(el, 'bs-save');
    await settle(fixture);
    expect(text(byTestId(el, 'bs-error')!)).toContain('how many');

    type(el, '[data-testid="bs-qty"]', '99');
    await settle(fixture);
    click(el, 'bs-save');
    await settle(fixture);
    expect(text(byTestId(el, 'bs-error')!)).toContain('only 30 there');
    h.http.expectNone({ method: 'POST', url: `${API}/inventory/branch-stock/transfer` });
  });
});
