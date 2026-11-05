import { Component, EventEmitter, Input, Output, inject } from '@angular/core';

import { I18nService } from '../../../core/i18n.service';
import { RECEIPT_SIZES, ReceiptSize, lastReceiptSize } from '../../../core/receipt';
import { ModalDialogComponent } from '../modal-dialog/modal-dialog';

/** "Print receipt": which paper is it for? A full page (A4), or a thermal printer's roll, 80 mm or 58 mm wide. The last choice is marked. */
@Component({
  selector: 'app-receipt-size',
  standalone: true,
  imports: [ModalDialogComponent],
  template: `
    <app-modal-dialog [show]="show" [title]="i18n.t('receipt.size.title')" [eyebrow]="i18n.t('receipt.print')" size="md" (close)="closed.emit()">
      <div slot="body" class="space-y-2">
        <p class="text-sm text-slate-500">{{ i18n.t('receipt.size.hint') }}</p>
        @for (s of sizes; track s) {
          <button type="button" class="size-opt" [class.is-last]="s === last()" (click)="picked.emit(s)" [attr.data-testid]="'receipt-size-' + s">
            <span class="size-ic" aria-hidden="true">
              @if (s === 'a4') {
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 2h9l5 5v15H6z"/><path d="M14 2v6h6M9 13h8M9 17h8"/></svg>
              } @else {
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 3h10v6H7zM5 9h14a2 2 0 012 2v6H3v-6a2 2 0 012-2zM7 15h10v6H7z"/></svg>
              }
            </span>
            <span class="grow text-left"><b>{{ i18n.t('receipt.size.' + s) }}</b><small>{{ i18n.t('receipt.size.' + s + '.hint') }}</small></span>
            @if (s === last()) { <span class="size-last">{{ i18n.t('receipt.size.last') }}</span> }
          </button>
        }
      </div>
      <div slot="footer" class="flex justify-end"><button type="button" class="modal-cancel-btn" (click)="closed.emit()">{{ i18n.t('common.cancel') }}</button></div>
    </app-modal-dialog>
  `,
  styles: [`
    .size-opt { display: flex; align-items: center; gap: 14px; width: 100%; padding: 12px 14px; border-radius: 14px; background: #fff; border: 1.5px solid #dbe4ff; cursor: pointer; transition: all .15s; }
    .size-opt:hover { background: #f3f6ff; border-color: #93b0fb; }
    .size-opt.is-last { border-color: #3b61e2; background: #f3f6ff; }
    .size-opt b { display: block; font-size: 14px; font-weight: 900; color: #1a2f6e; }
    .size-opt small { display: block; font-size: 12px; font-weight: 600; color: #64748b; }
    .size-ic { display: inline-flex; width: 42px; height: 42px; align-items: center; justify-content: center; border-radius: 12px; color: #3b61e2; background: #eaf0ff; }
    .size-last { font-size: 11px; font-weight: 800; color: #3b61e2; }
  `],
})
export class ReceiptSizeComponent {
  protected readonly i18n = inject(I18nService);
  protected readonly sizes = RECEIPT_SIZES;

  @Input() show = false;
  @Output() picked = new EventEmitter<ReceiptSize>();
  @Output() closed = new EventEmitter<void>();

  protected last(): ReceiptSize {
    return lastReceiptSize();
  }
}
