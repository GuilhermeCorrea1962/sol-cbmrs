import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { OAuthService } from 'angular-oauth2-oidc';

export const bearerInterceptor: HttpInterceptorFn = (req, next) => {
  const oauth = inject(OAuthService);
  const token = oauth.getAccessToken();
  const apiBase = window.location.origin + '/api';

  if (token && req.url.startsWith(apiBase)) {
    req = req.clone({ setHeaders: { Authorization: `Bearer ${token}` } });
  }
  return next(req);
};
