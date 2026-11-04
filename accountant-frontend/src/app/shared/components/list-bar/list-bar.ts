import { Component, EventEmitter, Input, Output, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { I18nService } from '../../../core/i18n.service';

/**
 * The strip above a data grid: "Showing 1–20 of 400" on the left (anything projected into it, such as a filter, sits beside it) and
 * Previous, numbered pages, Next on the right. The numbers are a window around the current page, so 400 rows never make 20 buttons.
 */
@Component({
  selector: 'app-list-bar',
  standalone: true,
  imports: [FormsModule],
  template: `
    <div class="list-bar">
      <span class="list-bar-count" data-testid="list-showing">{{ i18n.t('table.showing', '' + startIndex(), '' + endIndex(), '' + total) }}</span>
      @if (pageSizes.length) {
        <select class="list-size" [ngModel]="pageSize" (ngModelChange)="pageSizeChange.emit(+$event)" [attr.aria-label]="i18n.t('table.rows')" data-testid="list-size">
          @for (n of pageSizes; track n) { <option [value]="n">{{ n }}</option> }
        </select>
        <span class="text-sm font-semibold text-slate-500">{{ i18n.t('table.perpage') }}</span>
      }
      <ng-content />
      @if (totalPages() > 1) {
        <nav class="list-pager" [attr.aria-label]="i18n.t('table.rows')">
          <button type="button" class="pg" [disabled]="page <= 1" (click)="go(page - 1)">{{ i18n.t('table.prev') }}</button>
          @for (n of numbers(); track n) {
            <button type="button" class="pg" [class.is-current]="n === page" [attr.aria-current]="n === page ? 'page' : null" (click)="go(n)" [attr.data-testid]="'page-' + n">{{ n }}</button>
          }
          <button type="button" class="pg" [disabled]="page >= totalPages()" (click)="go(page + 1)">{{ i18n.t('table.next') }}</button>
        </nav>
      }
    </div>
  `,
})
export class ListBarComponent {
  protected readonly i18n = inject(I18nService);

  @Input() total = 0;
  @Input() page = 1;
  @Input() pageSize = 20;
  /** Offer a per-page choice (left empty, none is shown). */
  @Input() pageSizes: number[] = [];
  @Output() pageChange = new EventEmitter<number>();
  @Output() pageSizeChange = new EventEmitter<number>();

  totalPages(): number {
    return this.total > 0 ? Math.ceil(this.total / (this.pageSize || 20)) : 1;
  }

  startIndex(): number {
    return this.total ? (this.page - 1) * this.pageSize + 1 : 0;
  }

  endIndex(): number {
    return this.total ? Math.min(this.page * this.pageSize, this.total) : 0;
  }

  /** At most five page numbers, centred on the current page. */
  numbers(): number[] {
    const last = this.totalPages();
    const first = Math.max(1, Math.min(this.page - 2, last - 4));
    const to = Math.min(last, first + 4);
    const out: number[] = [];
    for (let n = first; n <= to; n++) out.push(n);

    return out;
  }

  go(n: number): void {
    if (n >= 1 && n <= this.totalPages() && n !== this.page) this.pageChange.emit(n);
  }
}
