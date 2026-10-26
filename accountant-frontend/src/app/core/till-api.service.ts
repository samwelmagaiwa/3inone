import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, map } from 'rxjs';

import { environment } from '../../environments/environment';
import { Customer, Product, parseCustomer, parseProduct } from './till.models';

const API = environment.apiUrl;

export interface SaleItemDetail {
  id: number;
  product_id: number;
  product_name: string;
  quantity: number;
  qty: number;
  unit_name: string | null;
  unit_price: number;
  total: number;
  tax_amount: number;
  is_service: boolean;
  staff_name: string | null;
}

/** One sale in full, as the server returns it (list rows carry the same fields). */
export interface SaleDetail {
  id: number;
  number: string;
  customer_id: number | null;
  customer_name: string | null;
  customer_phone: string | null;
  payment_status: 'paid' | 'debt' | 'partial';
  subtotal: number;
  discount: number;
  discount_reason: string | null;
  tax: number;
  total: number;
  paid_total: number;
  due_date: string | null;
  created_at: string;
  cancelled_at?: string | null;
  items: SaleItemDetail[];
  payments: { id: number; amount: number; method: string | null; reference: string | null; paid_at: string }[];
  salon_breakdown?: { services: unknown[]; goods: unknown[]; profit: number };
}

export interface ParkedSale {
  id: number;
  reference: string;
  customer_id: number | null;
  customer_name: string | null;
  total: number;
  note: string | null;
  parked_by_name: string | null;
  created_at: string;
}

export interface SaleReturn {
  id: number;
  reference: string;
  sale_id: number;
  sale_number: string;
  type: 'return' | 'cancellation';
  amount: number;
  reason: string | null;
  status: 'pending' | 'approved' | 'rejected';
  requested_by_name: string | null;
  created_at: string;
}

export interface CreditCheck {
  customer_id: number;
  balance: number;
  credit_limit: number;
  available: number | null;
  is_blocked: boolean;
  over_limit: boolean;
  near_limit: boolean;
  block_reason?: string | null;
}

export interface CrateType {
  id: number;
  name: string;
  deposit?: number;
  active?: boolean;
}

export interface StaffMember {
  id: string;
  name: string;
  role: string;
}

export interface UsualGood {
  product_id: number;
  name: string;
  quantity: number;
}

export interface ClientPackage {
  id: number;
  name: string;
  service_product_id: number;
  service_name: string;
  sessions_left: number;
  usable: boolean;
  expires_on: string | null;
}

/** The server calls of the till and of what can be done to a sale afterwards. The server decides who may do what. */
@Injectable({ providedIn: 'root' })
export class TillApi {
  private readonly http = inject(HttpClient);

  products(q: string, page = 1): Observable<{ items: Product[]; lastPage: number }> {
    let p = new HttpParams().set('page', page).set('with_units', '1').set('status', 'active');
    if (q.trim()) p = p.set('q', q.trim());
    return this.http
      .get<{ data: Record<string, unknown>[]; meta?: { last_page?: number } }>(`${API}/inventory/products`, { params: p })
      .pipe(map((r) => ({ items: (r.data ?? []).map(parseProduct), lastPage: r.meta?.last_page ?? 1 })));
  }

  customers(q: string): Observable<Customer[]> {
    let p = new HttpParams();
    if (q.trim()) p = p.set('q', q.trim());
    return this.http.get<{ data: Record<string, unknown>[] }>(`${API}/inventory/customers`, { params: p }).pipe(map((r) => (r.data ?? []).map(parseCustomer)));
  }

  createCustomer(name: string, phone: string): Observable<Customer> {
    return this.http.post<{ data: Record<string, unknown> }>(`${API}/inventory/customers`, { name, phone }).pipe(map((r) => parseCustomer(r.data)));
  }

  creditCheck(customerId: number, amount: number): Observable<CreditCheck> {
    return this.http.get<{ data: CreditCheck }>(`${API}/inventory/credit/customers/${customerId}/check`, { params: { amount } }).pipe(map((r) => r.data));
  }

  createSale(body: Record<string, unknown>): Observable<{ id: number; number: string }> {
    return this.http.post<{ data: { id: number; number: string } }>(`${API}/inventory/sales`, body).pipe(map((r) => r.data));
  }

  sale(id: number): Observable<SaleDetail> {
    return this.http.get<{ data: SaleDetail }>(`${API}/inventory/sales/${id}`).pipe(map((r) => r.data));
  }

