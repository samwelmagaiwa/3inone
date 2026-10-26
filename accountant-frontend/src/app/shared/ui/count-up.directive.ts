import { Directive, ElementRef, Input, OnChanges, OnDestroy, effect, inject, untracked } from '@angular/core';
import { MotionService } from '../../core/services/motion.service';

/**
 * Counts a number up from zero when it appears or changes, keeping any prefix or suffix:
 * <h3 [appCountUp]="'83.33%'"></h3> counts 0.00% to 83.33%.
 */
@Directive({ selector: '[appCountUp]', standalone: true })
export class CountUpDirective implements OnChanges, OnDestroy {
  @Input('appCountUp') value: string | number = '';

  private el = inject<ElementRef<HTMLElement>>(ElementRef);
  private motion = inject(MotionService);
  private frame = 0;
  private shown = 0;
  private firstTick = true;

  constructor() {
    // a refresh counts the figure up again from zero, even when the value did not change
    effect(() => {
      this.motion.tick();
      if (this.firstTick) { this.firstTick = false; return; }
      untracked(() => { this.shown = 0; this.ngOnChanges(); });
    });
  }

  ngOnChanges(): void {
    const text = String(this.value ?? '');
    const match = /^([^0-9-]*)(-?[0-9][0-9,]*(?:\.([0-9]+))?)(.*)$/.exec(text);
    const reduce = typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    if (!match || reduce || typeof requestAnimationFrame === 'undefined') {
      this.el.nativeElement.textContent = text;
      return;
    }

    const [, prefix, numeric, decimals = '', suffix] = match;
    const target = Number(numeric.replace(/,/g, ''));
    const places = decimals.length;
    const start = this.shown;
    const began = performance.now();
    const duration = 900;
    cancelAnimationFrame(this.frame);

    const step = (now: number) => {
      const t = Math.min(1, (now - began) / duration);
      const eased = 1 - Math.pow(1 - t, 3);
      this.shown = start + (target - start) * eased;
      this.el.nativeElement.textContent = prefix + this.shown.toFixed(places) + suffix;
      if (t < 1) this.frame = requestAnimationFrame(step);
      else {
        this.shown = target;
        this.el.nativeElement.textContent = text;
      }
    };
    this.frame = requestAnimationFrame(step);
  }

  ngOnDestroy(): void {
    cancelAnimationFrame(this.frame);
  }
}
