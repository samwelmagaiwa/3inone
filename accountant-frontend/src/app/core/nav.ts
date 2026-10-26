import { AuthService } from './auth.service';

/**
 * Every page of the app, with who may open it. The sidebar, the page guards, the search box and the "where do I start" redirect all
 * read this one list, so a person is never shown a page they cannot open (or able to open one that is not shown).
 * The server enforces the same rights; this keeps the screens honest.
 */
export interface NavItem {
  key: 'dashboard' | 'products' | 'sales' | 'credit' | 'debts' | 'expenses' | 'assistant';
  path: string;
  labelKey: string;
  hintKey: string;
  /** The label to use while working in the salon, when it differs ("Services & goods"). */
  salonLabelKey?: string;
  group: 'overview' | 'money' | 'help';
  /** An SVG path (24x24, stroke icon). */
  icon: string;
  allowed: (auth: AuthService) => boolean;
}

export const NAV: NavItem[] = [
  {
    key: 'dashboard',
    path: '/dashboard',
    labelKey: 'nav.dashboard',
    hintKey: 'nav.dashboard.hint',
    group: 'overview',
    icon: 'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6',
    allowed: (a) => a.service() === 'inventory' && a.can('inv_view_reports'),
  },
  {
    key: 'products',
    path: '/products',
    labelKey: 'nav.products',
    salonLabelKey: 'nav.products.salon',
    hintKey: 'nav.products.hint',
    group: 'overview',
    icon: 'M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4',
    // The same as the mobile app's Products section: whoever may see products (a sales officer, an accountant, ...).
    allowed: (a) => a.can('inv_view_products'),
  },
  {
    key: 'sales',
    path: '/sales',
    labelKey: 'nav.sales',
    hintKey: 'nav.sales.hint',
    group: 'money',
    icon: 'M3 3h2l.4 2M7 13h10l4-8H5.4M7 13L5.4 5M7 13l-2.293 2.293c-.63.63-.184 1.707.707 1.707H17m0 0a2 2 0 100 4 2 2 0 000-4zm-8 2a2 2 0 11-4 0 2 2 0 014 0z',
    // The server opens the sales list only to inv_create_sales (and so does the mobile app's Sales section): offering it to anyone else would only show an error.
    allowed: (a) => a.can('inv_create_sales'),
  },
  {
    key: 'credit',
    path: '/customers',
    labelKey: 'nav.credit',
    hintKey: 'nav.credit.hint',
    group: 'money',
    icon: 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z',
    // The mobile app's "Customers & credit": the same right (and the same server routes) as the debts page.
    allowed: (a) => a.service() === 'inventory' && a.can('inv_view_credit'),
  },
  {
    key: 'debts',
    path: '/debts',
    labelKey: 'nav.debts',
    hintKey: 'nav.debts.hint',
    group: 'money',
    icon: 'M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z',
    allowed: (a) => a.service() === 'inventory' && a.can('inv_view_credit'),
  },
  {
    key: 'expenses',
    path: '/expenses',
    labelKey: 'nav.expenses',
    hintKey: 'nav.expenses.hint',
    group: 'money',
    icon: 'M9 14l6-6m-5.5.5h.01m4.99 5h.01M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16l3.5-2 3.5 2 3.5-2 3.5 2z',
    allowed: (a) => a.canAny('inv_view_expenses', 'inv_manage_expenses'),
  },
  {
    key: 'assistant',
    path: '/assistant',
    labelKey: 'nav.assistant',
    hintKey: 'nav.assistant.hint',
    group: 'help',
    // a sparkle: the AI mark
    icon: 'M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z',
    // Everyone who is signed in: the server decides what it may read for them, and how-to help needs no data at all.
    allowed: (a) => !!a.user(),
  },
];

/** The pages this person may open, in sidebar order. */
export function allowedPages(auth: AuthService): NavItem[] {
  return NAV.filter((n) => n.allowed(auth));
}

/** Where a person lands: the first page they may open, or the "nothing here yet" page. */
export function homePath(auth: AuthService): string {
  // (the assistant is for everyone, so it never counts as "their first page": someone with no page still lands on the explanation)
  return allowedPages(auth).find((p) => p.key !== 'assistant')?.path ?? '/welcome';
}

/** Where "/" leads after sign-in: the picker for someone with several services, else their first page. */
export function startPath(auth: AuthService): string {
  return auth.needsPick() ? '/services' : homePath(auth);
}
