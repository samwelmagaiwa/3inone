import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';

import { environment } from '../../environments/environment';
import { AuthService } from './auth.service';
import { I18nService } from './i18n.service';
import { ToastService } from './services/toast.service';

/**
 * For calls to our own API: send the token and the service, and when the server says the token is no good (401) sign out
 * and go to the sign-in page with a plain message. The sign-in call itself is left alone, so a wrong password shows its message.
 */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  if (!req.url.startsWith(environment.apiUrl)) return next(req);

  const auth = inject(AuthService);
  const router = inject(Router);
  const toast = inject(ToastService);
  const i18n = inject(I18nService);
  const token = auth.token();
  const authed = req.clone({
    setHeaders: {
      Accept: 'application/json',
      'X-Service': auth.service(),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  });

  return next(authed).pipe(
    catchError((err: HttpErrorResponse) => {
      // The business's plan ended and the server holds it back until it pays: cover the app once, not a string of errors.
      if (err.status === 402 && !req.url.endsWith('/auth/login') && (err.error?.errors?.code ?? err.error?.code) === 'subscription_expired') {
        auth.blocked.set(true);
      }
      if (err.status === 401 && !req.url.endsWith('/auth/login') && auth.isLoggedIn()) {
        auth.clear();
        toast.warning(i18n.t('session.expired'), i18n.t('session.expired.title'));
        void router.navigate(['/login']);
      }
      return throwError(() => err);
    }),
  );
};