  recordPayment(id: number, amount: number, method: string, reference?: string): Observable<{ balance: number; payment_status: string }> {
    return this.http
      .post<{ data: { balance: number; payment_status: string } }>(`${API}/inventory/sales/${id}/payments`, { amount, method, ...(reference ? { reference } : {}) })
      .pipe(map((r) => r.data));
  }

  cancelSale(id: number, reason: string): Observable<void> {
    return this.http.post(`${API}/inventory/sales/${id}/cancel`, { reason }).pipe(map(() => undefined));
  }

  // ---- parked sales
  parked(): Observable<ParkedSale[]> {
    return this.http.get<{ data: ParkedSale[] }>(`${API}/inventory/parked-sales`).pipe(map((r) => r.data ?? []));
  }

  park(cart: unknown[], total: number, customerId: number | null, note: string): Observable<void> {
    return this.http
      .post(`${API}/inventory/parked-sales`, { cart, total, ...(customerId ? { customer_id: customerId } : {}), ...(note.trim() ? { note: note.trim() } : {}) })
      .pipe(map(() => undefined));
  }

  resume(id: number): Observable<{ cart: unknown[]; customer_id: number | null }> {
    return this.http.post<{ data: { cart: unknown; customer_id: number | null } }>(`${API}/inventory/parked-sales/${id}/resume`, {}).pipe(
      map((r) => ({ cart: Array.isArray(r.data?.cart) ? (r.data.cart as unknown[]) : [], customer_id: r.data?.customer_id ?? null })),
    );
  }

  discard(id: number): Observable<void> {
    return this.http.delete(`${API}/inventory/parked-sales/${id}`).pipe(map(() => undefined));
  }

  // ---- returns
  returns(status?: string): Observable<SaleReturn[]> {
    let p = new HttpParams();
    if (status) p = p.set('status', status);
    return this.http.get<{ data: SaleReturn[] }>(`${API}/inventory/returns`, { params: p }).pipe(map((r) => r.data ?? []));
  }

  createReturn(body: { sale_id: number; type: 'return' | 'cancellation'; reason?: string; lines: { product_id: number; quantity: number; unit_price: number; restock: boolean; unit_id?: number | null }[] }): Observable<void> {
    return this.http.post(`${API}/inventory/returns`, body).pipe(map(() => undefined));
  }

  decideReturn(id: number, decision: 'approved' | 'rejected'): Observable<void> {
    return this.http.post(`${API}/inventory/returns/${id}/decide`, { decision }).pipe(map(() => undefined));
  }

  // ---- depot crates
  crateTypes(): Observable<CrateType[]> {
    return this.http.get<{ data: CrateType[] }>(`${API}/inventory/crate-types`).pipe(map((r) => r.data ?? []));
  }

  // ---- salon
  salonStaff(): Observable<StaffMember[]> {
    return this.http.get<{ data: StaffMember[] }>(`${API}/inventory/salon/staff`).pipe(map((r) => r.data ?? []));
  }

  usualGoods(serviceId: number): Observable<UsualGood[]> {
    return this.http.get<{ data: UsualGood[] }>(`${API}/inventory/salon/services/${serviceId}/usual-goods`).pipe(map((r) => r.data ?? []));
  }

  voucher(code: string, subtotal: number): Observable<{ discount: number; label: string }> {
    return this.http.get<{ data: { discount: number; label: string } }>(`${API}/inventory/salon/vouchers/check`, { params: { code, subtotal } }).pipe(map((r) => r.data));
  }

  clientPackages(customerId: number): Observable<ClientPackage[]> {
    return this.http.get<{ data: ClientPackage[] }>(`${API}/inventory/salon/clients/${customerId}/packages`).pipe(map((r) => r.data ?? []));
  }

  loyalty(customerId: number): Observable<{ on: boolean; balance: number; worth: number; per: number; value: number }> {
    return this.http.get<{ data: { on: boolean; balance: number; worth: number; per: number; value: number } }>(`${API}/inventory/salon/clients/${customerId}/loyalty`).pipe(map((r) => r.data));
  }

  loyaltySettings(): Observable<{ on: boolean; per: number; value: number }> {
    return this.http.get<{ data: { on: boolean; per: number; value: number } }>(`${API}/inventory/salon/loyalty/settings`).pipe(map((r) => r.data));
  }
}
