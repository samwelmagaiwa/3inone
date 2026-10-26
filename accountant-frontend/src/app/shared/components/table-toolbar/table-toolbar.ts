import { Component, EventEmitter, Input, Output, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { I18nService } from '../../../core/i18n.service';

/**
 * Search and filter bar that sits above every table.
 * Filter controls (selects, date fields) are projected into the element body:
 *
 *   <app-table-toolbar placeholder="Search users…" [search]="query()" (searchChange)="query.set($event)"
 *                      [count]="rows().length" noun="user" [showClear]="hasFilters()" (cleared)="reset()">
 *     <label class="filter-field"><span>Status</span><select class="filter-select">…</select></label>
 *   </app-table-toolbar>
 */
@Component({
  selector: 'app-table-toolbar',
  standalone: true,
  imports: [FormsModule],
  template: `
    <div class="flex flex-wrap items-end gap-x-3 gap-y-3 px-5 py-4 border-b border-slate-100 bg-slate-50/60">
      @if (searchable) {
        <label class="filter-field grow basis-64 max-w-md">
          <span>{{ i18n.t('table.search') }}</span>
          <div class="relative">
            <svg class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
            <input type="text" class="filter-input" [ngModel]="search" (ngModelChange)="searchChange.emit($event)" [placeholder]="placeholder || i18n.t('table.search.placeholder')" autocomplete="off">
          </div>
        </label>
      }
      <ng-content />
      @if (showClear) {
        <button type="button" class="filter-clear" (click)="cleared.emit()">{{ i18n.t('table.clear') }}</button>
      }
      @if (count !== null) {
        <span class="ml-auto self-center text-[11px] font-extrabold text-slate-400 uppercase tracking-wide">{{ count }} {{ noun }}</span>
      }
    </div>
  `,
})
export class TableToolbarComponent {
  @Input() search = '';
  protected readonly i18n = inject(I18nService);

  /** Empty = the standard "search" hint in the current language. */
  @Input() placeholder = '';
  @Input() searchable = true;
  @Input() count: number | null = null;
  /** The counted thing, already in the right language and number ("3 debts" is count + noun). */
  @Input() noun = '';
  @Input() showClear = false;

  @Output() searchChange = new EventEmitter<string>();
  @Output() cleared = new EventEmitter<void>();
}
