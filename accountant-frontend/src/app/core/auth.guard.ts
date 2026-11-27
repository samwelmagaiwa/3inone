import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { AuthService } from './auth.service';
import { GroupsContext } from './groups/groups-context.service';
import { NAV, NavItem, homePath, startPath } from './nav';

/** Only for people who are signed in; everyone else goes to the sign-in page. */
export const authGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  return auth.isLoggedIn() ? true : inject(Router).createUrlTree(['/login']);
};

/** The sign-in page is for people who are not signed in yet. */
export const noAuthGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  return auth.isLoggedIn() ? inject(Router).createUrlTree(['/']) : true;
};

/**
 * A page only for people who may open it (see nav.ts). Anyone else is sent to the first page they do have, so a person who types or
 * bookmarks an address they may not open lands somewhere useful, not on an error.
 */
export const canOpen = (key: NavItem['key']): CanActivateFn => () => {
  const auth = inject(AuthService);
  const item = NAV.find((n) => n.key === key);
  if (item?.allowed(auth)) return true;
  return inject(Router).createUrlTree([homePath(auth)]);
};

/**
 * A Groups (Vikundi) page: its rights come from the group, so they are loaded first (once), then the page opens for whoever holds them.
 * Anyone else goes to the Groups start page, which picks the first page they may open.
 */
export const groupsOpen = (key: NavItem['key']): CanActivateFn => async () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  if (auth.service() !== 'groups') return router.createUrlTree([homePath(auth)]);
  await inject(GroupsContext).ensure();
  return NAV.find((n) => n.key === key)?.allowed(auth) ? true : router.createUrlTree(['/welcome']);
};

/** "/groups": the first Groups page this person may open (after their group rights are loaded), else the "nothing here yet" page. */
export const groupsStart: CanActivateFn = async () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  await inject(GroupsContext).ensure();
  const first = NAV.find((n) => n.key.startsWith('g_') && n.allowed(auth));
  return router.createUrlTree([first?.path ?? '/welcome']);
};

/** The address "/" means "my first page". */
export const startPage: CanActivateFn = () => {
  const auth = inject(AuthService);
  return inject(Router).createUrlTree([startPath(auth)]);
};

/** The till: only for people who may ring up sales (the shop and the salon), else back to their first page. */
export const canSell: CanActivateFn = () => {
  const auth = inject(AuthService);
  return auth.can('inv_create_sales') ? true : inject(Router).createUrlTree([homePath(auth)]);
};
