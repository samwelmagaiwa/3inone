import { Injectable, computed, inject, signal } from '@angular/core';

import { AuthService } from '../auth.service';
import { GroupsApi, Row } from './groups-api.service';
import { groupRights } from './groups-rights';

/**
 * Who the signed-in person is in their group (/groups/me): their rights, whether they run the business, the group's name and logo, and
 * what waits for them. Loaded once per person, again after a change that moves it (an office, a setting).
 */
@Injectable({ providedIn: 'root' })
export class GroupsContext {
  private readonly api = inject(GroupsApi);
  private readonly auth = inject(AuthService);

  readonly me = signal<Row | null>(null);
  readonly isOwner = computed(() => this.me()?.['is_owner'] === true);
  readonly groupName = computed(() => String(this.me()?.['group']?.['name'] ?? ''));
  readonly logoUrl = computed<string | null>(() => this.me()?.['group']?.['logo_url'] || null);
  /** What waits for this person: payments to verify, loans to approve, ... (only non-zero counts). */
  readonly waiting = computed<Record<string, number>>(() => this.me()?.['waiting'] ?? {});

  private forUser: string | null = null;
  private loading: Promise<void> | null = null;

  /** Load /groups/me unless it is already loaded for this person. */
  ensure(): Promise<void> {
    const id = this.auth.user()?.id ?? null;
    if (this.me() && this.forUser === id) return Promise.resolve();

    return this.reload();
  }

  reload(): Promise<void> {
    if (this.loading) return this.loading;
    const id = this.auth.user()?.id ?? null;
    this.loading = this.api
      .get('/me')
      .then((d) => {
        this.forUser = id;
        this.me.set(d);
        groupRights.set(new Set((d['rights'] as string[] | undefined) ?? []));
      })
      .catch(() => {
        this.me.set(null);
        groupRights.set(new Set());
      })
      .finally(() => (this.loading = null));

    return this.loading;
  }

  can(...rights: string[]): boolean {
    const held = (this.me()?.['rights'] as string[] | undefined) ?? [];
    return rights.some((r) => held.includes(r));
  }

  /** Forget (signing out, another person). */
  clear(): void {
    this.me.set(null);
    this.forUser = null;
    groupRights.set(new Set());
  }
}
