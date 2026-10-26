import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable, map } from 'rxjs';

import { environment } from '../../environments/environment';
import {
  Advice,
  AssistantAnswer,
  AssistantStatus,
  AssistantTurnOut,
  ApiEnvelope,
  AppNotification,
  Debt,
  DebtKind,
  DebtPayment,
  DebtsListing,
  Expense,
  ExpenseSummary,
  MonthlyReport,
  Paged,
  SaleRow,
  Subscription,
  Target,
} from './models';

const API = environment.apiUrl;

/** Everything the pages ask of the server, in one place. The same API the mobile app uses; the server decides what each person may see. */
export interface ExpenseBody {
  category: string;
  description: string;
  amount: number;
  expense_date: string;
  is_personal: boolean;
  supplier?: string | null;
  payment_method?: string | null;
}

@Injectable({ providedIn: 'root' })
export class AccountantApi {
  private readonly http = inject(HttpClient);

  // ------------------------------------------------------------------ the business and its plan
  subscription(): Observable<Subscription> {
    return this.http.get<ApiEnvelope<Subscription>>(`${API}/business/subscription`).pipe(map((r) => r.data));
  }

  // ------------------------------------------------------------------ the month
  monthlyReport(month: string): Observable<MonthlyReport> {
    return this.http.get<ApiEnvelope<MonthlyReport>>(`${API}/inventory/monthly-report`, { params: { month } }).pipe(map((r) => r.data));
  }

  /** Set the month's profit target (0 clears it). */
  setTarget(month: string, profitTarget: number): Observable<Target | null> {
    return this.http.put<ApiEnvelope<Target | null>>(`${API}/inventory/monthly-target`, { month, profit_target: profitTarget }).pipe(map((r) => r.data));
  }

  // ------------------------------------------------------------------ the AI assistant
  assistantStatus(): Observable<AssistantStatus> {
    return this.http.get<ApiEnvelope<AssistantStatus>>(`${API}/assistant`).pipe(map((r) => r.data));
  }

  /** Ask a question. `topic` is the id of a one-tap suggestion: the server then reads the data first and answers faster. */
  assistantAsk(question: string, lang: 'sw' | 'en', history: AssistantTurnOut[], topic?: string): Observable<AssistantAnswer> {
    return this.http.post<ApiEnvelope<AssistantAnswer>>(`${API}/assistant`, { question, lang, history, ...(topic ? { topic } : {}) }).pipe(map((r) => r.data));
  }

  advice(month: string, lang: 'sw' | 'en', refresh = false): Observable<Advice> {
    let params = new HttpParams().set('month', month).set('lang', lang);
    if (refresh) params = params.set('refresh', '1');
    return this.http.get<ApiEnvelope<Advice>>(`${API}/inventory/advice`, { params }).pipe(map((r) => r.data));
  }

  // ------------------------------------------------------------------ debts from before the app
  debts(kind: DebtKind): Observable<DebtsListing> {
    return this.http.get<ApiEnvelope<DebtsListing>>(`${API}/inventory/opening-debts`, { params: { kind } }).pipe(map((r) => r.data));
  }

  addDebt(body: { kind: DebtKind; name: string; phone?: string; amount: number; started_on?: string; due_on?: string; note?: string }): Observable<void> {
    return this.http.post(`${API}/inventory/opening-debts`, body).pipe(map(() => undefined));
  }

  payDebt(id: number, amount: number, method?: string): Observable<void> {
    return this.http.post(`${API}/inventory/opening-debts/${id}/payments`, { amount, ...(method ? { method } : {}) }).pipe(map(() => undefined));
  }

  debtPayments(id: number): Observable<DebtPayment[]> {
    return this.http.get<ApiEnvelope<DebtPayment[]>>(`${API}/inventory/opening-debts/${id}/payments`).pipe(map((r) => r.data));
  }

  deleteDebt(id: number): Observable<void> {
    return this.http.delete(`${API}/inventory/opening-debts/${id}`).pipe(map(() => undefined));
  }

