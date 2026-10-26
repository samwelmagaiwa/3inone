/** How the server wraps most answers: `{ status, message, data }`. */
export interface ApiEnvelope<T> {
  status?: 'success' | 'error';
  message?: string;
  data: T;
}

/** The services the web app works in. */
export type ServiceName = 'inventory' | 'salon';

/** Who is signed in, with what they may do (the server's own list, `effective_permissions`). */
export interface SessionUser {
  id: string;
  name: string;
  email: string;
  role: string;
  roleLabel: string;
  phone?: string;
  /** The services this person works in, among those the web app supports. */
  services: ServiceName[];
  /** Services they have that are used on the phone (rental, transport): listed, never opened here. */
  otherServices: string[];
  /** Inventory rights such as `inv_view_reports`; `__all__` means all of them. */
  permissions: string[];
  business?: string;
}

/** One figure of the monthly report against the month before. */
export interface Comparison {
  now: number;
  before: number;
  change: number;
  percent: number | null;
  direction: 'up' | 'down' | 'same';
  good: boolean;
}

export interface MonthlyReport {
  month: string;
  is_current: boolean;
  is_future: boolean;
  days_elapsed: number;
  days_in_month: number;
  figures: {
    sales: number;
    sales_count: number;
    cost_of_goods: number;
    gross_profit: number;
    margin_percent: number | null;
    expenses: number;
    personal_spending: number;
    write_offs: number;
    net_profit: number;
    expenses_by_category: { category: string; total: number }[];
  };
  previous: { month: string; like_for_like: boolean };
  compare: { sales: Comparison; gross_profit: Comparison; expenses: Comparison; net_profit: Comparison };
  overall: { direction: 'up' | 'down' | 'same'; percent: number | null };
  position: { stock_value: number; receivable: number; payable: number; capital: number } | null;
  capital_change: Comparison | null;
  target: Target | null;
  top_products: { name: string; qty: number; sales: number; profit: number }[];
  top_customers: { name: string; purchases: number; spent: number }[];
  slow_stock: { name: string; quantity: number; value: number }[];
  debtors: { name: string; owed: number; days: number }[];
}

export interface Target {
  profit_target: number;
  profit: number;
  progress_percent: number | null;
  left: number;
  over_by: number;
  expected_by_today: number;
  days_left: number;
  status: 'not_started' | 'on_track' | 'behind' | 'reached' | 'missed';
}

export interface AdviceItem {
  level: 'warning' | 'tip' | 'good';
  title: string;
  detail: string;
}

export interface Advice {
  items: AdviceItem[];
  source: 'ai' | 'rules';
  ai_available: boolean;
  refreshes_left: number;
}

export type DebtKind = 'receivable' | 'payable';

export interface Debt {
  id: number;
  kind: DebtKind;
  name: string;
  phone: string | null;
  amount: number;
  paid: number;
  left: number;
  started_on: string;
  due_on: string | null;
  days_late: number;
  note: string | null;
}

export interface DebtsListing {
  kind: DebtKind;
  debts: Debt[];
  total: number;
  old: number;
  from_records: number;
}

export interface DebtPayment {
  id: number;
  amount: number;
  method: string | null;
  paid_on: string;
}

export interface Expense {
  id: number;
  category: string;
  description: string;
  amount: number;
  expense_date: string;
  is_personal?: boolean | number;
  created_by_name?: string | null;
  status?: string;
  supplier?: string | null;
  payment_method?: string | null;
  receipt_url?: string | null;
}

export interface ExpenseSummary {
  revenue: number;
  cogs: number;
  gross_profit: number;
  total_expenses: number;
  net_profit: number;
  personal_total: number;
  by_category: { category: string; total: number; count: number }[];
}

export interface SaleRow {
  id: number;
  number: string;
  total: number;
  paid_total: number;
  payment_status: 'paid' | 'debt' | 'partial' | string;
  customer_name: string | null;
  created_at: string;
  cancelled_at?: string | null;
  items?: { product_name?: string; qty?: number; unit_name?: string | null; total?: number; staff_name?: string | null }[];
  payments?: { amount: number; method: string | null; paid_at: string }[];
}

export interface Paged<T> {
  data: T[];
  meta?: { current_page?: number; last_page?: number; total?: number; per_page?: number };
}

/** Where the business's plan stands (GET /business/subscription). */
export interface Subscription {
  status: 'never' | 'active' | 'expiring' | 'grace' | 'expired' | string;
  plan: string;
  business_name?: string;
  valid_until: string | null;
  days_left: number | null;
  grace_ends_at?: string | null;
  enforced: boolean;
  blocked: boolean;
  contact_phone?: string;
}

export interface AppNotification {
  id: number;
  type: string;
  title: string;
  body: string;
  read_at: string | null;
  created_at: string;
}

/** The AI assistant: what this person may ask about, and the answers (with the records they rest on). */
export interface AssistantSuggestion {
  id: string;
  en: string;
  sw: string;
  /** null = a "how do I..." question that needs no data. */
  tool: string | null;
}

export interface AssistantStatus {
  available: boolean;
  topics: string[];
  suggestions: AssistantSuggestion[];
  services: string[];
  questions_left: number;
}

export interface AssistantCardRow {
  title: string;
  value?: string;
  note?: string;
}

export interface AssistantCard {
  type: 'rows';
  title: string;
  rows: AssistantCardRow[];
}

export interface AssistantAnswer {
  answer: string;
  cards: AssistantCard[];
  tools: string[];
  questions_left: number;
}

export interface AssistantTurnOut {
  role: 'user' | 'model';
  text: string;
}
