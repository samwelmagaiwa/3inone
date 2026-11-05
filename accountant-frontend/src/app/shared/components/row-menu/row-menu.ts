import { Component, EventEmitter, Input, Output, inject, signal } from '@angular/core';

import { I18nService } from '../../../core/i18n.service';

/** One line of a menu: what it says, and how it looks. `id` comes back when it is chosen. */
export interface MenuItem {
  id: string;
  label: string;
  /** The main action of the menu: drawn in green. */
  primary?: boolean;
  danger?: boolean;
  disabled?: boolean;
  /** A link instead of an action (opens that address in a new tab). */
  href?: string;
  testid?: string;
}

/**
 * The three dots at the end of a row (or a labelled button) that opens a small menu of actions. The menu is drawn where the button is,
 * over the page, upward when the button is near the bottom of the window, so a scrolling table never cuts it off.
 */
@Component({
  selector: 'app-row-menu',
  standalone: true,
  template: `
    @if (label) {
      <button type="button" class="menu-label-btn" (click)="toggle($event)" aria-haspopup="menu" [attr.aria-expanded]="!!open()" [attr.data-testid]="testid">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12m0 0l-4-4m4 4l4-4M4 17v3h16v-3"/></svg>
        {{ label }}
      </button>
    } @else {
      <button type="button" class="dots-btn" (click)="toggle($event)" [attr.aria-label]="i18n.t('prod.col.actions')" aria-haspopup="menu" [attr.aria-expanded]="!!open()" [attr.data-testid]="testid">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="5" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="12" cy="19" r="1.8"/></svg>
      </button>
    }
    @if (open(); as m) {
      <div class="menu-backdrop" (click)="open.set(null)"></div>
      <div class="row-menu" role="menu" [style.top.px]="m.top" [style.bottom.px]="m.bottom" [style.right.px]="m.right" data-testid="row-menu">
        @for (it of items; track it.id) {
          @if (it.href) {
            <a role="menuitem" class="row-menu-item" [href]="it.href" target="_blank" rel="noopener" (click)="open.set(null)" [attr.data-testid]="it.testid">{{ it.label }}</a>
          } @else {
            <button type="button" role="menuitem" class="row-menu-item" [class.is-primary]="it.primary" [class.is-danger]="it.danger" [disabled]="it.disabled" (click)="pick(it)" [attr.data-testid]="it.testid">{{ it.label }}</button>
          }
        }
      </div>
    }
  `,
  styles: [`
    :host { display: inline-block; }
    .dots-btn { display: inline-flex; width: 34px; height: 34px; align-items: center; justify-content: center; border-radius: 10px; color: #475a8f; background: #fff; border: 1px solid #dbe4ff; cursor: pointer; }
    .dots-btn:hover { background: #f3f5ff; border-color: #93b0fb; }
    .menu-label-btn { display: inline-flex; align-items: center; gap: 7px; padding: 8px 14px; border-radius: 12px; font-size: 13px; font-weight: 800; color: #1a2f6e; background: #fff; border: 1px solid #dbe4ff; cursor: pointer; }
    .menu-label-btn:hover { background: #f3f5ff; border-color: #93b0fb; }
    .menu-backdrop { position: fixed; inset: 0; z-index: 70; }
    .row-menu { position: fixed; z-index: 71; min-width: 200px; padding: 6px; border-radius: 14px; background: #fff; border: 1px solid #dbe4ff; box-shadow: 0 18px 40px -16px rgba(26, 47, 110, .45); display: flex; flex-direction: column; text-align: left; }
    .row-menu-item { display: block; width: 100%; padding: 10px 14px; border-radius: 10px; text-align: left; font-size: 13px; font-weight: 800; color: #1a2f6e; background: transparent; border: 0; cursor: pointer; }
    .row-menu-item:hover:not(:disabled) { background: #f1f5ff; }
    .row-menu-item.is-primary { color: #15803d; }
    .row-menu-item.is-danger { color: #dc2626; }
    .row-menu-item:disabled { opacity: .45; cursor: not-allowed; }
  `],
})
export class RowMenuComponent {
  protected readonly i18n = inject(I18nService);

  @Input() items: MenuItem[] = [];
  /** With a label the button is a named one (with a download arrow); without, it is the three dots. */
  @Input() label = '';
  @Input() testid = '';
  @Output() picked = new EventEmitter<string>();

  protected readonly open = signal<{ top: number | null; bottom: number | null; right: number } | null>(null);

  protected toggle(ev: Event): void {
    if (this.open()) return this.open.set(null);
    const r = (ev.currentTarget as HTMLElement).getBoundingClientRect();
    const need = this.items.length * 42 + 20;
    const up = typeof window !== 'undefined' && r.bottom + need > window.innerHeight;
    const width = typeof window !== 'undefined' ? window.innerWidth : 0;
    this.open.set({ top: up ? null : r.bottom + 4, bottom: up ? window.innerHeight - r.top + 4 : null, right: Math.max(8, width - r.right) });
  }

  protected pick(it: MenuItem): void {
    this.open.set(null);
    this.picked.emit(it.id);
  }
}
