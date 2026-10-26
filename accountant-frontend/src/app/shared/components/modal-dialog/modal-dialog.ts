import { Component, Input, Output, EventEmitter } from '@angular/core';

@Component({
  selector: 'app-modal-dialog',
  standalone: true,
  template: `
    @if (show) {
      <div class="modal-backdrop" (click)="onClose()">
        <div class="modal-panel" [class]="panelSizeClass" (click)="$event.stopPropagation()">
          
          <div class="modal-header" [class]="headerVariantClass">
            <div>
              @if (eyebrow) {
                <p class="text-[10px] font-black uppercase tracking-widest text-blue-200">{{ eyebrow }}</p>
              }
              <h3 class="text-white font-extrabold text-lg tracking-tight mt-0.5">{{ title }}</h3>
            </div>
            <button (click)="onClose()" class="modal-close-btn" aria-label="Close modal">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/></svg>
            </button>
          </div>

          <div class="modal-body">
            <ng-content select="[slot=body]"></ng-content>
          </div>

          <div class="modal-footer">
            <ng-content select="[slot=footer]"></ng-content>
          </div>

        </div>
      </div>
    }
  `,
})
export class ModalDialogComponent {
  @Input() show: boolean = false;
  @Input() title: string = '';
  @Input() eyebrow?: string;
  @Input() size: 'sm' | 'md' | 'lg' = 'sm';
  @Input() variant: 'primary' | 'indigo' | 'danger' | 'teal' = 'primary';

  @Output() close = new EventEmitter<void>();

  onClose() {
    this.close.emit();
  }

  get panelSizeClass(): string {
    if (this.size === 'lg') return 'modal-panel-lg';
    if (this.size === 'md') return 'modal-panel-md';
    return 'modal-panel-sm';
  }

  get headerVariantClass(): string {
    switch (this.variant) {
      case 'indigo': return 'modal-header-indigo';
      case 'danger': return 'modal-header-danger';
      case 'teal':   return 'modal-header-teal';
      default:       return '';
    }
  }
}
