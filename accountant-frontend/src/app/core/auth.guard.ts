import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { AuthService } from './auth.service';
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