  // ------------------------------------------------------------------ expenses
  expenses(from: string, to: string): Observable<Expense[]> {
    return this.http.get<ApiEnvelope<Expense[]>>(`${API}/inventory/expenses`, { params: { period: 'custom', from, to } }).pipe(map((r) => r.data));
  }

  expenseSummary(from: string, to: string): Observable<ExpenseSummary> {
    return this.http.get<ApiEnvelope<ExpenseSummary>>(`${API}/inventory/expenses/summary`, { params: { period: 'custom', from, to } }).pipe(map((r) => r.data));
  }

  expenseCategories(): Observable<string[]> {
    return this.http.get<ApiEnvelope<string[]>>(`${API}/inventory/expenses/categories`).pipe(map((r) => r.data));
  }

  addExpense(body: ExpenseBody): Observable<Expense> {
    return this.http.post<ApiEnvelope<Expense>>(`${API}/inventory/expenses`, body).pipe(map((r) => r.data));
  }

  updateExpense(id: number, body: ExpenseBody): Observable<Expense> {
    return this.http.put<ApiEnvelope<Expense>>(`${API}/inventory/expenses/${id}`, body).pipe(map((r) => r.data));
  }

  /** The owner or a manager decides an expense somebody else recorded. */
  decideExpense(id: number, decision: 'approve' | 'reject'): Observable<void> {
    return this.http.post(`${API}/inventory/expenses/${id}/approval`, { decision }).pipe(map(() => undefined));
  }

  attachReceipt(id: number, photo: File): Observable<void> {
    const form = new FormData();
    form.append('photo', photo);
    return this.http.post(`${API}/inventory/expenses/${id}/receipt`, form).pipe(map(() => undefined));
  }

  deleteExpense(id: number): Observable<void> {
    return this.http.delete(`${API}/inventory/expenses/${id}`).pipe(map(() => undefined));
  }

  // ------------------------------------------------------------------ sales
  sales(params: { from?: string; to?: string; status?: string; q?: string; page?: number }): Observable<Paged<SaleRow>> {
    let p = new HttpParams();
    for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== '') p = p.set(k, String(v));
    return this.http.get<Paged<SaleRow>>(`${API}/inventory/sales`, { params: p });
  }

  salesSummary(params: { from?: string; to?: string; status?: string; q?: string }): Observable<{ count: number; total: number; paid: number; debt: number }> {
    let p = new HttpParams();
    for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== '') p = p.set(k, String(v));
    return this.http.get<ApiEnvelope<{ count: number; total: number; paid: number; debt: number }>>(`${API}/inventory/sales/summary`, { params: p }).pipe(map((r) => r.data));
  }

  // ------------------------------------------------------------------ the bell
  notifications(): Observable<{ items: AppNotification[]; unread: number }> {
    return this.http
      .get<{ data: AppNotification[]; meta?: { unread_count?: number } }>(`${API}/inventory/notifications`)
      .pipe(map((r) => ({ items: r.data.slice(0, 30), unread: r.meta?.unread_count ?? 0 })));
  }

  markNotificationRead(id: number): Observable<void> {
    return this.http.post(`${API}/inventory/notifications/${id}/read`, {}).pipe(map(() => undefined));
  }

  markAllNotificationsRead(): Observable<void> {
    return this.http.post(`${API}/inventory/notifications/read-all`, {}).pipe(map(() => undefined));
  }

  // ------------------------------------------------------------------ passwords (no sign-in needed)
  forgotPassword(email: string, phone: string): Observable<void> {
    return this.http.post(`${API}/auth/forgot-password`, { email, phone_number: phone }).pipe(map(() => undefined));
  }

  resetPassword(email: string, code: string, password: string): Observable<void> {
    return this.http.post(`${API}/auth/reset-password`, { email, code, password, password_confirmation: password }).pipe(map(() => undefined));
  }
}

export type { Debt };
