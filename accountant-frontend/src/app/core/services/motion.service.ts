import { Injectable, signal } from '@angular/core';

/**
 * Lets a page replay its entrance animations (counting numbers, drawing charts) after a refresh,
 * not only when it first opens.
 */
@Injectable({ providedIn: 'root' })
export class MotionService {
  /** Changes every time something should animate again. */
  readonly tick = signal(0);

  replay(): void {
    this.tick.update(n => n + 1);
  }
}
