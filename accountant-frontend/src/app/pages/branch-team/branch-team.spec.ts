import { TestBed } from '@angular/core/testing';

import { environment } from '../../../environments/environment';
import { byTestId, configure, settle, text } from '../../testing';
import { BranchTeamPage } from './branch-team';

const API = environment.apiUrl;
const TEAM = { data: [{ staff_id: 'u1', name: 'Asha Cashier', role: 'sales_officer', branch_id: null, branch: null }] };
const BRANCHES = { data: [{ id: 1, name: 'Kariakoo', address: null, phone: null, active: true }, { id: 2, name: 'Old', address: null, phone: null, active: false }] };

async function open(branches = BRANCHES) {
  const h = configure({ permissions: ['inv_manage_settings'] });
  const fixture = TestBed.createComponent(BranchTeamPage);
  fixture.detectChanges();
  h.http.expectOne({ method: 'GET', url: `${API}/inventory/branch-team` }).flush(TEAM);
  h.http.expectOne({ method: 'GET', url: `${API}/inventory/branches` }).flush(branches);
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

describe('staff by branch', () => {
  it('lists each person with the branches that are switched on, and places a person in one', async () => {
    const { h, fixture, el } = await open();

    expect(text(byTestId(el, 'bt-row-u1')!)).toContain('Asha Cashier');
    const select = byTestId(el, 'bt-select-u1') as HTMLSelectElement;
    expect(Array.from(select.options).map((o) => o.text.trim())).toEqual(['No branch', 'Kariakoo']);

    select.value = '1';
    select.dispatchEvent(new Event('change', { bubbles: true }));
    const req = h.http.expectOne({ method: 'PUT', url: `${API}/inventory/branch-team/u1` });
    expect(req.request.body).toEqual({ branch_id: 1 });
    req.flush({ message: 'Saved' });
    await settle(fixture);
    h.http.expectOne({ method: 'GET', url: `${API}/inventory/branch-team` }).flush(TEAM);
    h.http.expectOne({ method: 'GET', url: `${API}/inventory/branches` }).flush(BRANCHES);
  });

  it('says to add a branch first when there is none', async () => {
    const { el } = await open({ data: [] });

    expect(byTestId(el, 'bt-nobranches')).not.toBeNull();
  });
});
