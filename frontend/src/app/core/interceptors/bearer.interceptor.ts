import { HttpInterceptorFn } from '@angular/common/http';

export const bearerInterceptor: HttpInterceptorFn = (req, next) => {
  // Le diretamente do sessionStorage — mesmo storage configurado no app.config.ts.
  // angular-oauth2-oidc salva com a chave 'access_token'.
  const token = sessionStorage.getItem('access_token');

  if (token && req.url.includes('/api/')) {
    return next(req.clone({ setHeaders: { Authorization: `Bearer ${token}` } }));
  }
  return next(req);
};
