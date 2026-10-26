import { TestBed } from '@angular/core/testing';

import { environment } from '../../../environments/environment';
import { byTestId, configure, settle, text, type } from '../../testing';
import { ProductsPage } from './products';

const API = environment.apiUrl;
const LIST = `${API}/inventory/products`;

const product = (id: number, over: Record<string, unknown> = {}) => ({
  id, name: `Item ${id}`, sku: `SKU${id}`, barcode: null, description: null, category_id: 1, category_name: 'Drinks', brand_id: null, brand_name: null,
  unit: 'crate', quantity: 50, min_stock: 10, cost_price: '1000.00', selling_price: '1500.00', tax_percent: null, status: 'active', is_service: 0,
  duration_minutes: null, rebook_after_weeks: null, commission_percent: null, price_options: [], ...over,
});

const ROWS = [
  product(1, { name: 'Soda', quantity: 3, min_stock: 10 }),
  product(2, { name: 'Haircut', is_service: 1, duration_minutes: 45, selling_price: '5000.00', quantity: 0, min_stock: 0 }),
];

const SALES_OFFICER = ['inv_view_products', 'inv_create_products', 'inv_create_sales', 'inv_view_credit'];
const ACCOUNTANT = ['inv_view_products', 'inv_create_sales', 'inv_manage_sales', 'inv_view_reports', 'inv_view_expenses', 'inv_manage_expenses'];
const MANAGER = ['inv_view_products', 'inv_manage_products', 'inv_create_sales'];

async function open(permissions: string[], over: { service?: 'inventory' | 'salon'; rows?: unknown[]; meta?: object } = {}) {
  const h = configure({ permissions, services: [over.service ?? 'inventory'] });
  const fixture = TestBed.createComponent(ProductsPage);
  fixture.detectChanges();
  h.http.expectOne((r) => r.url === LIST && r.params.get('page') === '1').flush({ data: over.rows ?? ROWS, meta: over.meta ?? { current_page: 1, last_page: 1, total: (over.rows ?? ROWS).length } });
  h.http.expectOne(`${API}/inventory/categories`).flush({ data: [{ id: 1, name: 'Drinks', description: null, status: 'active', products_count: 2 }] });
  h.http.expectOne(`${API}/inventory/brands`).flush({ data: [{ id: 5, name: 'Coca', description: null, status: 'active', products_count: 1 }] });
  await settle(fixture);

  return { h, fixture, el: fixture.nativeElement as HTMLElement };
}

const click = (el: HTMLElement, id: string) => (byTestId(el, id) as HTMLElement).click();
const wait = (ms = 10) => new Promise((r) => setTimeout(r, ms));

