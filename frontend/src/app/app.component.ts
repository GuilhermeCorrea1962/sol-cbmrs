import { Component, OnInit, inject } from '@angular/core';
import { Router, RouterOutlet } from '@angular/router';
import { OAuthService } from 'angular-oauth2-oidc';
import { environment } from '../environments/environment';

@Component({
  selector: 'sol-root',
  standalone: true,
  imports: [RouterOutlet],
  template: `<router-outlet />`
})
export class AppComponent implements OnInit {

  private readonly oauthService = inject(OAuthService);
  private readonly router = inject(Router);

  ngOnInit(): void {
    this.configureOAuth();
  }

  private configureOAuth(): void {
    this.oauthService.configure({
      issuer:               environment.keycloak.issuer,
      redirectUri:          environment.keycloak.redirectUri,
      clientId:             environment.keycloak.clientId,
      scope:                environment.keycloak.scope,
      responseType:         environment.keycloak.responseType,
      showDebugInformation: environment.keycloak.showDebugInformation,
      requireHttps:         environment.keycloak.requireHttps,
      clearHashAfterLogin:  environment.keycloak.clearHashAfterLogin
    });

    this.oauthService.setupAutomaticSilentRefresh();

    // Tenta trocar o authorization_code recebido do Keycloak por um access_token.
    // Apos sucesso, navega para o dashboard. Se nao houver token, aguarda
    // que o usuario acesse /login e clique em "Entrar".
    this.oauthService.loadDiscoveryDocumentAndTryLogin().then(() => {
      if (this.oauthService.hasValidAccessToken()) {
        const url = this.router.url;
        if (url === '/' || url === '/login' || url.startsWith('/?') || url.startsWith('/#')) {
          this.router.navigate(['/app/dashboard']);
        }
      }
    });
  }
}
