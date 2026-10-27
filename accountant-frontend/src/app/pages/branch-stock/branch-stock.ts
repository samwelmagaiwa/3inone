import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { firstValueFrom } from 'rxjs';

import { BranchStock, BranchStockRow, BranchTransfer, BranchesService } from '../../core/branches.service';
import { offline, serverMessage } from '../../core/format';
import { I18nService } from '../../core/i18n.service';
import { MotionService } from '../../core/services/motion.service';
import { ToastService } from '../../core/services/toast.service';
import { ModalDialogComponent } from '../../shared/components/modal-dialog/modal-dialog';
import { TableToolbarComponent } from '../../shared/components/table-toolbar/table-toolbar';

/**
 * Where the goods are: for each product the whole stock, what each branch holds and what is still in the main store, and moving goods
 * between them. The product's quantity is the business's whole stock; a branch holds a share of it, and what is not given to a branch is
 * in the main store. A sale in a branch takes from that branch's shelf first.
 */
@Component({
  selector: 'app-branch-stock',
  imports: [FormsModule, ModalDialogComponent, TableToolbarComponent],
  templateUrl: './branch-stock.html',
})
export class BranchStockPage implements OnInit {
  private readonly api = inject(BranchesService);
  private readonly toast = inject(ToastService);
  protected readonly i18n = inject(I18nService);
  protected readonly motion = inject(MotionService);

  protected readonly data = signal<BranchStock | null>(null);
  protected readonly moves = signal<BranchTransfer[]>([]);
  protected readonly loading = signal(true);
  protected readonly error = signal<string | null>(null);
  protected readonly query = signal('');

  protected readonly rows = computed(() => {
    const q = this.query().toLowerCase().trim();
    const all = this.data()?.products ?? [];

    return q ? all.filter((p) => p.name.toLowerCase().includes(q)) : all;
  });
  protected readonly noun = computed(() => this.i18n.t(this.rows().length === 1 ? 'prod.noun.one' : 'prod.noun.many'));

  // ---- moving goods
  protected readonly moveFor = signal<BranchStockRow | null>(null);
  protected from = '';
  protected to = '';
  protected qtyText = '';
  protected readonly moveError = signal('');
  protected readonly moving = signal(false);

  ngOnInit(): void {
    void this.load();
  }

  protected async load(): Promise<void> {
    this.loading.set(true);
    this.error.set(null);
    try {
      const [stock, moves] = await Promise.all([firstValueFrom(this.api.stock()), firstValueFrom(this.api.transfers())]);
      this.data.set(stock);
      this.moves.set(moves);
    } catch (err) {
      this.error.set(this.messageOf(err));
    } finally {
      this.loading.set(false);
    }
  }

  protected openMove(p: BranchStockRow): void {
    this.moveFor.set(p);
    this.from = 'main';
    this.to = '';
    this.qtyText = '';
    this.moveError.set('');
  }

  /** What is on the shelf the goods would be taken from. */
  protected available(p: BranchStockRow, from: string): number {
    if (from === 'main') return p.unallocated;

    return p.branches.find((b) => String(b.branch_id) === from)?.quantity ?? 0;
  }

  protected async move(): Promise<void> {
    const p = this.moveFor();
    if (!p) return;
    const qty = /^\d+$/.test(this.qtyText.trim()) ? Number(this.qtyText.trim()) : NaN;
    if (!this.to || this.to === this.from) return this.moveError.set(this.i18n.t('bs.err.place'));
    if (Number.isNaN(qty) || qty < 1) return this.moveError.set(this.i18n.t('bs.err.qty'));
    if (qty > this.available(p, this.from)) return this.moveError.set(this.i18n.t('bs.err.enough', this.available(p, this.from)));

    this.moving.set(true);
    this.moveError.set('');
    try {
      await firstValueFrom(
        this.api.transfer({ product_id: p.id, from_branch_id: this.from === 'main' ? null : Number(this.from), to_branch_id: this.to === 'main' ? null : Number(this.to), quantity: qty }),
      );
      this.toast.success(this.i18n.t('bs.moved'), this.i18n.t('common.done'));
      this.moveFor.set(null);
      await this.load();
    } catch (err) {
      this.moveError.set(this.messageOf(err));
    } finally {
      this.moving.set(false);
    }
  }

  private messageOf(err: unknown): string {
    return offline(err) ? this.i18n.t('error.offline') : (serverMessage(err) ?? this.i18n.t('error.generic'));
  }
}
