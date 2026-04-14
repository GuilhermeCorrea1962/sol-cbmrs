import { ApplicationConfig, provideZoneChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';
import { provideAnimationsAsync } from '@angular/platform-browser/animations/async';
import { OAuthStorage, provideOAuthClient } from 'angular-oauth2-oidc';

import { routes } from './app.routes';
import { environment } from '../environments/environment';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZoneChangeDetection({ eventCoalescing: true }),

    // Roteamento HTML5 (sem hash) — Nginx configurado com try_files $uri /index.html
    provideRouter(routes),

    // HttpClient — angular-oauth2-oidc injeta o token automaticamente
    // via OAuthModule.forRoot({ resourceServer: { sendAccessToken: true } })
    provideHttpClient(),

    // Angular Material: animacoes asincronas (melhor performance inicial)
    provideAnimationsAsync(),

    // Keycloak OIDC: token injetado automaticamente nas URLs em allowedUrls
    provideOAuthClient({
      resourceServer: {
        allowedUrls: [environment.apiUrl],
        sendAccessToken: true
      }
    }),

    // Tokens armazenados em sessionStorage: limpos ao fechar o navegador
    { provide: OAuthStorage, useValue: sessionStorage }
  ]
};
