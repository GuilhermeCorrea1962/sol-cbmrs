import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';

@Component({
  selector: 'sol-not-found',
  standalone: true,
  imports: [RouterLink, MatButtonModule, MatIconModule],
  template: `
    <div class="not-found-container">
      <mat-icon class="not-found-icon">find_in_page</mat-icon>
      <h1 class="not-found-code">404</h1>
      <h2 class="not-found-title">Pagina nao encontrada</h2>
      <p class="not-found-msg">
        O endereco solicitado nao existe ou voce nao tem permissao para acessa-lo.
      </p>
      <a mat-raised-button color="primary" routerLink="/app/dashboard">
        Voltar ao painel
      </a>
    </div>
  `,
  styles: [`
    .not-found-container {
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 80vh;
      text-align: center;
      padding: 32px;
    }

    .not-found-icon {
      font-size: 72px;
      width: 72px;
      height: 72px;
      color: #ccc;
      margin-bottom: 16px;
    }

    .not-found-code {
      font-size: 80px;
      font-weight: 700;
      color: #cc0000;
      margin: 0 0 8px;
      line-height: 1;
    }

    .not-found-title {
      font-size: 22px;
      font-weight: 600;
      color: #333;
      margin: 0 0 12px;
    }

    .not-found-msg {
      font-size: 14px;
      color: #666;
      max-width: 400px;
      margin: 0 0 32px;
      line-height: 1.6;
    }
  `]
})
export class NotFoundComponent {}
