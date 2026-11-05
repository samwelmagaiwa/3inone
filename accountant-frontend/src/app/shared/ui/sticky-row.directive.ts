import { Directive, ElementRef, OnDestroy, OnInit, inject } from '@angular/core';

/**
 * Put on a row that stays at the top of the page while it scrolls (the figure cards): it tells the page, as --stick-top, how tall it is,
 * so the header of a data grid below it (a `.fit-page` table) can stop right under it instead of sliding beneath it.
 */
@Directive({ selector: '[appStickyRow]', standalone: true })
export class StickyRowDirective implements OnInit, OnDestroy {
  private readonly el = inject<ElementRef<HTMLElement>>(ElementRef);
  private observer: ResizeObserver | null = null;

  ngOnInit(): void {
    const host = this.el.nativeElement;
    const page = host.parentElement;
    if (!page) return;
    const apply = () => page.style.setProperty('--stick-top', `${host.offsetHeight}px`);
    apply();
    if (typeof ResizeObserver !== 'undefined') {
      this.observer = new ResizeObserver(apply);
      this.observer.observe(host);
    }
  }

  ngOnDestroy(): void {
    this.observer?.disconnect();
    this.el.nativeElement.parentElement?.style.removeProperty('--stick-top');
  }
}
