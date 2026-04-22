import { APP_INITIALIZER, ApplicationConfig, provideZoneChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';
import { provideAnimationsAsync } from '@angular/platform-browser/animations/async';
import { OAuthService, OAuthStorage, provideOAuthClient } from 'angular-oauth2-oidc';

import { routes } from './app.routes';
import { environment } from '../environments/environment';

function initializeOAuth(oauthService: OAuthService): () => Promise<void> {
  return async () => {
    oauthService.configure({
      issuer:               environment.keycloak.issuer,
      redirectUri:          environment.keycloak.redirectUri,
      clientId:             environment.keycloak.clientId,
      scope:                environment.keycloak.scope,
      responseType:         environment.keycloak.responseType,
      showDebugInformation: environment.keycloak.showDebugInformation,
      requireHttps:         environment.keycloak.requireHttps,
      clearHashAfterLogin:  environment.keycloak.clearHashAfterLogin
    });
    // Executa antes do roteamento para garantir que ?code= seja processado
    // antes que o Router navegue para outra rota e limpe a URL.
    try {
      await oauthService.loadDiscoveryDocumentAndTryLogin();
    } catch (e) {
      console.error('OIDC init error:', e);
    }
  };
}

export const appConfig: ApplicationConfig = {
  providers: [
    provideZoneChangeDetection({ eventCoalescing: true }),

    provideRouter(routes),

    provideHttpClient(),

    provideAnimationsAsync(),

    provideOAuthClient({
      resourceServer: {
        allowedUrls: [environment.apiUrl],
        sendAccessToken: true
      }
    }),

    { provide: OAuthStorage, useValue: sessionStorage },

    // APP_INITIALIZER garante que a troca do authorization_code ocorra
    // antes de qualquer navegacao do Router, evitando a corrida entre o
    // redirect do guard e o processamento do ?code= pelo angular-oauth2-oidc.
    {
      provide: APP_INITIALIZER,
      useFactory: initializeOAuth,
      deps: [OAuthService],
      multi: true
    }
  ]
};
