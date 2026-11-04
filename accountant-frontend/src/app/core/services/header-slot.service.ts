import { Injectable, TemplateRef, signal } from '@angular/core';

/**
 * A page can put its own controls (such as period tabs) in the breadcrumb row at the top of the page, next to where it says where you
 * are. The page gives its template with [show] and takes it back with [clear] when it goes away.
 */
@Injectable({ providedIn: 'root' })
export class HeaderSlotService {
  readonly template = signal<TemplateRef<unknown> | null>(null);

  show(template: TemplateRef<unknown>): void {
    this.template.set(template);
  }

  /** Only the page that put the template there may take it away, so a page that opens next is never emptied by the one leaving. */
  clear(template: TemplateRef<unknown>): void {
    if (this.template() === template) this.template.set(null);
  }
}
