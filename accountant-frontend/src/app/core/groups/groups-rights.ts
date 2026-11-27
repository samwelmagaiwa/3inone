import { signal } from '@angular/core';

/**
 * The Groups (Vikundi) rights of the signed-in person, as /groups/me gives them (the office they hold; the business admin holds every
 * one). A plain signal, so the menu (nav.ts), the page guards and the buttons all follow it, and the menu redraws once it has loaded.
 * The server enforces the same rights on every call; this only keeps the screens honest.
 */
export const groupRights = signal<ReadonlySet<string>>(new Set());

/** Does the person hold any of these Groups rights? */
export function gCan(...rights: string[]): boolean {
  const held = groupRights();
  return rights.some((r) => held.has(r));
}
