import { Component, OnInit } from '@angular/core';
import { OAuthService } from 'angular-oauth2-oidc';
import { Router } from '@angular/router';
import { CommonModule } from '@angular/common';
import { LoginComponent } from '../login/login.component';

@Component({
  selector: 'sol-home',
  standalone: true,
  imports: [CommonModule, LoginComponent],
  template: `
    <div *ngIf="isLoggedIn; else notLogged">
      <h2>Bem-vindo ao SOL, {{ userName }}</h2>
      <p>Perfil: {{ userRoles.join(', ') }}</p>
      <button (click)="logout()">Sair</button>
    </div>
    <ng-template #notLogged>
      <sol-login></sol-login>
    </ng-template>
  `
})
export class HomeComponent implements OnInit {

  isLoggedIn = false;
  userName = '';
  userRoles: string[] = [];

  constructor(private oauthService: OAuthService, private router: Router) {}

  ngOnInit(): void {
    this.isLoggedIn = this.oauthService.hasValidAccessToken();
    if (!this.isLoggedIn) {
      this.router.navigate(['/login']);
      return;
    }
    const claims = this.oauthService.getIdentityClaims() as any;
    this.userName = claims?.name || claims?.preferred_username || '';
    this.userRoles = claims?.roles || [];
  }

  logout(): void {
    this.oauthService.logOut();
  }
}
