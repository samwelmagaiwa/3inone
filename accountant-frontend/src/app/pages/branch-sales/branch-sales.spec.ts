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
      total: { sales_count: 2, sales: 3000, paid: 3000 },
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

    expect(text(byTestId(el, 'bsl-total')!)).toContain('3,000');
    expect(text(byTestId(el, 'bsl-branch-1')!)).toContain('Kariakoo');
    expect(text(byTestId(el, 'bsl-branch-1')!)).toContain('Asha');
    expect(text(byTestId(el, 'bsl-branch-1')!)).toContain('profit');
    expect(text(byTestId(el, 'bsl-staff-u1')!)).toContain('Kariakoo');
  });

  it('shows no profit when the server leaves it out', async () => {
    const { el } = await open(false);

    expect(text(byTestId(el, 'bsl-branch-1')!)).not.toContain('profit');
  });

  it('asks again for another period', async () => {
    const { h, fixture, el } = await open(true);

    (byTestId(el, 'bsl-period-week') as HTMLElement).click();
    h.http.expectOne((r) => r.url === `${API}/inventory/branch-sales`).flush(data(true));
    await settle(fixture);
  });
});
