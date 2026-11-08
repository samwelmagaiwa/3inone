import { Injectable } from '@angular/core';

import { Customer } from './till.models';

const KEY = 'resume_state';
/** A saved place is kept for half a day: after that the person simply starts at their first page. */
const KEEP_MS = 12 * 60 * 60 * 1000;

/** The sale that was being rung up when the person was signed out: the cart, the customer and how far the popup had got. */
export interface TillDraft {
  lines: unknown[];
  customer: Customer | null;
  /** The popup's own progress (step and payment details), as the page writes it. */
  progress: string;
}

interface Saved {
  userId: string;
  url: string;
  at: number;
  till: TillDraft | null;
}

/**
 * Where the person had got to when they were signed out for doing nothing: the page they were on and, in the till, the sale they were
 * making. When the same person signs in again they carry on from there (the data itself is on the server, so it is all still there).
 */
@Injectable({ providedIn: 'root' })
export class ResumeService {
  private state: Saved | null = this.read();

  private read(): Saved | null {
    try {
      const raw = localStorage.getItem(KEY);
      const s = raw ? (JSON.parse(raw) as Saved) : null;

      return s && typeof s.userId === 'string' && typeof s.url === 'string' && Date.now() - s.at < KEEP_MS ? s : null;
    } catch {
      return null;
    }
  }

  private write(): void {
    try {
      if (this.state) localStorage.setItem(KEY, JSON.stringify(this.state));
      else localStorage.removeItem(KEY);
    } catch {
      // not kept: the person starts at their first page
    }
  }

  save(userId: string, url: string, till: TillDraft | null): void {
    this.state = { userId, url, at: Date.now(), till };
    this.write();
  }

  /** The page to go back to for this person (once); someone else signing in finds nothing and the saved place is dropped. */
  takeUrl(userId: string): string | null {
    this.state = this.state ?? this.read();
    if (!this.state) return null;
    if (this.state.userId !== userId) {
      this.state = null;
      this.write();

      return null;
    }
    const url = this.state.url;
    this.state = this.state.till ? { ...this.state, url: '' } : null;
    this.write();

    return url || null;
  }

  /** The sale that was being made for this person (once). */
  takeTill(userId: string): TillDraft | null {
    this.state = this.state ?? this.read();
    if (!this.state || this.state.userId !== userId || !this.state.till) return null;
    const till = this.state.till;
    this.state = this.state.url ? { ...this.state, till: null } : null;
    this.write();

    return till;
  }
}
