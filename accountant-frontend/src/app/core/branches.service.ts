import { Injectable, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, map } from 'rxjs';

import { environment } from '../../environments/environment';

const API = environment.apiUrl;
const KEY = 'accountant_branch';

/** A branch (a place the business sells from). */
export interface Branch {
  id: number;
  name: string;
  address: string | null;
  phone: string | null;
  active: boolean;
}

export interface BranchShelf {
  branch_id: number;
  name: string;
  quantity: number;
  min_quantity: number | null;
  low: boolean;
}

export interface BranchStockRow {
  id: number;
  name: string;
  total: number;
  unallocated: number;
  over_allocated: boolean;
  branches: BranchShelf[];
}

export interface BranchStock {
  branches: { id: number; name: string }[];
  products: BranchStockRow[];
  low: number;
}

export interface BranchTransfer {
  id: number;
  product: string;
  from: string | null;
  to: string | null;
  quantity: number;
  by: string;
  at: string;
}

export interface BranchTeamMember {
  staff_id: string;
  name: string;
  role: string;
  branch_id: number | null;
  branch: string | null;
}

export interface SalesCell {
  sales_count: number;
  sales: number;
  paid: number;
  /** null when the server does not let this person see profit. */
  profit: number | null;
}

export interface BranchSales {
  from: string;
  to: string;
  by_branch: (SalesCell & { branch_id: number | null; name: string | null; staff: (SalesCell & { staff_id: string; name: string })[] })[];
  by_staff: (SalesCell & { staff_id: string; name: string; branches: (SalesCell & { branch_id: number | null; name: string | null })[] })[];
  total: { sales_count: number; sales: number; paid: number };
}

function read(): number | null {
  try {
    const v = localStorage.getItem(KEY);
    return v && /^\d+$/.test(v) ? Number(v) : null;
  } catch {
    return null;
  }
}

/**
 * Branches, and which one is being looked at. With no branch chosen everything is the whole business (every branch together); with one
 * chosen, every list and figure follows it and new sales are recorded in it: the server is told with the `X-Branch` header on each call.
 */
@Injectable({ providedIn: 'root' })
export class BranchesService {
  private readonly http = inject(HttpClient);

  /** The branch looked at now (its id), or null for all. Kept for the next visit. */
  readonly selected = signal<number | null>(read());
  readonly list = signal<Branch[]>([]);

  select(id: number | null): void {
    this.selected.set(id);
    try {
      if (id === null) localStorage.removeItem(KEY);
      else localStorage.setItem(KEY, String(id));
    } catch {
      // private mode: the choice lasts until the page is closed
    }
  }

  /** The name of the branch chosen, for showing where the figures come from. */
  name(): string | null {
    const id = this.selected();
    return id === null ? null : (this.list().find((b) => b.id === id)?.name ?? null);
  }

  // ------------------------------------------------------------------ the server
  branches(): Observable<Branch[]> {
    return this.http.get<{ data: Branch[] }>(`${API}/inventory/branches`).pipe(
      map((r) => (r.data ?? []).map((b) => ({ id: Number(b.id), name: String(b.name), address: b.address ?? null, phone: b.phone ?? null, active: b.active === true }))),
    );
  }

  save(id: number | null, body: { name: string; address: string | null; phone: string | null; active?: boolean }): Observable<void> {
    const call = id === null ? this.http.post(`${API}/inventory/branches`, body) : this.http.put(`${API}/inventory/branches/${id}`, body);

    return call.pipe(map(() => undefined));
  }

  remove(id: number): Observable<void> {
    return this.http.delete(`${API}/inventory/branches/${id}`).pipe(map(() => undefined));
  }

  team(): Observable<BranchTeamMember[]> {
    return this.http.get<{ data: BranchTeamMember[] }>(`${API}/inventory/branch-team`).pipe(map((r) => r.data ?? []));
  }

  assign(staffId: string, branchId: number | null): Observable<void> {
    return this.http.put(`${API}/inventory/branch-team/${staffId}`, { branch_id: branchId }).pipe(map(() => undefined));
  }

  branchSales(from: string, to: string): Observable<BranchSales> {
    return this.http.get<{ data: BranchSales }>(`${API}/inventory/branch-sales`, { params: { from, to } }).pipe(map((r) => r.data));
  }

  stock(): Observable<BranchStock> {
    return this.http.get<{ data: BranchStock }>(`${API}/inventory/branch-stock`).pipe(map((r) => r.data));
  }

  transfer(body: { product_id: number; from_branch_id: number | null; to_branch_id: number | null; quantity: number }): Observable<void> {
    return this.http.post(`${API}/inventory/branch-stock/transfer`, body).pipe(map(() => undefined));
  }

  setLevel(body: { product_id: number; branch_id: number; min_quantity: number | null }): Observable<void> {
    return this.http.put(`${API}/inventory/branch-stock/level`, body).pipe(map(() => undefined));
  }

  transfers(): Observable<BranchTransfer[]> {
    return this.http.get<{ data: BranchTransfer[] }>(`${API}/inventory/branch-stock/transfers`, { params: { limit: '50' } }).pipe(map((r) => r.data ?? []));
  }
}
