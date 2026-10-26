import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { AuthService } from './auth.service';
import { ServiceName } from './models';

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
 * A page for people with one of these rights (and, when named, working in that service). Anyone else is sent to the page they
 * do have, so a person who types or bookmarks an address they may not open lands somewhere useful, not on an error.
 * The server enforces the same rights; this only keeps the screens honest.
 */
export const canOpen = (options: { any: string[]; service?: ServiceName }): CanActivateFn => () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  const rightService = !options.service || auth.service() === options.service;
  if (rightService && auth.canAny(...options.any)) return true;

  return router.createUrlTree(['/welcome']);
};
