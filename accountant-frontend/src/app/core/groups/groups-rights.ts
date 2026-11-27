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

/**
 * ME: a leader looks at the group as an ordinary member. While on, every /groups call carries `X-Group-View: member` (the
 * interceptor adds it) and the server answers with no office rights and none of the leaders' lists, exactly as on the phone.
 */
export const groupViewAsMember = signal(false);

/** Does the signed-in person have a member record in the group (so "My account" has something to show)? */
export const groupHasMember = signal(false);
