import { TestBed } from '@angular/core/testing';

import { environment } from '../../../environments/environment';
import { byTestId, configure, settle, text } from '../../testing';
import { BranchSalesPage } from './branch-sales';

const API = environment.apiUrl;
const cell = (sales: number, profit: number | null) => ({ sales_count: 2, sales, paid: sales, profit });

function data(profit: boolean) {
  return {
    data: {
      from: '2026-11-01', to: '2026-11-30',
      by_branch: [{ branch_id: 1, name: 'Kariakoo', ...cell(3000, profit ? 1200 : null), staff: [{ staff_id: 'u1', name: 'Asha', ...cell(3000, profit ? 1200 : null) }] }],
      by_staff: [{ staff_id: 'u1', name: 'Asha', ...cell(3000, profit ? 1200 : null), branches: [{ branch_id: 1, name: 'Kariakoo', ...cell(3000, profit ? 1200 : null) }] }],
      total: { sales_count: 2, sales: 3000, paid: 3000, goods_sold: 2500, services_sold: 500, service_profit: profit ? 450 : null },
    },
  };
}

async function open(profit: boolean) {
  const h = configure({ permissions: ['inv_view_reports'] });
  const fixture = TestBed.createComponent(BranchSalesPage);
  fixture.detectChanges();
  h.http.expectOne((r) => r.url === `${API}/inventory/branch-sales`).flush(data(profit));
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

describe('sales by branch and by person', () => {
  it('shows the total, each branch with its people and each person with their branches, with profit', async () => {
    const { el } = await open(true);

    expect(text(byTestId(el, 'bsl-goods')!)).toContain('2,500');
    expect(text(byTestId(el, 'bsl-service-profit')!)).toContain('450');
    expect(text(byTestId(el, 'bsl-branch-b1')!)).toContain('Kariakoo');
    expect(text(byTestId(el, 'bsl-branch-b1')!)).toContain('profit');
    expect(text(byTestId(el, 'bsl-branch-b1-u1')!)).toContain('Asha'); // under its branch, in the same table
    expect(text(byTestId(el, 'bsl-branch-b1-u1')!)).toContain('profit');
  });

  it('shows no profit when the server leaves it out', async () => {
    const { el } = await open(false);

    expect(byTestId(el, 'bsl-service-profit')).toBeNull();
    expect(text(byTestId(el, 'bsl-goods')!)).toContain('2,500');
    expect(text(byTestId(el, 'bsl-branch-b1')!)).not.toContain('profit');
  });

  it('shows a bordered grid whose headers sort the rows, and no page title card', async () => {
    const { fixture, el } = await open(true);

    expect(el.querySelector('table.grid-table')).not.toBeNull();
    expect(el.querySelectorAll('section.section-card').length).toBe(1);
    expect(el.querySelectorAll('table.grid-table').length).toBe(1); // branches and people in one table
    expect(el.querySelector('.page-header-card')).toBeNull();
    const head = el.querySelector('table.grid-table th .grid-sort') as HTMLElement;
    head.click();
    await settle(fixture);
    expect(head.className).toContain('is-sorted');
    expect(text(head)).toContain('▲');
    head.click();
    await settle(fixture);
    expect(text(head)).toContain('▼');
  });

  it('can be read by person instead of by branch: each person with the branches they sold in', async () => {
    const { fixture, el } = await open(true);

    const pick = (v: string) => {
      const box = byTestId(el, 'bsl-group') as HTMLSelectElement;
      box.value = v;
      box.dispatchEvent(new Event('change'));
    };
    pick('staff');
    await settle(fixture);

    expect(el.querySelectorAll('table.grid-table').length).toBe(1);
    expect(text(byTestId(el, 'bsl-staff-u1')!)).toContain('Asha');
    expect(text(byTestId(el, 'bsl-staff-u1-b1')!)).toContain('Kariakoo');
    expect(text(el.querySelector('table.grid-table th .grid-sort') as HTMLElement)).toContain('Person');
    pick('branch');
    await settle(fixture);
    expect(byTestId(el, 'bsl-branch-b1')).not.toBeNull();
  });

  it('asks again for another period', async () => {
    const { h, fixture, el } = await open(true);

    (fixture.componentInstance as unknown as { choose(p: string): void }).choose('week');
    h.http.expectOne((r) => r.url === `${API}/inventory/branch-sales`).flush(data(true));
    await settle(fixture);
  });
});
