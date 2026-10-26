/** Customers who buy on credit, as the web app uses them. Numbers are always numbers (the server sends many as text). */
export interface CreditCustomer {
  id: number;
  name: string;
  phone: string;
  /** What they owe now: credit sales not yet paid, plus any debt from before the app. */
  balance: number;
  /** The part of the balance that dates from before the app. */
  old_balance: number;
  credit_limit: number;
  payment_terms_days: number;
  is_blocked: boolean;
  block_reason: string | null;
}

export type CreditState = 'blocked' | 'over' | 'near' | 'ok';

export interface AgeingRow {
  customer_id: number;
  customer_name: string;
  customer_phone: string;
  credit_limit: number;
  current: number;
  days_31_60: number;
  days_61_90: number;
  days_90_plus: number;
  total: number;
  oldest_days: number;
}

export interface AgeingTotals {
  grand_total: number;
  current: number;
  days_31_60: number;
  days_61_90: number;
  days_90_plus: number;
}

export interface AgeingListing {
  rows: AgeingRow[];
  totals: AgeingTotals;
}

export interface StatementSale {
  id: number;
  number: string;
  total: number;
  paid_total: number;
  payment_status: string;
  due_date: string | null;
  created_at: string;
}

export interface StatementPayment {
  id: number;
  amount: number;
  method: string | null;
  reference: string | null;
  paid_at: string;
  sale_number: string;
}

export interface Statement {
  from: string;
  to: string;
  opening_balance: number;
  old_debt: number;
  period_charges: number;
  period_payments: number;
  closing_balance: number;
  sales: StatementSale[];
  payments: StatementPayment[];
}

export interface CreditSettingsBody {
  credit_limit: number;
  payment_terms_days: number;
  is_blocked: boolean;
  block_reason: string | null;
}

export interface ReceivePaymentBody {
  customer_id: number;
  amount: number;
  method: 'cash' | 'mobile_money' | 'bank_transfer' | 'cheque';
  reference?: string;
  allocations: { sale_id: number; amount: number }[];
}

/** How close a customer is to their limit, in the words the screens use (the mobile app's rule: "near" starts at 90% of the limit). */
export function creditState(c: Pick<CreditCustomer, 'balance' | 'credit_limit' | 'is_blocked'>): CreditState {
  if (c.is_blocked) return 'blocked';
  if (c.credit_limit > 0 && c.balance > c.credit_limit) return 'over';
  if (c.credit_limit > 0 && c.balance >= c.credit_limit * 0.9) return 'near';
  return 'ok';
}
