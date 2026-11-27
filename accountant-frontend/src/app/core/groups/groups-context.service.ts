import { Injectable, computed, inject, signal } from '@angular/core';

import { AuthService } from '../auth.service';
import { GroupsApi, Row } from './groups-api.service';
import { groupHasMember, groupRights, groupViewAsMember } from './groups-rights';

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
  /** Does this person hold an office, so the ME switch is offered (whatever the view now)? */
  readonly canSwitch = computed(() => this.me()?.['can_switch_view'] === true);
  /** ME is on: the group is seen as an ordinary member sees it. */
  readonly viewingAsMember = groupViewAsMember.asReadonly();

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
    // ME is remembered per person (as on the phone): set it before the first call, so the first answer is already the right view.
    if (this.forUser !== id) groupViewAsMember.set(this.savedMe(id));
    this.loading = this.api
      .get('/me')
      .then(async (d) => {
        // Someone with no office (any more) has nothing to switch: ME goes off and the answer is read again without it.
        if (groupViewAsMember() && d['can_switch_view'] !== true) {
          this.saveMe(id, false);
          groupViewAsMember.set(false);
          d = await this.api.get('/me');
        }
        this.forUser = id;
        this.me.set(d);
        groupRights.set(new Set((d['rights'] as string[] | undefined) ?? []));
        groupHasMember.set(!!d['member']);
      })
      .catch(() => {
        this.me.set(null);
        groupRights.set(new Set());
      })
      .finally(() => (this.loading = null));

    return this.loading;
  }

  /** Turn ME on or off: remembered, then the group is read again in that view. */
  async setViewAsMember(on: boolean): Promise<void> {
    this.saveMe(this.auth.user()?.id ?? null, on);
    groupViewAsMember.set(on);
    await this.reload();
  }

  private meKey(id: string | null): string {
    return `groups_me_view_${id ?? ''}`;
  }

  private savedMe(id: string | null): boolean {
    try {
      return localStorage.getItem(this.meKey(id)) === '1';
    } catch {
      return false; // a convenience: without storage it starts off
    }
  }

  private saveMe(id: string | null, on: boolean): void {
    try {
      if (on) localStorage.setItem(this.meKey(id), '1');
      else localStorage.removeItem(this.meKey(id));
    } catch {
      /* not remembered; it still works for this visit */
    }
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
    groupViewAsMember.set(false);
    groupHasMember.set(false);
  }
}
