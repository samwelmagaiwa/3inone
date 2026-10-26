import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, map } from 'rxjs';

import { environment } from '../../environments/environment';
import { AgeingListing, AgeingRow, CreditCustomer, CreditSettingsBody, ReceivePaymentBody, Statement, StatementPayment, StatementSale } from './credit.models';

const API = environment.apiUrl;

const num = (v: unknown): number => {
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
};
const str = (v: unknown): string => (v === null || v === undefined ? '' : String(v));

/** Customers on credit: the same server routes the mobile app's "Customers & credit" section uses. */
@Injectable({ providedIn: 'root' })
export class CreditApi {
  private readonly http = inject(HttpClient);

  customers(): Observable<CreditCustomer[]> {
    return this.http.get<{ data: Record<string, unknown>[] }>(`${API}/inventory/credit/customers`).pipe(
      map((r) => (r.data ?? []).map((c) => ({
        id: num(c['id']),
        name: str(c['name']),
        phone: str(c['phone']),
        balance: num(c['balance']),
        old_balance: num(c['old_balance']),
        credit_limit: num(c['credit_limit']),
        payment_terms_days: num(c['payment_terms_days']),
        is_blocked: c['is_blocked'] === true || c['is_blocked'] === 1 || c['is_blocked'] === '1',
        block_reason: str(c['block_reason']) || null,
      }))),
    );
  }

  ageing(): Observable<AgeingListing> {
    return this.http.get<{ data: Record<string, unknown>[]; meta?: Record<string, unknown> }>(`${API}/inventory/credit/debtors-ageing`).pipe(
      map((r) => ({
        rows: (r.data ?? []).map((a): AgeingRow => ({
          customer_id: num(a['customer_id']),
          customer_name: str(a['customer_name']),
          customer_phone: str(a['customer_phone']),
          credit_limit: num(a['credit_limit']),
          current: num(a['current']),
          days_31_60: num(a['days_31_60']),
          days_61_90: num(a['days_61_90']),
          days_90_plus: num(a['days_90_plus']),
          total: num(a['total']),
          oldest_days: num(a['oldest_days']),
        })),
        totals: {
          grand_total: num(r.meta?.['grand_total']),
          current: num(r.meta?.['current']),
          days_31_60: num(r.meta?.['days_31_60']),
          days_61_90: num(r.meta?.['days_61_90']),
          days_90_plus: num(r.meta?.['days_90_plus']),
        },
      })),
    );
  }

  /** A customer's account between two days (YYYY-MM-DD). */
  statement(customerId: number, from: string, to: string): Observable<Statement> {
    const params = new HttpParams().set('from', from).set('to', to);

    return this.http.get<{ data: Record<string, unknown> }>(`${API}/inventory/credit/customers/${customerId}/statement`, { params }).pipe(
      map((r) => {
        const d = r.data;

        return {
          from: str(d['from']),
          to: str(d['to']),
          opening_balance: num(d['opening_balance']),
          old_debt: num(d['old_debt']),
          period_charges: num(d['period_charges']),
          period_payments: num(d['period_payments']),
          closing_balance: num(d['closing_balance']),
          sales: ((d['sales'] as Record<string, unknown>[]) ?? []).map((s): StatementSale => ({
            id: num(s['id']),
            number: str(s['number']),
            total: num(s['total']),
            paid_total: num(s['paid_total']),
            payment_status: str(s['payment_status']),
            due_date: str(s['due_date']) || null,
            created_at: str(s['created_at']),
          })),
          payments: ((d['payments'] as Record<string, unknown>[]) ?? []).map((p): StatementPayment => ({
            id: num(p['id']),
            amount: num(p['amount']),
            method: str(p['method']) || null,
            reference: str(p['reference']) || null,
            paid_at: str(p['paid_at']),
            sale_number: str(p['sale_number']),
          })),
        };
      }),
    );
  }

  saveSettings(customerId: number, body: CreditSettingsBody): Observable<void> {
    return this.http.put(`${API}/inventory/credit/customers/${customerId}`, body).pipe(map(() => undefined));
  }

  /** Take money from a customer against chosen unpaid sales. */
  receivePayment(body: ReceivePaymentBody): Observable<void> {
    return this.http.post(`${API}/inventory/payments`, body).pipe(map(() => undefined));
  }
}
