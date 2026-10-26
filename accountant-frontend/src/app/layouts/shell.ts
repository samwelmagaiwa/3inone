import { Component, inject, signal } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';

import { environment } from '../../environments/environment';
import { AuthService } from '../core/auth.service';

interface NavItem {
  label: string;
  path: string | null; // null = planned, not built yet
}

/** The frame around every signed-in page: a sidebar (a drawer on a phone), the person and the way out. */
@Component({
  selector: 'app-shell',
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  templateUrl: './shell.html',
})
export class Shell {
  protected readonly auth = inject(AuthService);
  protected readonly appName = environment.appName;
  protected readonly open = signal(false);

  /** Add a page here when its route is added in app.routes.ts. */
  protected readonly nav: NavItem[] = [
    { label: 'Dashboard', path: '/dashboard' },
    { label: 'Debts', path: null },
    { label: 'Expenses', path: null },
    { label: 'Sales', path: null },
    { label: 'Reports', path: null },
  ];
}
