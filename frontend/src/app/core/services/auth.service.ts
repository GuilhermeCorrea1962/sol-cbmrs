import { Injectable, inject } from '@angular/core';
import { Router } from '@angular/router';
import { OAuthService } from 'angular-oauth2-oidc';

export type SolRole =
  | 'CIDADAO'
  | 'ANALISTA'
  | 'INSPETOR'
  | 'ADMIN'
  | 'CHEFE_SSEG_BBM';

@Injectable({ providedIn: 'root' })
export class AuthService {

  private readonly oauthService = inject(OAuthService);
  private readonly router = inject(Router);

  isLoggedIn(): boolean {
    return this.oauthService.hasValidAccessToken();
  }

  login(): void {
    this.oauthService.initCodeFlow();
  }

  logout(): void {
    this.oauthService.logOut();
  }

  getUserName(): string {
    const claims = this.oauthService.getIdentityClaims() as Record<string, unknown>;
    return (claims?.['name'] ?? claims?.['preferred_username'] ?? '') as string;
  }

  /**
   * Extrai os realm roles do access token JWT do Keycloak.
   * O Keycloak publica os roles em: payload.realm_access.roles
   */
  getUserRoles(): string[] {
    const token = this.oauthService.getAccessToken();
    if (!token) return [];
    try {
      // Decodifica o payload do JWT (parte central, Base64URL)
      const padded = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
      const payload = JSON.parse(atob(padded)) as Record<string, unknown>;
      const realmAccess = payload['realm_access'] as { roles?: string[] } | undefined;
      return realmAccess?.roles ?? [];
    } catch {
      return [];
    }
  }

  hasRole(role: SolRole): boolean {
    return this.getUserRoles().includes(role);
  }

  hasAnyRole(roles: SolRole[]): boolean {
    const userRoles = this.getUserRoles();
    return roles.some(r => userRoles.includes(r));
  }

  getAccessToken(): string {
    return this.oauthService.getAccessToken();
  }

  /** Navega para o dashboard ap\u00f3s login bem-sucedido. */
  navigateAfterLogin(): void {
    this.router.navigate(['/app/dashboard']);
  }
}
