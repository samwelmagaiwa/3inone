import { TestBed } from '@angular/core/testing';
import { firstValueFrom } from 'rxjs';

import { environment } from '../../environments/environment';
import { configure } from '../testing';
import { ProductsApi } from './products-api.service';
import { alphabetical, byName } from './sort';
import { TillApi } from './till-api.service';

const LIST = `${environment.apiUrl}/inventory/products`;

const row = (id: number, name: string) => ({
  id, name, sku: `SKU${id}`, barcode: null, description: null, category_id: 1, category_name: 'Hair', brand_id: null, brand_name: null,
  unit: 'pcs', quantity: 5, min_stock: 1, cost_price: '100.00', selling_price: '500.00', tax_percent: null, status: 'active', is_service: 1,
  duration_minutes: 30, rebook_after_weeks: null, commission_percent: null, price_options: [], units: [],
});

describe('services and goods A to Z', () => {
  it('byName ignores capitals and stray spaces, and alphabetical keeps the older first for the same name', () => {
    expect(byName('Bangili', 'bangili')).toBe(0);
    expect(byName('  Cheni', 'bangili')).toBeGreaterThan(0);
    expect(byName('afro wig', 'Bangili')).toBeLessThan(0);
    const out = alphabetical([
      { id: 5, name: 'kucha' }, { id: 2, name: 'Bangili' }, { id: 7, name: '  Cheni' }, { id: 3, name: 'bangili' }, { id: 1, name: 'afro wig' }, { id: 9, name: 'Zeze' }, { id: 6, name: '027 sunflower' },
    ]);
    expect(out.map((p) => p.name.trim())).toEqual(['027 sunflower', 'afro wig', 'Bangili', 'bangili', 'Cheni', 'kucha', 'Zeze']);
    expect(out[2].id).toBe(2);
    expect(out[3].id).toBe(3);
  });

  it('the till reads EVERY page of the services and goods (100 to a page), asks for A to Z, and lists them A to Z', async () => {
    const h = configure({ services: ['salon'] });
    const api = TestBed.inject(TillApi);
    const done = firstValueFrom(api.products('', 1, { kind: 'service' }));

    const first = h.http.expectOne((r) => r.url === LIST && r.params.get('page') === '1');
    expect(first.request.params.get('per_page')).toBe('100');
    expect(first.request.params.get('sort')).toBe('name');
    expect(first.request.params.get('is_service')).toBe('1');
    first.flush({ data: [row(3, 'Rasta'), row(1, 'Braids')], meta: { current_page: 1, last_page: 3, total: 5 } });
    await Promise.resolve();
    h.http.expectOne((r) => r.url === LIST && r.params.get('page') === '2').flush({ data: [row(5, 'Facial')], meta: { current_page: 2, last_page: 3, total: 5 } });
    await Promise.resolve();
    h.http.expectOne((r) => r.url === LIST && r.params.get('page') === '3').flush({ data: [row(4, 'Afro cut'), row(2, 'Manicure')], meta: { current_page: 3, last_page: 3, total: 5 } });

    const r = await done;
    expect(r.items.map((p) => p.name)).toEqual(['Afro cut', 'Braids', 'Facial', 'Manicure', 'Rasta']);
    expect(r.items.length).toBe(5);
    h.http.verify();
  });

  it('one page is one request, and an older server that says nothing about pages still works', async () => {
    const h = configure({ services: ['salon'] });
    const api = TestBed.inject(TillApi);
    const done = firstValueFrom(api.products('braid', 1));
    const only = h.http.expectOne((r) => r.url === LIST);
    expect(only.request.params.get('q')).toBe('braid');
    only.flush({ data: [row(2, 'Zig zag'), row(1, 'Braids')] });
    expect((await done).items.map((p) => p.name)).toEqual(['Braids', 'Zig zag']);
    h.http.verify();
  });

  it('the products page asks for A to Z, 20 to a page, and shows what comes A to Z', async () => {
    const h = configure({ services: ['salon'] });
    const api = TestBed.inject(ProductsApi);
    const done = firstValueFrom(api.products({ q: '', status: '', kind: '', lowStock: false, categoryId: null, page: 2 }));
    const req = h.http.expectOne((r) => r.url === LIST);
    expect(req.request.params.get('sort')).toBe('name');
    expect(req.request.params.get('per_page')).toBe('20');
    expect(req.request.params.get('page')).toBe('2');
    req.flush({ data: [row(3, 'Rasta'), row(1, 'Braids'), row(2, 'afro cut')], meta: { current_page: 2, last_page: 4, total: 70 } });
    const page = await done;
    expect(page.items.map((p) => p.name)).toEqual(['afro cut', 'Braids', 'Rasta']);
    expect(page.page).toBe(2);
    expect(page.lastPage).toBe(4);
    expect(page.total).toBe(70);
    h.http.verify();
  });

  it('the goods a service uses up are found A to Z, and the categories and brands to choose from too', async () => {
    const h = configure({ services: ['salon'] });
    const api = TestBed.inject(ProductsApi);
    const goods = firstValueFrom(api.findGoods('oil'));
    const req = h.http.expectOne((r) => r.url === LIST);
    expect(req.request.params.get('sort')).toBe('name');
    expect(req.request.params.get('per_page')).toBe('100');
    req.flush({ data: [row(3, 'Shine oil'), row(1, 'Argan oil')] });
    expect((await goods).map((p) => p.name)).toEqual(['Argan oil', 'Shine oil']);

    const named = firstValueFrom(api.named('categories'));
    h.http.expectOne(`${environment.apiUrl}/inventory/categories`).flush({
      data: [{ id: 2, name: 'Wigi', status: 'active', products_count: 1 }, { id: 1, name: 'bidhaa za nywele', status: 'active', products_count: 2 }, { id: 3, name: 'Nywele', status: 'active', products_count: 0 }],
    });
    expect((await named).map((n) => n.name)).toEqual(['bidhaa za nywele', 'Nywele', 'Wigi']);
    h.http.verify();
  });
});
