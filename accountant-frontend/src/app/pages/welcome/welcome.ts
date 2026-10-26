import { Component, computed, inject } from '@angular/core';

import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';

/**
 * Where a person lands when none of the pages is open to them (no service the web app supports, or no rights yet): a plain explanation
 * of what to do, not an error.
 */
@Component({
  selector: 'app-welcome',
  template: `
    <div class="section-card p-10 text-center space-y-3 max-w-xl mx-auto animate-fade-in-up" data-testid="welcome">
      <div class="empty-icon mx-auto">
        <svg fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8"><path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4"/></svg>
      </div>
      <h1 class="text-slate-900 font-black text-xl">{{ i18n.t('welcome.empty.title') }}</h1>
      <p class="text-slate-500 text-sm">{{ i18n.t(auth.user()?.services?.length ? 'welcome.empty.norights' : 'welcome.empty.noservice') }}</p>
      @if (others()) { <p class="text-slate-500 text-sm" data-testid="welcome-other">{{ i18n.t('welcome.empty.phone', others()) }}</p> }
      <p class="text-slate-400 text-xs font-semibold">{{ i18n.t('welcome.empty.ask') }}</p>
    </div>
  `,
})
export class WelcomePage {
  protected readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);
  protected readonly others = computed(() => (this.auth.user()?.otherServices ?? []).map((s) => this.i18n.t(`service.${s}`)).join(', '));
}
