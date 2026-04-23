import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { MatToolbarModule } from '@angular/material/toolbar';
import { MatSidenavModule } from '@angular/material/sidenav';
import { MatListModule } from '@angular/material/list';
import { MatIconModule } from '@angular/material/icon';
import { MatButtonModule } from '@angular/material/button';
import { MatMenuModule } from '@angular/material/menu';
import { MatDividerModule } from '@angular/material/divider';
import { MatTooltipModule } from '@angular/material/tooltip';
import { AuthService } from '../../core/services/auth.service';

interface NavItem {
  label: string;
  icon: string;
  route: string;
  roles: string[];
}

const NAV_ITEMS: NavItem[] = [
  { label: 'Painel',                icon: 'dashboard',      route: '/app/dashboard',         roles: [] },
  { label: 'Licenciamentos',        icon: 'folder_open',    route: '/app/licenciamentos',    roles: ['CIDADAO', 'ADMIN'] },
  { label: 'Fila de Analise',       icon: 'inbox',          route: '/app/analise',           roles: ['ANALISTA', 'CHEFE_SSEG_BBM'] },
  { label: 'Vistorias',             icon: 'search',         route: '/app/vistorias',         roles: ['INSPETOR', 'CHEFE_SSEG_BBM'] },
  { label: 'Usuarios',              icon: 'people',         route: '/app/usuarios',          roles: ['ADMIN'] },
  { label: 'Relatorios',            icon: 'bar_chart',      route: '/app/relatorios',        roles: ['ADMIN', 'CHEFE_SSEG_BBM'] },
];

@Component({
  selector: 'sol-shell',
  standalone: true,
  imports: [
    CommonModule,
    RouterOutlet,
    RouterLink,
    RouterLinkActive,
    MatToolbarModule,
    MatSidenavModule,
    MatListModule,
    MatIconModule,
    MatButtonModule,
    MatMenuModule,
    MatDividerModule,
    MatTooltipModule,
  ],
  template: `
    <mat-sidenav-container class="shell-container">

      <!-- Sidebar lateral -->
      <mat-sidenav #sidenav mode="side" opened class="shell-sidenav">
        <div class="sidenav-header">
          <span class="sidenav-logo">SOL</span>
          <span class="sidenav-subtitle">CBM-RS</span>
        </div>
        <mat-divider />

        <mat-nav-list>
          @for (item of visibleNavItems; track item.route) {
            <a mat-list-item
               [routerLink]="item.route"
               routerLinkActive="active-link"
               [matTooltip]="item.label"
               matTooltipPosition="right">
              <mat-icon matListItemIcon>{{ item.icon }}</mat-icon>
              <span matListItemTitle>{{ item.label }}</span>
            </a>
          }
        </mat-nav-list>
      </mat-sidenav>

      <!-- Conteudo principal -->
      <mat-sidenav-content class="shell-content">

        <!-- Toolbar superior -->
        <mat-toolbar color="primary" class="shell-toolbar">
          <span class="toolbar-spacer"></span>

          <!-- Menu de usuario -->
          <button mat-icon-button [matMenuTriggerFor]="userMenu"
                  [matTooltip]="userName">
            <mat-icon>account_circle</mat-icon>
          </button>

          <mat-menu #userMenu="matMenu">
            <div class="user-menu-header">
              <p class="user-menu-name">{{ userName }}</p>
              <p class="user-menu-roles">{{ userRolesLabel }}</p>
            </div>
            <mat-divider />
            <button mat-menu-item (click)="logout()">
              <mat-icon>logout</mat-icon>
              <span>Sair</span>
            </button>
          </mat-menu>
        </mat-toolbar>

        <!-- Area de conteudo roteado -->
        <div class="shell-body">
          <router-outlet />
        </div>

      </mat-sidenav-content>
    </mat-sidenav-container>
  `,
  styles: [`
    .shell-container {
      height: 100vh;
    }

    .shell-sidenav {
      width: 220px;
      background: #1a1a2e;
      color: #fff;

      /* Sobrescreve as CSS custom properties do MDC para texto branco no tema escuro */
      --mdc-list-list-item-label-text-color:        rgba(255, 255, 255, 0.85);
      --mdc-list-list-item-supporting-text-color:   rgba(255, 255, 255, 0.6);
      --mdc-list-list-item-leading-icon-color:      rgba(255, 255, 255, 0.85);
      --mdc-list-list-item-hover-label-text-color:  #fff;
      --mdc-list-list-item-focus-label-text-color:  #fff;
      --mdc-list-list-item-hover-leading-icon-color: #fff;
    }

    .sidenav-header {
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 24px 16px 16px;
    }

    .sidenav-logo {
      font-size: 32px;
      font-weight: 700;
      color: #fff;
      letter-spacing: 2px;
    }

    .sidenav-subtitle {
      font-size: 11px;
      color: rgba(255,255,255,.6);
      letter-spacing: 1px;
    }

    mat-nav-list a {
      border-radius: 4px;
      margin: 2px 8px;
    }

    mat-nav-list a:hover {
      background: rgba(255,255,255,.08);
    }

    mat-nav-list a.active-link {
      background: rgba(204,0,0,.7);
      --mdc-list-list-item-label-text-color:       #fff;
      --mdc-list-list-item-leading-icon-color:     #fff;
    }

    mat-nav-list mat-icon {
      color: inherit;
    }

    .shell-toolbar {
      position: sticky;
      top: 0;
      z-index: 100;
      box-shadow: 0 2px 4px rgba(0,0,0,.2);
    }

    .toolbar-spacer {
      flex: 1;
    }

    .shell-content {
      display: flex;
      flex-direction: column;
      background: #f5f5f5;
    }

    .shell-body {
      flex: 1;
      padding: 24px;
      overflow-y: auto;
    }

    .user-menu-header {
      padding: 12px 16px;
    }

    .user-menu-name {
      font-weight: 600;
      margin: 0 0 2px;
    }

    .user-menu-roles {
      font-size: 12px;
      color: #666;
      margin: 0;
    }
  `]
})
export class ShellComponent implements OnInit {

  private auth = inject(AuthService);
  private router = inject(Router);

  userName = '';
  userRolesLabel = '';
  visibleNavItems: NavItem[] = [];

  ngOnInit(): void {
    this.userName = this.auth.getUserName();
    const roles = this.auth.getUserRoles();
    this.userRolesLabel = roles.join(', ') || 'Sem perfil';
    this.visibleNavItems = NAV_ITEMS.filter(item =>
      item.roles.length === 0 || item.roles.some(r => roles.includes(r))
    );
  }

  logout(): void {
    this.auth.logout();
  }
}
