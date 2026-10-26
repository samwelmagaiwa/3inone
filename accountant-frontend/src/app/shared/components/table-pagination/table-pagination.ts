import { Component, Input, Output, EventEmitter } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { BsSelectDirective } from '../../ui/bs-select.directive';

/** Footer shared by every table: rows-per-page selector, "1–10 of 42" range and Prev / Next buttons. */
@Component({
  selector: 'app-table-pagination',
  standalone: true,
  imports: [FormsModule, BsSelectDirective],
  styles: `
    :host { display: block; }
    .pager-box {
      margin: 14px 16px 16px;
      padding: 10px 16px;
      background: #ffffff;
      border: 1px solid #e2e8f0;
      border-radius: 10px;
    }
  `,
  template: `
    <div class="pager-box flex flex-wrap items-center justify-between gap-3">
      <div class="flex items-center gap-2">
        <span class="uppercase text-[10px] tracking-wider text-slate-400 font-bold">Rows per page</span>
        <select [ngModel]="pageSize" (ngModelChange)="onPageSizeChange(+$event)"
          class="bg-white border border-slate-200 px-2 py-1 text-xs font-bold text-slate-800 outline-none cursor-pointer rounded-md">
          @for (opt of pageSizeOptions; track opt) {
            <option [value]="opt">{{ opt }}</option>
          }
        </select>
      </div>

      <span class="font-bold text-slate-500 text-xs">{{ startIndex() }}–{{ endIndex() }} of {{ totalItems }}</span>

      <div class="flex items-center gap-2">
        <button (click)="goToPage(page - 1)" [disabled]="page <= 1"
          class="px-3.5 py-1.5 text-[10px] font-extrabold uppercase bg-white border border-slate-200 text-slate-500 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer transition-all hover:border-[#1a2f6e] hover:text-[#1a2f6e] rounded-md">
          Prev
        </button>
        <button (click)="goToPage(page + 1)" [disabled]="page >= totalPages()"
          class="px-3.5 py-1.5 text-[10px] font-extrabold uppercase bg-white border border-slate-200 text-slate-500 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer transition-all hover:border-[#1a2f6e] hover:text-[#1a2f6e] rounded-md">
          Next
        </button>
      </div>
    </div>
  `
})
export class TablePaginationComponent {
  @Input() totalItems: number = 0;
  @Input() page: number = 1;
  @Input() pageSize: number = 10;
  @Input() pageSizeOptions: number[] = [5, 10, 25, 50];

  @Output() pageChange = new EventEmitter<number>();
  @Output() pageSizeChange = new EventEmitter<number>();

  // Inputs are plain fields, so these are methods (a computed() would cache the first value forever).
  totalPages(): number {
    if (!this.totalItems || this.totalItems <= 0) return 1;
    return Math.ceil(this.totalItems / (this.pageSize || 10));
  }

  startIndex(): number {
    if (!this.totalItems) return 0;
    return (this.page - 1) * this.pageSize + 1;
  }

  endIndex(): number {
    if (!this.totalItems) return 0;
    return Math.min(this.page * this.pageSize, this.totalItems);
  }

  goToPage(newPage: number) {
    if (newPage < 1 || newPage > this.totalPages()) return;
    this.pageChange.emit(newPage);
  }

  onPageSizeChange(newSize: number) {
    this.pageSizeChange.emit(newSize);
    this.pageChange.emit(1);
  }
}
