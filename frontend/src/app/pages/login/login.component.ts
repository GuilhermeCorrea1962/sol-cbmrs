import { Component } from '@angular/core';
import { OAuthService } from 'angular-oauth2-oidc';
import { Router } from '@angular/router';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'sol-login',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="login-container">
      <div class="login-card">
        <div class="login-logo">
          <h1>SOL</h1>
          <p>Sistema Online de Licenciamento</p>
          <small>Corpo de Bombeiros Militar do RS</small>
        </div>
        <button class="btn-login" (click)="login()">
          Entrar com credenciais SOL
        </button>
        <p class="login-hint">
          Utilize o login e senha cadastrados no sistema SOL.
        </p>
      </div>
    </div>
  `,
  styles: [`
    .login-container {
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      background: #f5f5f5;
    }
    .login-card {
      background: white;
      border-radius: 8px;
      padding: 48px 40px;
      box-shadow: 0 2px 12px rgba(0,0,0,.15);
      text-align: center;
      max-width: 400px;
      width: 100%;
    }
    .login-logo h1 {
      font-size: 48px;
      color: #cc0000;
      font-weight: 700;
      margin-bottom: 4px;
    }
    .login-logo p {
      font-size: 16px;
      color: #333;
      margin-bottom: 4px;
    }
    .login-logo small {
      font-size: 12px;
      color: #666;
    }
    .btn-login {
      margin-top: 32px;
      width: 100%;
      padding: 14px;
      background: #cc0000;
      color: white;
      border: none;
      border-radius: 4px;
      font-size: 15px;
      font-weight: 600;
      cursor: pointer;
      transition: background .2s;
    }
    .btn-login:hover { background: #990000; }
    .login-hint {
      margin-top: 16px;
      font-size: 12px;
      color: #888;
    }
  `]
})
export class LoginComponent {

  constructor(private oauthService: OAuthService, private router: Router) {}

  login(): void {
    this.oauthService.initCodeFlow();
  }
}