describe('products and services', () => {
  it('lists what is sold with stock, unit and price, flags low stock, and shows a service with its time', async () => {
    const { el } = await open(SALES_OFFICER);

    const soda = text(byTestId(el, 'prod-row-1')!);
    expect(soda).toContain('Soda');
    expect(soda).toContain('3 crate');
    expect(soda).toContain('TSH 1,500');
    expect(byTestId(el, 'prod-low-1')).not.toBeNull();

    const cut = text(byTestId(el, 'prod-row-2')!);
    expect(cut).toContain('Haircut');
    expect(cut).toContain('Service · 45 min');
    expect(cut).toContain('TSH 5,000');
    expect(byTestId(el, 'prod-low-2')).toBeNull();
  });

  describe('who may do what, as on the mobile app', () => {
    it('a sales officer can add but not change or delete, and has no categories or brands tabs', async () => {
      const { el } = await open(SALES_OFFICER);

      expect(byTestId(el, 'prod-add')).not.toBeNull();
      expect(byTestId(el, 'prod-edit-1')).toBeNull();
      expect(byTestId(el, 'prod-del-1')).toBeNull();
      expect(byTestId(el, 'tab-categories')).toBeNull();
    });

    it('an accountant only reads: no add, change or delete', async () => {
      const { el } = await open(ACCOUNTANT);

      expect(text(el)).toContain('Soda');
      expect(byTestId(el, 'prod-add')).toBeNull();
      expect(byTestId(el, 'prod-edit-1')).toBeNull();
      expect(byTestId(el, 'prod-del-1')).toBeNull();
    });

    it('someone who manages the catalogue can add, change, delete and sees the tabs', async () => {
      const { el } = await open(MANAGER);

      expect(byTestId(el, 'prod-add')).not.toBeNull();
      expect(byTestId(el, 'prod-edit-1')).not.toBeNull();
      expect(byTestId(el, 'prod-del-1')).not.toBeNull();
      expect(byTestId(el, 'tab-categories')).not.toBeNull();
      expect(byTestId(el, 'tab-brands')).not.toBeNull();
    });
  });

  it('searching and filtering ask the server (from the first page)', async () => {
    const { h, fixture, el } = await open(MANAGER);

    type(el, '.filter-input', 'soda');
    await wait(350);
    h.http.expectOne((r) => r.url === LIST && r.params.get('q') === 'soda' && r.params.get('page') === '1').flush({ data: [ROWS[0]], meta: { current_page: 1, last_page: 1, total: 1 } });
    await settle(fixture);
    expect(text(el)).toContain('Soda');

    const low = byTestId(el, 'filter-low') as HTMLSelectElement;
    low.value = low.options[1].value;
    low.dispatchEvent(new Event('change', { bubbles: true }));
    await wait();
    h.http.expectOne((r) => r.url === LIST && r.params.get('low_stock') === '1').flush({ data: [], meta: { current_page: 1, last_page: 1, total: 0 } });
    await settle(fixture);
    expect(byTestId(el, 'prod-empty')).not.toBeNull();
  });

  it('pages through a long list', async () => {
    const { h, fixture, el } = await open(MANAGER, { meta: { current_page: 1, last_page: 3, total: 50 } });
    expect(text(byTestId(el, 'prod-page')!)).toBe('Page 1 of 3');

    click(el, 'prod-next');
    h.http.expectOne((r) => r.url === LIST && r.params.get('page') === '2').flush({ data: [ROWS[0]], meta: { current_page: 2, last_page: 3, total: 50 } });
    await settle(fixture);

    expect(text(byTestId(el, 'prod-page')!)).toBe('Page 2 of 3');
  });

  describe('adding', () => {
    it('asks for what is missing before sending anything', async () => {
      const { h, fixture, el } = await open(SALES_OFFICER);

      click(el, 'prod-add');
      await settle(fixture);
      click(el, 'prod-save');
      await settle(fixture);
      expect(text(byTestId(el, 'prod-error')!)).toContain('write the name');

      type(el, '[data-testid="prod-name"]', 'Water');
      click(el, 'prod-save');
      await settle(fixture);
      expect(text(byTestId(el, 'prod-error')!)).toContain('selling price');
      h.http.expectNone({ method: 'POST', url: LIST });
    });

    it('sends the product with its numbers as numbers, and shows the new list', async () => {
      const { h, fixture, el } = await open(SALES_OFFICER);

      click(el, 'prod-add');
      await settle(fixture);
      type(el, '[data-testid="prod-name"]', 'Water 1L');
      type(el, '[data-testid="prod-cost"]', '700');
      type(el, '[data-testid="prod-price"]', '1,000');
      type(el, '[data-testid="prod-qty"]', '24');
      type(el, '[data-testid="prod-min"]', '6');
      await settle(fixture);
      click(el, 'prod-save');

      const req = h.http.expectOne({ method: 'POST', url: LIST });
      expect(req.request.body).toMatchObject({ name: 'Water 1L', cost_price: 700, selling_price: 1000, quantity: 24, min_stock: 6, status: 'active', is_service: false, unit: 'pcs' });
      expect(req.request.body.sku).toBeUndefined();
      req.flush({ message: 'Product created', data: { id: 9 } });
      await settle(fixture);
      h.http.expectOne((r) => r.url === LIST && r.method === 'GET').flush({ data: ROWS, meta: { current_page: 1, last_page: 1, total: 2 } });
      await settle(fixture);

      expect(byTestId(el, 'prod-error')).toBeNull();
    });

    it('shows the server\'s own message when it refuses', async () => {
      const { h, fixture, el } = await open(SALES_OFFICER);

      click(el, 'prod-add');
      await settle(fixture);
      type(el, '[data-testid="prod-name"]', 'Water');
      type(el, '[data-testid="prod-price"]', '1000');
      await settle(fixture);
      click(el, 'prod-save');
      h.http.expectOne({ method: 'POST', url: LIST }).flush({ message: 'The sku has already been taken.' }, { status: 422, statusText: 'x' });
      await settle(fixture);

      expect(text(byTestId(el, 'prod-error')!)).toContain('already been taken');
    });
  });

  it('changing a product fills the form and saves with PUT', async () => {
    const { h, fixture, el } = await open(MANAGER);

    click(el, 'prod-edit-1');
    await settle(fixture);
    expect((byTestId(el, 'prod-name') as HTMLInputElement).value).toBe('Soda');
    expect((byTestId(el, 'prod-price') as HTMLInputElement).value).toBe('1500');
    type(el, '[data-testid="prod-price"]', '1800');
    await settle(fixture);
    click(el, 'prod-save');

    const req = h.http.expectOne({ method: 'PUT', url: `${LIST}/1` });
    expect(req.request.body).toMatchObject({ name: 'Soda', selling_price: 1800, sku: 'SKU1', category_id: 1 });
    req.flush({ message: 'Updated' });
    await settle(fixture);
    h.http.expectOne((r) => r.url === LIST && r.method === 'GET').flush({ data: ROWS, meta: { current_page: 1, last_page: 1, total: 2 } });
  });

  describe('deleting', () => {
    it('asks first, then deletes', async () => {
      const { h, fixture, el } = await open(MANAGER);

      click(el, 'prod-del-1');
      await settle(fixture);
      h.http.expectOne({ method: 'DELETE', url: `${LIST}/1` }).flush({ message: 'Product deleted' });
      await settle(fixture);
      h.http.expectOne((r) => r.url === LIST && r.method === 'GET').flush({ data: [ROWS[1]], meta: { current_page: 1, last_page: 1, total: 1 } });
    });

    it('a product with sales is offered "make inactive" instead, and only then archived', async () => {
      const { h, fixture, el } = await open(MANAGER);

      click(el, 'prod-del-1');
      await settle(fixture);
      h.http.expectOne({ method: 'DELETE', url: `${LIST}/1` }).flush({ message: 'Product has sales history. Pass ?force=1 to archive (deactivate) instead.' }, { status: 422, statusText: 'x' });
      await settle(fixture);

      const again = h.http.expectOne((r) => r.method === 'DELETE' && r.url === `${LIST}/1` && r.params.get('force') === '1');
      again.flush({ message: 'Product archived' });
      await settle(fixture);
      h.http.expectOne((r) => r.url === LIST && r.method === 'GET').flush({ data: ROWS, meta: { current_page: 1, last_page: 1, total: 2 } });
    });

    it('does nothing when the person says no', async () => {
      const { h, fixture, el } = await open(MANAGER);
      h.confirmAnswer.value = false;

      click(el, 'prod-del-1');
      await settle(fixture);

      h.http.expectNone({ method: 'DELETE', url: `${LIST}/1` });
    });
  });

  describe('a salon: services and goods', () => {
    it('shows the Services & goods wording and the type filter, and only a salon has them', async () => {
      const salon = await open(MANAGER, { service: 'salon' });
      expect(text(salon.el)).toContain('Services & goods');
      expect(byTestId(salon.el, 'filter-kind')).not.toBeNull();

      TestBed.resetTestingModule();
      const shop = await open(MANAGER);
      expect(byTestId(shop.el, 'filter-kind')).toBeNull();
      expect(byTestId(shop.el, 'prod-is-service')).toBeNull();
    });

    it('adds a service: no stock, a time, price options', async () => {
      const { h, fixture, el } = await open(MANAGER, { service: 'salon' });

      click(el, 'prod-add');
      await settle(fixture);
      const toggle = byTestId(el, 'prod-is-service') as HTMLInputElement;
      toggle.click();
      await settle(fixture);
      expect(byTestId(el, 'prod-qty')).toBeNull();

      type(el, '[data-testid="prod-name"]', 'Braids');
      type(el, '[data-testid="prod-price"]', '30000');
      type(el, '[data-testid="prod-duration"]', '120');
      click(el, 'prod-add-option');
      await settle(fixture);
      type(el, '[data-testid="opt-label-0"]', 'Short');
      type(el, '[data-testid="opt-price-0"]', '25000');
      await settle(fixture);
      click(el, 'prod-save');

      const req = h.http.expectOne({ method: 'POST', url: LIST });
      expect(req.request.body).toMatchObject({ name: 'Braids', is_service: true, selling_price: 30000, quantity: 0, min_stock: 0, duration_minutes: 120, price_options: [{ label: 'Short', price: 25000 }] });
      req.flush({ data: { id: 3 } });
      await settle(fixture);
      h.http.expectOne((r) => r.url === LIST && r.method === 'GET').flush({ data: ROWS, meta: { current_page: 1, last_page: 1, total: 2 } });
    });
  });

  describe('categories and brands', () => {
    it('are listed with how many products each holds, and a new one is saved', async () => {
      const { h, fixture, el } = await open(MANAGER);

      click(el, 'tab-categories');
      await settle(fixture);
      expect(text(byTestId(el, 'named-row-1')!)).toContain('Drinks');

      click(el, 'named-add');
      await settle(fixture);
      type(el, '[data-testid="named-name"]', 'Hair care');
      await settle(fixture);
      click(el, 'named-save');
      const req = h.http.expectOne({ method: 'POST', url: `${API}/inventory/categories` });
      expect(req.request.body).toEqual({ name: 'Hair care', description: null, status: 'active' });
      req.flush({ data: { id: 2 } });
      await settle(fixture);
      h.http.expectOne({ method: 'GET', url: `${API}/inventory/categories` }).flush({ data: [] });
    });

    it('brands are managed the same way', async () => {
      const { h, fixture, el } = await open(MANAGER);

      click(el, 'tab-brands');
      await settle(fixture);
      expect(text(byTestId(el, 'named-row-5')!)).toContain('Coca');

      click(el, 'named-del-5');
      await settle(fixture);
      h.http.expectOne({ method: 'DELETE', url: `${API}/inventory/brands/5` }).flush({ message: 'Deleted' });
      await settle(fixture);
      h.http.expectOne({ method: 'GET', url: `${API}/inventory/brands` }).flush({ data: [] });
    });
  });
});
