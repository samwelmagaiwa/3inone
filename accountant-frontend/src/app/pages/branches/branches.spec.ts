import { TestBed } from '@angular/core/testing';

import { environment } from '../../../environments/environment';
import { BranchesService } from '../../core/branches.service';
import { byTestId, configure, settle, text, type } from '../../testing';
import { BranchesPage } from './branches';

const API = environment.apiUrl;
const LIST = `${API}/inventory/branches`;

const BRANCHES = [
  { id: 1, name: 'Kariakoo', address: 'Mtaa wa Kongo', phone: '0711222333', active: true },
  { id: 2, name: 'Mbagala', address: null, phone: null, active: false },
];

async function open(permissions: string[], rows: unknown[] = BRANCHES) {
  localStorage.clear();
  const h = configure({ permissions });
  const fixture = TestBed.createComponent(BranchesPage);
  fixture.detectChanges();
  h.http.expectOne({ method: 'GET', url: LIST }).flush({ data: rows });
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

const click = (el: HTMLElement, id: string) => (byTestId(el, id) as HTMLElement).click();

describe('branches', () => {
  it('lists the places the business sells from, and the whole business is always a choice', async () => {
    const { el } = await open(['inv_manage_settings']);

    expect(text(byTestId(el, 'br-row-1')!)).toContain('Kariakoo');
    expect(text(byTestId(el, 'br-row-1')!)).toContain('Mtaa wa Kongo');
    expect(text(byTestId(el, 'br-row-2')!)).toContain('Switched off');
    expect(byTestId(el, 'br-all-on')).not.toBeNull();
    expect(byTestId(el, 'br-look-2')).toBeNull();
  });

  it('whoever is not allowed to change settings can look at a branch but not add, change or delete', async () => {
    const { el } = await open(['inv_view_products']);

    expect(byTestId(el, 'br-look-1')).not.toBeNull();
    expect(byTestId(el, 'br-add')).toBeNull();
    expect(byTestId(el, 'br-edit-1')).toBeNull();
    expect(byTestId(el, 'br-del-1')).toBeNull();
  });

  it('choosing a branch to look at is remembered and asking for all goes back to the whole business', async () => {
    const { h, fixture, el } = await open(['inv_manage_settings']);
    const branches = TestBed.inject(BranchesService);

    click(el, 'br-look-1');
    await settle(fixture);
    expect(branches.selected()).toBe(1);
    expect(localStorage.getItem('accountant_branch_1_inventory')).toBe('1');
    expect(byTestId(el, 'br-on-1')).not.toBeNull();
    expect(h.http).toBeTruthy();

    click(el, 'br-look-all');
    await settle(fixture);
    expect(branches.selected()).toBeNull();
    expect(localStorage.getItem('accountant_branch_1_inventory')).toBeNull();
  });

  it('adds a branch, and the server\'s refusal of a repeated name is shown', async () => {
    const { h, fixture, el } = await open(['inv_manage_settings']);

    click(el, 'br-add');
    await settle(fixture);
    click(el, 'br-save');
    await settle(fixture);
    expect(text(byTestId(el, 'br-error')!)).toContain('write the branch name');

    type(el, '[data-testid="br-name"]', 'Kariakoo');
    type(el, '[data-testid="br-phone"]', '0711000000');
    await settle(fixture);
    click(el, 'br-save');
    h.http.expectOne({ method: 'POST', url: LIST }).flush({ message: 'That branch already exists.', errors: { name: ['That branch already exists.'] } }, { status: 422, statusText: 'x' });
    await settle(fixture);
    expect(text(byTestId(el, 'br-error')!)).toContain('already exists');

    type(el, '[data-testid="br-name"]', 'Temeke');
    await settle(fixture);
    click(el, 'br-save');
    const req = h.http.expectOne({ method: 'POST', url: LIST });
    expect(req.request.body).toEqual({ name: 'Temeke', address: null, phone: '0711000000' });
    req.flush({ message: 'Saved', data: { id: 3 } }, { status: 201, statusText: 'Created' });
    await settle(fixture);
    h.http.expectOne({ method: 'GET', url: LIST }).flush({ data: BRANCHES });
  });

  it('switches a branch off and on', async () => {
    const { h, fixture, el } = await open(['inv_manage_settings']);

    click(el, 'br-toggle-1');
    const req = h.http.expectOne({ method: 'PUT', url: `${LIST}/1` });
    expect(req.request.body).toMatchObject({ name: 'Kariakoo', active: false });
    req.flush({ message: 'Saved' });
    await settle(fixture);
    h.http.expectOne({ method: 'GET', url: LIST }).flush({ data: BRANCHES });
  });

  it('a branch chosen earlier that has been switched off is no longer chosen', async () => {
    localStorage.setItem('accountant_branch_1_inventory', '2');
    const h = configure({ permissions: ['inv_manage_settings'] });
    const branches = TestBed.inject(BranchesService);
    branches.select(2);
    const fixture = TestBed.createComponent(BranchesPage);
    fixture.detectChanges();
    h.http.expectOne({ method: 'GET', url: LIST }).flush({ data: BRANCHES });
    await settle(fixture);

    expect(branches.selected()).toBeNull();
  });

  it('says there are none yet, and that a business with one place needs none', async () => {
    const { el } = await open(['inv_manage_settings'], []);

    expect(text(byTestId(el, 'br-empty')!)).toContain('No branches yet');
  });
});
