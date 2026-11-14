import { Component, computed, inject } from '@angular/core';

import { AuthService } from '../../core/auth.service';
import { AdminHomeComponent } from './admin-home';
import { DashboardPage } from './dashboard';

/**
 * The dashboard address: the business admin of a salon gets the phone's own dashboard (the same cards and figures, in the same look, one
 * column so it reads the same on a phone); everyone else (the accountant, a shop) gets the dashboard they had.
 */
@Component({
  selector: 'app-dashboard-entry',
  imports: [AdminHomeComponent, DashboardPage],
  template: `@if (owner()) { <app-admin-home /> } @else { <app-dashboard /> }`,
})
export class DashboardEntryPage {
  private readonly auth = inject(AuthService);

  protected readonly owner = computed(() => this.auth.service() === 'salon' && this.auth.isBusinessAdmin());
}
