import { AuthService } from './auth.service';

/**
 * Every page of the app, with who may open it. The sidebar, the page guards, the search box and the "where do I start" redirect all
 * read this one list, so a person is never shown a page they cannot open (or able to open one that is not shown).
 * The server enforces the same rights; this keeps the screens honest.
 */
export interface NavItem {
  key: 'dashboard' | 'products' | 'sales' | 'credit' | 'debts' | 'expenses' | 'branch_stock' | 'branches' | 'branch_team' | 'branch_sales' | 'assistant';
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
    salonLabelKey: 'nav.dashboard.salon',
    hintKey: 'nav.dashboard.hint',
    group: 'overview',
    icon: 'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6',
    // The month's figures: the salon has them too (the same report the phone shows its owner), so an accountant working in a salon is not left with an empty app.
    allowed: (a) => a.sells() && a.can('inv_view_reports'),
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
    allowed: (a) => a.sells() && a.can('inv_view_credit'),
  },
  {
    key: 'debts',
    path: '/debts',
    labelKey: 'nav.debts',
    hintKey: 'nav.debts.hint',
    group: 'money',
    icon: 'M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z',
    allowed: (a) => a.sells() && a.can('inv_view_credit'),
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
    key: 'branch_stock',
    path: '/branch-stock',
    labelKey: 'nav.branch_stock',
    hintKey: 'nav.branch_stock.hint',
    group: 'overview',
    icon: 'M3 7l9-4 9 4M4 7v10l8 4 8-4V7M12 11v10',
    // As on the mobile app: whoever runs the settings or reads the reports sees (and moves) the goods held by each branch.
    // In a salon it is a section of its own, which the owner switches on for each person (the server refuses it otherwise).
    allowed: (a) => (a.service() === 'salon' ? a.can('inv_salon_branch_stock') : a.canAny('inv_manage_settings', 'inv_view_reports')),
  },
  {
    key: 'branches',
    path: '/branches',
    labelKey: 'nav.branches',
    hintKey: 'nav.branches.hint',
    group: 'overview',
    icon: 'M3 21h18M5 21V7l7-4 7 4v14M9 21v-6h6v6',
    allowed: (a) => a.can('inv_manage_settings'),
  },
  {
    key: 'branch_team',
    path: '/branch-team',
    labelKey: 'nav.branch_team',
    hintKey: 'nav.branch_team.hint',
    group: 'overview',
    icon: 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z',
    allowed: (a) => a.can('inv_manage_settings'),
  },
  {
    key: 'branch_sales',
    path: '/branch-sales',
    labelKey: 'nav.branch_sales',
    hintKey: 'nav.branch_sales.hint',
    group: 'overview',
    icon: 'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z',
    allowed: (a) => a.can('inv_view_reports'),
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

/**
 * The phone's menus that the web app does not have yet: the business admin sees them in the menu, marked as "on the phone", so the whole
 * menu is in view and nothing seems missing. Each one is shown only to someone who holds its right.
 */
export interface PhoneOnly {
  key: string;
  labelKey: string;
  icon: string;
  right: string;
}

export const PHONE_ONLY: PhoneOnly[] = [
  { key: 'appointments', labelKey: 'nav.ph.appointments', right: 'inv_salon_appointments', icon: 'M8 7V3m8 4V3M5 11h14M5 5h14a2 2 0 012 2v12a2 2 0 01-2 2H5a2 2 0 01-2-2V7a2 2 0 012-2z' },
  { key: 'stylists', labelKey: 'nav.ph.stylists', right: 'inv_salon_stylists', icon: 'M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z' },
  { key: 'rebook', labelKey: 'nav.ph.rebook', right: 'inv_salon_rebook', icon: 'M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15' },
  { key: 'queue', labelKey: 'nav.ph.queue', right: 'inv_salon_walkins', icon: 'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z' },
  { key: 'reports', labelKey: 'nav.ph.reports', right: 'inv_view_reports', icon: 'M9 17v-6m4 6V7m4 10v-3M5 21h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v14a2 2 0 002 2z' },
  { key: 'money', labelKey: 'nav.ph.money', right: 'inv_salon_money', icon: 'M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z' },
  { key: 'team', labelKey: 'nav.ph.team', right: 'inv_salon_team', icon: 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z' },
  { key: 'insights', labelKey: 'nav.ph.insights', right: 'inv_salon_insights', icon: 'M13 7h8m0 0v8m0-8l-8 8-4-4-6 6' },
  { key: 'feedback', labelKey: 'nav.ph.feedback', right: 'inv_salon_feedback', icon: 'M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z' },
  { key: 'equipment', labelKey: 'nav.ph.equipment', right: 'inv_salon_equipment', icon: 'M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z' },
  { key: 'business', labelKey: 'nav.ph.business', right: 'inv_manage_settings', icon: 'M3 21h18M5 21V7l7-4 7 4v14M9 21v-6h6v6' },
  { key: 'offers', labelKey: 'nav.ph.offers', right: 'inv_manage_settings', icon: 'M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z' },
  { key: 'settings', labelKey: 'nav.ph.settings', right: 'inv_manage_settings', icon: 'M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4' },
];

/** The phone-only menus this person would see in the menu: the business admin of a salon, for the rights held. */
export function phoneOnlyPages(auth: AuthService): PhoneOnly[] {
  if (!auth.isBusinessAdmin() || auth.service() !== 'salon') return [];

  return PHONE_ONLY.filter((p) => auth.can(p.right));
}

/** The pages this person may open, in sidebar order. */
export function allowedPages(auth: AuthService): NavItem[] {
  return NAV.filter((n) => n.allowed(auth));
}

/** Where a person lands: the first page they may open, or the "nothing here yet" page. */
export function homePath(auth: AuthService): string {
  // The accountant and the business admin start on the dashboard (the accountant's month, the owner's whole dashboard), whatever else the menu
  // offers first. Everyone else starts on the first page their rights open.
  const dashboard = NAV.find((p) => p.key === 'dashboard');
  if ((auth.user()?.role === 'accountant' || auth.isBusinessAdmin()) && dashboard?.allowed(auth)) return '/dashboard';
  // (the assistant is for everyone, so it never counts as "their first page": someone with no page still lands on the explanation)
  return allowedPages(auth).find((p) => p.key !== 'assistant')?.path ?? '/welcome';
}

/** Where "/" leads after sign-in: the picker for someone with several services, else their first page. */
export function startPath(auth: AuthService): string {
  return auth.needsPick() ? '/services' : homePath(auth);
}
