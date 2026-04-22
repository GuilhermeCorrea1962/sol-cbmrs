import { Component, OnInit, inject } from '@angular/core';
import { Router, RouterOutlet } from '@angular/router';
import { OAuthService } from 'angular-oauth2-oidc';

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
    // OIDC ja foi configurado e o code flow ja foi tentado no APP_INITIALIZER.
    // Aqui apenas habilitamos o refresh silencioso e navegamos para o dashboard
    // se o usuario ja tiver um token valido (retorno do Keycloak).
    this.oauthService.setupAutomaticSilentRefresh();

    if (this.oauthService.hasValidAccessToken()) {
      const url = this.router.url;
      if (url === '/' || url === '/login' || url.startsWith('/?') || url.startsWith('/#')) {
        this.router.navigate(['/app/dashboard']);
      }
    }
  }
}
