import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, map } from 'rxjs';

import { environment } from '../../environments/environment';
import { Named, NamedKind, Product, ProductBody, ProductFilters, ProductPage, ServiceMaterial, StaffMember } from './products.models';

const API = environment.apiUrl;

const num = (v: unknown, fallback = 0): number => {
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : fallback;
};
const numOrNull = (v: unknown): number | null => (v === null || v === undefined || v === '' ? null : num(v));
const text = (v: unknown): string | null => (typeof v === 'string' && v !== '' ? v : null);

/** One product row from the server, with every number made a number and the service lists made lists. */
export function parseProduct(r: Record<string, unknown>): Product {
  const options = Array.isArray(r['price_options']) ? (r['price_options'] as Record<string, unknown>[]) : [];

  return {
    id: num(r['id']),
    name: String(r['name'] ?? ''),
    sku: String(r['sku'] ?? ''),
    barcode: text(r['barcode']),
    description: text(r['description']),
    category_id: numOrNull(r['category_id']),
    category_name: text(r['category_name']),
    brand_id: numOrNull(r['brand_id']),
    brand_name: text(r['brand_name']),
    unit: String(r['unit'] ?? 'pcs'),
    quantity: num(r['quantity']),
    min_stock: num(r['min_stock']),
    cost_price: num(r['cost_price']),
    selling_price: num(r['selling_price']),
    tax_percent: numOrNull(r['tax_percent']),
    status: r['status'] === 'inactive' ? 'inactive' : 'active',
    is_service: r['is_service'] === true || r['is_service'] === 1 || r['is_service'] === '1',
    duration_minutes: numOrNull(r['duration_minutes']),
    rebook_after_weeks: numOrNull(r['rebook_after_weeks']),
    commission_percent: numOrNull(r['commission_percent']),
    commission_fixed: numOrNull(r['commission_fixed']),
    package_sessions: numOrNull(r['package_sessions']),
    package_service_id: numOrNull(r['package_service_id']),
    package_valid_days: numOrNull(r['package_valid_days']),
    staff_ids: Array.isArray(r['staff_ids']) ? (r['staff_ids'] as unknown[]).map(String) : [],
    price_options: options.map((o) => ({ label: String(o['label'] ?? ''), price: num(o['price']) })),
  };
}

/** Goods, services, categories and brands: the same server routes the mobile app uses. The server decides who may add, change or delete. */
@Injectable({ providedIn: 'root' })
export class ProductsApi {
  private readonly http = inject(HttpClient);

  products(f: ProductFilters): Observable<ProductPage> {
    let params = new HttpParams().set('page', String(f.page));
    if (f.q.trim()) params = params.set('q', f.q.trim());
    if (f.status) params = params.set('status', f.status);
    if (f.kind) params = params.set('is_service', f.kind === 'services' ? '1' : '0');
    if (f.lowStock) params = params.set('low_stock', '1');
    if (f.categoryId) params = params.set('category_id', String(f.categoryId));

    return this.http.get<{ data: Record<string, unknown>[]; meta?: { current_page?: number; last_page?: number; total?: number } }>(`${API}/inventory/products`, { params }).pipe(
      map((r) => ({
        items: (r.data ?? []).map(parseProduct),
        page: r.meta?.current_page ?? 1,
        lastPage: r.meta?.last_page ?? 1,
        total: r.meta?.total ?? (r.data ?? []).length,
      })),
    );
  }

  createProduct(body: ProductBody): Observable<void> {
    return this.http.post(`${API}/inventory/products`, body).pipe(map(() => undefined));
  }

  updateProduct(id: number, body: ProductBody): Observable<void> {
    return this.http.put(`${API}/inventory/products/${id}`, body).pipe(map(() => undefined));
  }

  /** `force` archives (deactivates) a product that has sales history instead of deleting it. */
  deleteProduct(id: number, force = false): Observable<void> {
    return this.http.delete(`${API}/inventory/products/${id}`, { params: force ? { force: '1' } : {} }).pipe(map(() => undefined));
  }

  /** The people who work in this business: who may be named as doing a service. */
  staff(): Observable<StaffMember[]> {
    return this.http.get<{ data: StaffMember[] }>(`${API}/inventory/salon/staff`).pipe(map((r) => (r.data ?? []).map((s) => ({ id: String(s.id), name: s.name, role: s.role }))));
  }

  /** The goods a service uses up each time (owner or accountant only: the server refuses anyone else). */
  materials(serviceId: number): Observable<ServiceMaterial[]> {
    return this.http.get<{ data: ServiceMaterial[] }>(`${API}/inventory/salon/services/${serviceId}/materials`).pipe(
      map((r) => (r.data ?? []).map((m) => ({ material_product_id: num(m.material_product_id), name: String(m.name), quantity: num(m.quantity), in_stock: num(m.in_stock) }))),
    );
  }

  saveMaterials(serviceId: number, items: { material_product_id: number; quantity: number }[]): Observable<void> {
    return this.http.put(`${API}/inventory/salon/services/${serviceId}/materials`, { items }).pipe(map(() => undefined));
  }

  /** Goods (not services) by name, to pick what a service uses up. */
  findGoods(q: string): Observable<Product[]> {
    const params = new HttpParams().set('is_service', '0').set('status', 'active').set('q', q);

    return this.http.get<{ data: Record<string, unknown>[] }>(`${API}/inventory/products`, { params }).pipe(map((r) => (r.data ?? []).map(parseProduct)));
  }

  named(kind: NamedKind): Observable<Named[]> {
    return this.http.get<{ data: Record<string, unknown>[] }>(`${API}/inventory/${kind}`).pipe(
      map((r) => (r.data ?? []).map((n) => ({
        id: num(n['id']),
        name: String(n['name'] ?? ''),
        description: text(n['description']),
        status: (n['status'] === 'inactive' ? 'inactive' : 'active') as 'active' | 'inactive',
        products_count: num(n['products_count']),
      }))),
    );
  }

  saveNamed(kind: NamedKind, id: number | null, body: { name: string; description: string | null; status: 'active' | 'inactive' }): Observable<void> {
    const call = id === null ? this.http.post(`${API}/inventory/${kind}`, body) : this.http.put(`${API}/inventory/${kind}/${id}`, body);

    return call.pipe(map(() => undefined));
  }

  deleteNamed(kind: NamedKind, id: number): Observable<void> {
    return this.http.delete(`${API}/inventory/${kind}/${id}`).pipe(map(() => undefined));
  }
}
