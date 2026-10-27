import { Routes } from '@angular/router';
import { authGuard, canOpen, canSell, noAuthGuard, startPage } from './core/auth.guard';

export const routes: Routes = [
  {
    path: 'login',
    canActivate: [noAuthGuard],
    loadComponent: () => import('./pages/login/login').then((m) => m.LoginPage),
  },
  {
    path: '',
    canActivate: [authGuard],
    loadComponent: () => import('./layouts/shell-layout/shell-layout').then((m) => m.ShellLayout),
    children: [
      // "/" means "my first page" (the first one this person's rights open)
      { path: '', pathMatch: 'full', canActivate: [startPage], children: [] },
      { path: 'services', loadComponent: () => import('./pages/services/services').then((m) => m.ServicesPage) },
      { path: 'welcome', loadComponent: () => import('./pages/welcome/welcome').then((m) => m.WelcomePage) },
      { path: 'dashboard', canActivate: [canOpen('dashboard')], loadComponent: () => import('./pages/dashboard/dashboard').then((m) => m.DashboardPage) },
      { path: 'products', canActivate: [canOpen('products')], loadComponent: () => import('./pages/products/products').then((m) => m.ProductsPage) },
      { path: 'sales', canActivate: [canOpen('sales')], loadComponent: () => import('./pages/sales/sales').then((m) => m.SalesPage) },
      { path: 'sales/new', canActivate: [canSell], loadComponent: () => import('./pages/till/till').then((m) => m.TillPage) },
      { path: 'customers', canActivate: [canOpen('credit')], loadComponent: () => import('./pages/credit/credit').then((m) => m.CreditPage) },
      { path: 'customers/:id/report', canActivate: [canOpen('credit')], loadComponent: () => import('./pages/customer-report/customer-report').then((m) => m.CustomerReportPage) },
      { path: 'debts', canActivate: [canOpen('debts')], loadComponent: () => import('./pages/debts/debts').then((m) => m.DebtsPage) },
      { path: 'expenses', canActivate: [canOpen('expenses')], loadComponent: () => import('./pages/expenses/expenses').then((m) => m.ExpensesPage) },
      { path: 'branch-stock', canActivate: [canOpen('branch_stock')], loadComponent: () => import('./pages/branch-stock/branch-stock').then((m) => m.BranchStockPage) },
      { path: 'branches', canActivate: [canOpen('branches')], loadComponent: () => import('./pages/branches/branches').then((m) => m.BranchesPage) },
      { path: 'branch-team', canActivate: [canOpen('branch_team')], loadComponent: () => import('./pages/branch-team/branch-team').then((m) => m.BranchTeamPage) },
      { path: 'branch-sales', canActivate: [canOpen('branch_sales')], loadComponent: () => import('./pages/branch-sales/branch-sales').then((m) => m.BranchSalesPage) },
      { path: 'assistant', loadComponent: () => import('./pages/assistant/assistant').then((m) => m.AssistantPage) },
      // New modules are added here as children of the shell, and in core/nav.ts.
    ],
  },
  { path: '**', redirectTo: '' },
];
