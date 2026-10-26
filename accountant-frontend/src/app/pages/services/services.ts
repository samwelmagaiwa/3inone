import { Component, computed, inject } from '@angular/core';
import { Router } from '@angular/router';

import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { ServiceName } from '../../core/models';
import { allowedPages, homePath } from '../../core/nav';

/**
 * Right after sign-in, someone who works in more than one service chooses which to open (as on the phone). Services the web app does
 * not cover (rental, transport) are named, with where to use them, so nobody wonders why they are missing.
 */
@Component({
  selector: 'app-services',
  template: `
    <div class="max-w-3xl mx-auto space-y-5 animate-fade-in-up" data-testid="services">
      <div class="page-header-card">
        <p class="label-eyebrow">{{ auth.user()?.business || '' }}</p>
        <h1 class="text-slate-900 font-black text-xl tracking-tight mt-1">{{ i18n.t('services.title') }}</h1>
        <p class="text-slate-500 text-sm mt-0.5">{{ i18n.t('services.sub') }}</p>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        @for (s of services(); track s) {
          <button type="button" class="section-card p-6 text-left hover-lift cursor-pointer service-tile" (click)="open(s)" [attr.data-testid]="'service-' + s">
            <div class="w-14 h-14 flex items-center justify-center kpi-icon-primary" style="border-radius: 14px !important;">
              <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" [attr.d]="icon(s)"/></svg>
            </div>
            <p class="font-black text-slate-900 text-lg mt-4">{{ i18n.t('service.' + s) }}</p>
            <p class="text-sm text-slate-500 mt-1">{{ i18n.t('services.' + s + '.hint') }}</p>
          </button>
        }
      </div>

      @if (auth.user()?.otherServices?.length) {
        <p class="text-xs font-semibold text-slate-400" data-testid="services-other">{{ i18n.t('services.other', others()) }}</p>
      }
    </div>
  `,
  styles: [':host { display: block; } .service-tile { transition: transform .15s; } .service-tile:hover { transform: translateY(-2px); }'],
})
export class ServicesPage {
  protected readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);
  private readonly router = inject(Router);

  protected readonly services = computed(() => this.auth.user()?.services ?? []);
  protected readonly others = computed(() => (this.auth.user()?.otherServices ?? []).map((s) => this.i18n.t(`service.${s}`)).join(', '));

  protected icon(s: ServiceName): string {
    return s === 'inventory'
      ? 'M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4'
      : 'M14.121 14.121L19 19m-7-7l7-7m-7 7l-2.879 2.879M12 12L9.121 9.121m0 5.758a3 3 0 10-4.243 4.243 3 3 0 004.243-4.243zm0-5.758a3 3 0 10-4.243-4.243 3 3 0 004.243 4.243z';
  }

  protected open(s: ServiceName): void {
    this.auth.pick(s);
    void this.router.navigate([allowedPages(this.auth)[0]?.path ?? homePath(this.auth)]);
  }
}
