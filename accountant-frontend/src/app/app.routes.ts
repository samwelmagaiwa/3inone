import { Routes } from '@angular/router';
import { authGuard, noAuthGuard } from './core/auth.guard';

export const routes: Routes = [
    {
    path: 'login',
    canActivate: [noAuthGuard],
    loadComponent: () => import('./pages/login/login').then((m) => m.LoginPage),
  },
  {
    path: '',
    canActivate: [authGuard],
    loadComponent: () => import('./layouts/shell').then((m) => m.Shell),
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'dashboard' },
      {
        path: 'dashboard',
        loadComponent: () => import('./pages/dashboard/dashboard').then((m) => m.DashboardPage),
      },
      // New modules (debts, expenses, reports, ...) are added here as children of the shell.
    ],
  },
  { path: '**', redirectTo: '' },
];
