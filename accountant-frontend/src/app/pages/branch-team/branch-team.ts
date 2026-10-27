import { Component, OnInit, inject, signal } from '@angular/core';
import { firstValueFrom } from 'rxjs';

import { BranchTeamMember, BranchesService } from '../../core/branches.service';
import { offline, serverMessage } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { MotionService } from '../../core/services/motion.service';
import { ToastService } from '../../core/services/toast.service';

/**
 * Who works in which branch. The owner places each person in a branch (their home branch): the sales they make with no other branch
 * chosen are recorded in it, and the sales report counts them there. "No branch" leaves a person free of any one place.
 */
@Component({
  selector: 'app-branch-team',
  templateUrl: './branch-team.html',
})
export class BranchTeamPage implements OnInit {
  private readonly api = inject(BranchesService);
  private readonly toast = inject(ToastService);
  protected readonly i18n = inject(I18nService);
  protected readonly motion = inject(MotionService);

  protected readonly rows = signal<BranchTeamMember[]>([]);
  protected readonly branches = signal<{ id: number; name: string }[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);

  ngOnInit(): void {
    void this.load();
  }

  protected async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      const [team, list] = await Promise.all([firstValueFrom(this.api.team()), firstValueFrom(this.api.branches())]);
      this.rows.set(team);
      this.branches.set(list.filter((b) => b.active));
    } catch (err) {
      this.error.set(this.messageOf(err));
    } finally {
      this.loading.set(false);
    }
  }

  protected async place(m: BranchTeamMember, value: string): Promise<void> {
    const id = value === '' ? null : Number(value);
    try {
      await firstValueFrom(this.api.assign(m.staff_id, id));
      this.toast.success(this.i18n.t('bt.saved', m.name), this.i18n.t('common.done'));
    } catch (err) {
      this.toast.error(this.messageOf(err), this.i18n.t('error.title'));
    }
    await this.load();
  }

  private messageOf(err: unknown): string {
    return offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic'));
  }
}
