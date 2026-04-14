import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { AuthService } from '../../core/services/auth.service';

interface DashboardCard {
  title: string;
  description: string;
  icon: string;
  route: string;
  color: string;
}

@Component({
  selector: 'sol-dashboard',
  standalone: true,
  imports: [CommonModule, RouterLink, MatCardModule, MatButtonModule, MatIconModule],
  template: `
    <div class="dashboard-header">
      <h1 class="dashboard-title">Bem-vindo, {{ userName }}</h1>
      <p class="dashboard-subtitle">{{ greeting }}</p>
    </div>

    <div class="dashboard-grid">
      @for (card of cards; track card.route) {
        <mat-card class="dashboard-card" appearance="outlined">
          <mat-card-header>
            <div class="card-icon-wrapper" [style.background]="card.color">
              <mat-icon class="card-icon">{{ card.icon }}</mat-icon>
            </div>
          </mat-card-header>
          <mat-card-content>
            <h2 class="card-title">{{ card.title }}</h2>
            <p class="card-desc">{{ card.description }}</p>
          </mat-card-content>
          <mat-card-actions align="end">
            <a mat-button color="primary" [routerLink]="card.route">
              Acessar
            </a>
          </mat-card-actions>
        </mat-card>
      }
    </div>
  `,
  styles: [`
    .dashboard-header {
      margin-bottom: 32px;
    }

    .dashboard-title {
      font-size: 24px;
      font-weight: 600;
      color: #1a1a2e;
      margin: 0 0 4px;
    }

    .dashboard-subtitle {
      font-size: 14px;
      color: #666;
      margin: 0;
    }

    .dashboard-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
      gap: 20px;
    }

    .dashboard-card {
      cursor: default;
      transition: box-shadow .2s;
    }

    .dashboard-card:hover {
      box-shadow: 0 4px 16px rgba(0,0,0,.12);
    }

    .card-icon-wrapper {
      width: 48px;
      height: 48px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      margin-bottom: 8px;
    }

    .card-icon {
      color: #fff;
      font-size: 24px;
      width: 24px;
      height: 24px;
    }

    .card-title {
      font-size: 16px;
      font-weight: 600;
      color: #1a1a2e;
      margin: 0 0 6px;
    }

    .card-desc {
      font-size: 13px;
      color: #666;
      margin: 0;
      line-height: 1.5;
    }
  `]
})
export class DashboardComponent implements OnInit {

  private auth = inject(AuthService);

  userName = '';
  greeting = '';
  cards: DashboardCard[] = [];

  ngOnInit(): void {
    this.userName = this.auth.getUserName();
    this.greeting = this.buildGreeting();
    this.cards = this.buildCards();
  }

  private buildGreeting(): string {
    const roles = this.auth.getUserRoles();
    if (roles.includes('ADMIN')) return 'Voce esta acessando como Administrador do sistema SOL.';
    if (roles.includes('CHEFE_SSEG_BBM')) return 'Voce esta acessando como Chefe SSEG/BBM.';
    if (roles.includes('ANALISTA')) return 'Voce esta acessando como Analista tecnico.';
    if (roles.includes('INSPETOR')) return 'Voce esta acessando como Inspetor de vistoria.';
    return 'Voce esta acessando como Cidadao / Responsavel Tecnico.';
  }

  private buildCards(): DashboardCard[] {
    const roles = this.auth.getUserRoles();
    const cards: DashboardCard[] = [];

    if (roles.includes('CIDADAO') || roles.length === 0) {
      cards.push({
        title: 'Meus Licenciamentos',
        description: 'Acompanhe o status dos seus processos de licenciamento PPCI e PSPCIM.',
        icon: 'folder_open',
        route: '/app/licenciamentos',
        color: '#3498db'
      });
    }

    if (roles.includes('ANALISTA') || roles.includes('CHEFE_SSEG_BBM')) {
      cards.push({
        title: 'Fila de Analise',
        description: 'Licenciamentos aguardando analise tecnica distribuidos para voce.',
        icon: 'inbox',
        route: '/app/analise',
        color: '#cc0000'
      });
    }

    if (roles.includes('INSPETOR') || roles.includes('CHEFE_SSEG_BBM')) {
      cards.push({
        title: 'Vistorias',
        description: 'Vistorias presenciais agendadas e pendentes de realizacao.',
        icon: 'search',
        route: '/app/vistorias',
        color: '#27ae60'
      });
    }

    if (roles.includes('ADMIN')) {
      cards.push(
        {
          title: 'Gestao de Usuarios',
          description: 'Gerencie contas de usuarios e atribuicoes de perfil no sistema.',
          icon: 'people',
          route: '/app/usuarios',
          color: '#8e44ad'
        },
        {
          title: 'Relatorios',
          description: 'Visualize estatisticas e relatorios gerenciais do sistema SOL.',
          icon: 'bar_chart',
          route: '/app/relatorios',
          color: '#e67e22'
        }
      );
    }

    return cards;
  }
}
