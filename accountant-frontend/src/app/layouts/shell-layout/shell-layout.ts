import { Component, HostListener, OnDestroy, computed, inject, signal } from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { filter, firstValueFrom } from 'rxjs';

import { environment } from '../../../environments/environment';
import { AccountantApi } from '../../core/accountant-api.service';
import { AuthService } from '../../core/auth.service';
import { I18nService } from '../../core/i18n.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { ToastService } from '../../core/services/toast.service';
import { AppNotification, ServiceName } from '../../core/models';
import { NAV, NavItem, allowedPages } from '../../core/nav';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';

/**
 * The frame around every signed-in page: the sidebar (only the pages this person may open), the top bar (search, language,
 * the shop/salon switch when they work in both, the bell, their menu) and the page itself.
 */
@Component({
  selector: 'app-shell-layout',
  imports: [RouterOutlet, RouterLink, RouterLinkActive, FormsModule, ModalDialogComponent],
  templateUrl: './shell-layout.html',
})
export class ShellLayout implements OnDestroy {
  protected readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);
  protected readonly toastService = inject(ToastService);
  private readonly confirm = inject(ConfirmService);
  private readonly api = inject(AccountantApi);
  private readonly router = inject(Router);

  protected readonly appName = environment.appName;

  /** The pages in each part of the sidebar. */
  protected readonly pages = computed(() => {
    this.auth.service(); // the list changes when the person switches between shop and salon
    return allowedPages(this.auth);
  });
  protected readonly overview = computed(() => this.pages().filter((p) => p.group === 'overview'));
  protected readonly money = computed(() => this.pages().filter((p) => p.group === 'money'));
  protected readonly helpPages = computed(() => this.pages().filter((p) => p.group === 'help'));

  /** A page's name in the menu: a salon sees "Services & goods" where a shop sees "Products". */
  protected label(item: NavItem): string {
    return this.i18n.t(this.auth.service() === 'salon' && item.salonLabelKey ? item.salonLabelKey : item.labelKey);
  }

  protected readonly sidebarOpen = signal(false); // phone drawer
  protected readonly sidebarCollapsed = signal(false); // icons only
  protected readonly profileOpen = signal(false);
  protected readonly searchQuery = signal('');
  protected readonly searchOpen = signal(false);
  protected readonly currentUrl = signal(this.router.url);
  protected readonly showProfile = signal(false);
  protected readonly showHelp = signal(false);

  // the bell
  protected readonly notifications = signal<AppNotification[]>([]);
  protected readonly unreadCount = signal(0);
  protected readonly bellOpen = signal(false);
  private bellTimer: ReturnType<typeof setInterval> | null = null;
  private payTimer: ReturnType<typeof setInterval> | null = null;

  protected readonly user = computed(() => this.auth.user()!);

  // the business's plan: a warning as the end comes near, and a cover while the server holds the business back
  protected readonly blocked = this.auth.blocked;
  protected readonly checking = signal(false);
  protected readonly stillUnpaid = signal(false);
  protected readonly planBanner = computed(() => {
    const s = this.auth.subscription();
    if (!s || this.blocked()) return null;
    if (s.status === 'expiring') return { tone: 'warn', text: this.i18n.t('sub.expiring', s.days_left ?? 0) };
    if (s.status === 'grace') return { tone: 'warn', text: this.i18n.t('sub.grace') };
    if (s.status === 'expired') return { tone: 'bad', text: this.i18n.t('sub.expired') };
    return null;
  });
  protected readonly payPhone = computed(() => this.auth.subscription()?.contact_phone ?? '');
  protected readonly initials = computed(() => (this.user().name || '?').trim().slice(0, 2).toUpperCase());
  protected readonly serviceNames: Record<ServiceName, string> = { inventory: 'service.inventory', salon: 'service.salon' };

  protected readonly breadcrumb = computed(() => {
    const url = this.currentUrl();
    const page = NAV.find((n) => url.startsWith(n.path));
    return page ? this.i18n.t(page.labelKey) : this.i18n.t('nav.welcome');
  });

  protected readonly today = computed(() => new Date().toLocaleDateString(this.i18n.locale(), { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }));

  /** Every page this person can open, found by what they type in the box above the page. */
  protected readonly searchResults = computed(() => {
    const q = this.searchQuery().toLowerCase().trim();
    if (!q) return [];
    return this.pages()
      .filter((p) => `${this.i18n.t(p.labelKey)} ${this.i18n.t(p.hintKey)}`.toLowerCase().includes(q))
      .slice(0, 6);
  });

  constructor() {
    this.router.events.pipe(filter((e) => e instanceof NavigationEnd)).subscribe((e) => {
      this.currentUrl.set((e as NavigationEnd).urlAfterRedirects);
      this.sidebarOpen.set(false);
    });
    if (typeof window !== 'undefined') {
      void this.loadNotifications();
      void this.loadSubscription();
      this.bellTimer = setInterval(() => void this.loadNotifications(), 60_000);
      // while the business is held back for an unpaid plan, ask again now and then: the cover goes by itself once a payment is recorded
      this.payTimer = setInterval(() => {
        if (this.blocked()) void this.recheckPlan(false);
      }, 30_000);
    }
  }

  ngOnDestroy(): void {
    if (this.bellTimer) clearInterval(this.bellTimer);
    if (this.payTimer) clearInterval(this.payTimer);
  }

  protected async loadSubscription(): Promise<void> {
    // An account with no business (the platform admin) has no plan: the server would only answer 404, which shows as a red line in the browser console.
    if (!this.user().business) return;
    try {
      const s = await firstValueFrom(this.api.subscription());
      this.auth.subscription.set(s);
      this.auth.blocked.set(s.blocked);
    } catch {
      // no plan information (or no connection): nothing is shown
    }
  }

  /** "I have paid": ask the server at once whether the business is open again. */
  protected async recheckPlan(manual: boolean): Promise<void> {
    if (this.checking()) return;
    if (manual) this.checking.set(true);
    await this.loadSubscription();
    this.checking.set(false);
    this.stillUnpaid.set(manual && this.blocked());
  }

  protected toggleSidebar(): void {
    this.sidebarOpen.update((v) => !v);
  }

  protected toggleCollapse(): void {
    this.sidebarCollapsed.update((v) => !v);
  }

  protected toggleProfile(): void {
    this.bellOpen.set(false);
    this.profileOpen.update((v) => !v);
  }

  protected openSearchResult(item: NavItem): void {
    void this.router.navigate([item.path]);
    this.searchQuery.set('');
    this.searchOpen.set(false);
  }

  protected searchEnter(): void {
    const first = this.searchResults()[0];
    if (first) this.openSearchResult(first);
  }

  /** Switch between the shop and the salon (only for people who work in both): the whole app then reads that service. */
  protected switchService(service: ServiceName): void {
    if (this.auth.service() === service) return;
    this.auth.switchService(service);
    void this.loadNotifications();
    // go to the first page of that service; a page the person may not open there would only show an error
    const first = allowedPages(this.auth)[0];
    void this.router.navigate([first?.path ?? '/welcome']);
  }

  // ------------------------------------------------------------------ the bell
  protected async loadNotifications(): Promise<void> {
    try {
      const res = await firstValueFrom(this.api.notifications());
      this.notifications.set(res.items);
      this.unreadCount.set(res.unread);
    } catch {
      // the bell stays as it was; the next round tries again
    }
  }

  protected toggleBell(): void {
    this.profileOpen.set(false);
    this.bellOpen.update((v) => !v);
    if (this.bellOpen()) void this.loadNotifications();
  }

  protected async openNotification(n: AppNotification): Promise<void> {
    this.bellOpen.set(false);
    if (n.read_at) return;
    this.notifications.update((l) => l.map((x) => (x.id === n.id ? { ...x, read_at: new Date().toISOString() } : x)));
    this.unreadCount.update((c) => Math.max(0, c - 1));
    try {
      await firstValueFrom(this.api.markNotificationRead(n.id));
    } catch {
      // shown as read until the next refresh
    }
  }

  protected async markAllRead(): Promise<void> {
    this.notifications.update((l) => l.map((x) => ({ ...x, read_at: x.read_at ?? new Date().toISOString() })));
    this.unreadCount.set(0);
    try {
      await firstValueFrom(this.api.markAllNotificationsRead());
    } catch {
      // ignore
    }
  }

  protected timeAgo(iso: string): string {
    const seconds = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
    if (seconds < 60) return this.i18n.t('time.now');
    if (seconds < 3600) return this.i18n.t('time.min', Math.floor(seconds / 60));
    if (seconds < 86400) return this.i18n.t('time.hour', Math.floor(seconds / 3600));
    return this.i18n.t('time.day', Math.floor(seconds / 86400));
  }

  // ------------------------------------------------------------------ the person
  protected openProfile(): void {
    this.profileOpen.set(false);
    this.showProfile.set(true);
  }

  protected openHelp(): void {
    this.profileOpen.set(false);
    this.showHelp.set(true);
  }

  /** What the person may do, in words they know (not the system's codes). */
  protected readonly rightsInWords = computed(() => {
    const labels: [string, string][] = [
      ['inv_view_reports', 'right.reports'],
      ['inv_view_credit', 'right.debts'],
      ['inv_create_sales', 'right.sell'],
      ['inv_manage_sales', 'right.sales'],
      ['inv_view_expenses', 'right.expenses.view'],
      ['inv_manage_expenses', 'right.expenses.manage'],
    ];
    return labels.filter(([code]) => this.auth.can(code)).map(([, key]) => this.i18n.t(key));
  });

  protected async signOut(): Promise<void> {
    this.profileOpen.set(false);
    const yes = await this.confirm.ask({
      title: this.i18n.t('signout.title'),
      message: this.i18n.t('signout.message'),
      confirmLabel: this.i18n.t('signout.yes'),
      cancelLabel: this.i18n.t('common.stay'),
    });
    if (yes) this.auth.logout();
  }

  @HostListener('document:keydown.escape')
  protected onEscape(): void {
    this.searchOpen.set(false);
    this.bellOpen.set(false);
    this.profileOpen.set(false);
  }

  @HostListener('document:click', ['$event'])
  protected onDocumentClick(e: MouseEvent): void {
    const target = e.target as HTMLElement;
    if (!target.closest('.topbar-search')) this.searchOpen.set(false);
    if (!target.closest('.bell-wrap')) this.bellOpen.set(false);
    if (!target.closest('.profile-menu-wrap')) this.profileOpen.set(false);
  }
}
