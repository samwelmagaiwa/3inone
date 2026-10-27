import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { AuthService } from '../../core/auth.service';
import { Branch, BranchesService } from '../../core/branches.service';
import { offline, serverMessage } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { ConfirmService } from '../../core/services/confirm.service';
import { MotionService } from '../../core/services/motion.service';
import { ToastService } from '../../core/services/toast.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';

/**
 * The places a business sells from, for a salon, a shop or a depot: add one, change it, switch it off (a branch with a history is never
 * deleted: it is switched off, so old figures keep their branch), and choose the one to look at. A business with one place needs none.
 * Everyone sees the list; only whoever may change settings (the owner) changes it, and the server checks that again.
 */
@Component({
  selector: 'app-branches',
  imports: [FormsModule, ModalDialogComponent],
  templateUrl: './branches.html',
})
export class BranchesPage implements OnInit {
  private readonly api = inject(BranchesService);
  private readonly toast = inject(ToastService);
  private readonly confirm = inject(ConfirmService);
  protected readonly auth = inject(AuthService);
  protected readonly i18n = inject(I18nService);
  protected readonly motion = inject(MotionService);
  protected readonly branches = inject(BranchesService);

  protected readonly canManage = computed(() => this.auth.can('inv_manage_settings'));
  protected readonly rows = signal<Branch[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);

  protected readonly formOpen = signal(false);
  protected readonly editing = signal<Branch | null>(null);
  protected name = '';
  protected address = '';
  protected phone = '';
  protected readonly formError = signal('');
  protected readonly saving = signal(false);

  ngOnInit(): void {
    void this.load();
  }

  protected async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      const list = await firstValueFrom(this.api.branches());
      this.rows.set(list);
      this.branches.list.set(list.filter((b) => b.active));
      // A branch chosen earlier that was switched off is no longer a choice.
      const chosen = this.branches.selected();
      if (chosen !== null && !list.some((b) => b.id === chosen && b.active)) this.branches.select(null);
    } catch (err) {
      this.error.set(this.messageOf(err));
    } finally {
      this.loading.set(false);
    }
  }

  protected look(id: number | null): void {
    this.branches.select(id);
    this.toast.success(this.i18n.t(id === null ? 'br.looking.all' : 'br.looking.one', this.branches.name() ?? ''), this.i18n.t('common.done'));
  }

  protected openForm(b: Branch | null): void {
    this.editing.set(b);
    this.name = b?.name ?? '';
    this.address = b?.address ?? '';
    this.phone = b?.phone ?? '';
    this.formError.set('');
    this.formOpen.set(true);
  }

  protected async save(): Promise<void> {
    if (this.name.trim().length < 2) return this.formError.set(this.i18n.t('br.err.name'));
    this.saving.set(true);
    this.formError.set('');
    try {
      await firstValueFrom(this.api.save(this.editing()?.id ?? null, { name: this.name.trim(), address: this.address.trim() || null, phone: this.phone.trim() || null }));
      this.toast.success(this.i18n.t('br.saved'), this.i18n.t('common.done'));
      this.formOpen.set(false);
      await this.load();
    } catch (err) {
      this.formError.set(this.messageOf(err));
    } finally {
      this.saving.set(false);
    }
  }

  protected async setActive(b: Branch, active: boolean): Promise<void> {
    try {
      await firstValueFrom(this.api.save(b.id, { name: b.name, address: b.address, phone: b.phone, active }));
      await this.load();
    } catch (err) {
      this.toast.error(this.messageOf(err), this.i18n.t('error.title'));
    }
  }

  protected async remove(b: Branch): Promise<void> {
    const yes = await this.confirm.ask({ title: this.i18n.t('br.delete.title'), message: this.i18n.t('br.delete.message', b.name), confirmLabel: this.i18n.t('common.delete'), cancelLabel: this.i18n.t('common.keep'), danger: true });
    if (!yes) return;
    try {
      await firstValueFrom(this.api.remove(b.id));
      this.toast.success(this.i18n.t('prod.deleted'), this.i18n.t('common.done'));
      await this.load();
    } catch (err) {
      this.toast.error(this.messageOf(err), this.i18n.t('error.title'));
    }
  }

  private messageOf(err: unknown): string {
    return offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic'));
  }
}
