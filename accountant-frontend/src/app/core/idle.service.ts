import { Location } from '@angular/common';
import { Injectable, NgZone, inject } from '@angular/core';

import { AuthService } from './auth.service';
import { ResumeService } from './resume.service';
import { TillService } from './till.service';

/** Ten minutes of doing nothing and the accountant is signed out (the screen may be left open on a shared computer). */
export const IDLE_LIMIT_MS = 10 * 60 * 1000;
const CHECK_MS = 15 * 1000;
const ACTIVITY_KEY = 'last_activity';
export const IDLE_NOTICE_KEY = 'idle_signed_out';
const EVENTS = ['mousemove', 'mousedown', 'keydown', 'scroll', 'touchstart', 'wheel', 'click'];

/**
 * Signs the person out after ten minutes without a touch of the mouse or keyboard. Before it does, it keeps where they were (the page, and
 * the sale in the till) so that signing in again carries on from there. Activity in another tab of the same browser counts too, and a
 * computer that was asleep for longer than the limit finds the person signed out when it wakes.
 */
@Injectable({ providedIn: 'root' })
export class IdleService {
  private readonly auth = inject(AuthService);
  private readonly till = inject(TillService);
  private readonly resume = inject(ResumeService);
  private readonly location = inject(Location);
  private readonly zone = inject(NgZone);

  private timer: ReturnType<typeof setInterval> | null = null;
  private last = Date.now();
  private lastWritten = 0;
  private readonly touch = (): void => this.touched();

  /** Begin watching (when the person is signed in and the app is showing). */
  start(): void {
    if (this.timer) return;
    this.last = Date.now();
    // Left alone longer than the limit before the page was even opened again (a closed laptop, a long night): out at once.
    const before = this.stored();
    if (before > 0 && Date.now() - before >= IDLE_LIMIT_MS) {
      this.expire();
      return;
    }
    this.write(true);
    this.zone.runOutsideAngular(() => {
      for (const e of EVENTS) window.addEventListener(e, this.touch, { passive: true, capture: true });
      this.timer = setInterval(() => this.check(), CHECK_MS);
    });
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    for (const e of EVENTS) window.removeEventListener(e, this.touch, true);
  }

  private touched(): void {
    this.last = Date.now();
    this.write(false);
  }

  /** The moment of the last activity is kept where other tabs can see it (written at most every five seconds). */
  private write(force: boolean): void {
    const now = Date.now();
    if (!force && now - this.lastWritten < 5000) return;
    this.lastWritten = now;
    try {
      localStorage.setItem(ACTIVITY_KEY, String(now));
    } catch {
      // the other tabs then cannot see it; this tab still watches its own
    }
  }

  private stored(): number {
    try {
      return Number(localStorage.getItem(ACTIVITY_KEY)) || 0;
    } catch {
      return 0;
    }
  }

  private check(): void {
    if (!this.auth.isLoggedIn()) return this.stop();
    const lastSeen = Math.max(this.last, this.stored());
    if (Date.now() - lastSeen >= IDLE_LIMIT_MS) this.zone.run(() => this.expire());
  }

  private expire(): void {
    this.stop();
    const user = this.auth.user();
    if (user) {
      const lines = this.till.snapshot();
      const progress = this.till.progressProvider?.() ?? '';
      this.resume.save(user.id, this.location.path() || '/', lines.length ? { lines, customer: this.till.customer(), progress } : null);
    }
    try {
      localStorage.setItem(IDLE_NOTICE_KEY, '1');
      localStorage.removeItem(ACTIVITY_KEY);
    } catch {
      // the sign-in page then does not say why
    }
    this.auth.logout();
  }
}
