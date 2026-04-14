import { Component, OnInit, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatDividerModule } from '@angular/material/divider';
import { RelatorioService } from '../../../core/services/relatorio.service';
import { RelatorioResumoStatusResponse } from '../../../core/models/relatorio.model';
import { STATUS_COLOR } from '../../../core/models/licenciamento.model';

@Component({
  selector: 'sol-relatorios-menu',
  standalone: true,
  imports: [
    MatCardModule,
    MatButtonModule,
    MatIconModule,
    MatProgressSpinnerModule,
    MatDividerModule
  ],
  template: `
    <div class="relatorios-container">

      <h2 class="relatorios-title">Relatorios</h2>
      <p class="relatorios-subtitle">
        Painel de consultas e exportacoes para ADMIN e CHEFE_SSEG_BBM.
      </p>

      <mat-divider></mat-divider>

      <!-- Resumo por status (carregado do backend) -->
      <ng-container>
        @if (carregandoResumo()) {
          <div class="resumo-loading">
            <mat-spinner diameter="28"></mat-spinner>
            <span>Carregando resumo...</span>
          </div>
        } @else if (resumo()) {
          <div class="resumo-bloco">
            <p class="resumo-titulo">Resumo atual — {{ resumo()!.totalGeral }} licenciamento(s)</p>
            <div class="resumo-grid">
              @for (item of resumo()!.itens; track item.status) {
                <div class="resumo-card" [style.border-left]="'4px solid ' + corStatus(item.status)">
                  <div class="resumo-valor">{{ item.quantidade }}</div>
                  <div class="resumo-label">{{ item.label }}</div>
                </div>
              }
            </div>
          </div>
        }
      </ng-container>

      <mat-divider></mat-divider>

      <!-- Cards de relatorios disponíveis -->
      <div class="relatorios-grid">

        <!-- Relatorio ativo: Licenciamentos por Periodo -->
        <mat-card class="relatorio-card">
          <mat-card-header>
            <mat-icon mat-card-avatar color="primary">list_alt</mat-icon>
            <mat-card-title>Licenciamentos por Periodo</mat-card-title>
            <mat-card-subtitle>Filtros: datas, status, municipio, tipo</mat-card-subtitle>
          </mat-card-header>
          <mat-card-content>
            <p class="relatorio-descricao">
              Lista detalhada de licenciamentos com filtros avancados.
              Suporta exportacao em formato CSV.
            </p>
          </mat-card-content>
          <mat-card-actions>
            <button mat-flat-button color="primary" (click)="irParaLicenciamentos()">
              <mat-icon>open_in_new</mat-icon>
              Abrir Relatorio
            </button>
          </mat-card-actions>
        </mat-card>

        <!-- Placeholder: Vistorias Realizadas -->
        <mat-card class="relatorio-card relatorio-card--futuro">
          <mat-card-header>
            <mat-icon mat-card-avatar>event_available</mat-icon>
            <mat-card-title>Vistorias Realizadas</mat-card-title>
            <mat-card-subtitle>Disponivel em versao futura</mat-card-subtitle>
          </mat-card-header>
          <mat-card-content>
            <p class="relatorio-descricao">
              Historico de vistorias por inspetor, municipio e resultado.
            </p>
          </mat-card-content>
          <mat-card-actions>
            <button mat-stroked-button disabled>
              <mat-icon>schedule</mat-icon>
              Em breve
            </button>
          </mat-card-actions>
        </mat-card>

        <!-- Placeholder: APPCI Emitidos -->
        <mat-card class="relatorio-card relatorio-card--futuro">
          <mat-card-header>
            <mat-icon mat-card-avatar>verified</mat-icon>
            <mat-card-title>APPCI Emitidos</mat-card-title>
            <mat-card-subtitle>Disponivel em versao futura</mat-card-subtitle>
          </mat-card-header>
          <mat-card-content>
            <p class="relatorio-descricao">
              Alvaras emitidos por periodo, tipo de ocupacao e validade.
            </p>
          </mat-card-content>
          <mat-card-actions>
            <button mat-stroked-button disabled>
              <mat-icon>schedule</mat-icon>
              Em breve
            </button>
          </mat-card-actions>
        </mat-card>

        <!-- Placeholder: Pendencias Criticas -->
        <mat-card class="relatorio-card relatorio-card--futuro">
          <mat-card-header>
            <mat-icon mat-card-avatar>warning_amber</mat-icon>
            <mat-card-title>Pendencias Criticas</mat-card-title>
            <mat-card-subtitle>Disponivel em versao futura</mat-card-subtitle>
          </mat-card-header>
          <mat-card-content>
            <p class="relatorio-descricao">
              Licenciamentos com pendencias de longa data ou alvara vencido.
            </p>
          </mat-card-content>
          <mat-card-actions>
            <button mat-stroked-button disabled>
              <mat-icon>schedule</mat-icon>
              Em breve
            </button>
          </mat-card-actions>
        </mat-card>

      </div>
    </div>
  `,
  styles: [`
    .relatorios-container   { padding: 24px; max-width: 1200px; margin: 0 auto; }
    .relatorios-title       { margin: 0 0 4px; font-size: 1.6rem; font-weight: 600; }
    .relatorios-subtitle    { margin: 0 0 16px; color: #666; }
    .resumo-loading         { display: flex; align-items: center; gap: 12px;
                              padding: 16px 0; color: #666; }
    .resumo-bloco           { padding: 16px 0; }
    .resumo-titulo          { margin: 0 0 12px; font-size: 0.9rem; color: #555; }
    .resumo-grid            { display: flex; flex-wrap: wrap; gap: 10px; }
    .resumo-card            { padding: 10px 14px; background: #fafafa;
                              border-radius: 4px; min-width: 130px; }
    .resumo-valor           { font-size: 1.8rem; font-weight: 700; line-height: 1; }
    .resumo-label           { font-size: 0.76rem; color: #555; margin-top: 4px; }
    .relatorios-grid        { display: grid;
                              grid-template-columns: repeat(auto-fill, minmax(270px, 1fr));
                              gap: 20px; padding-top: 24px; }
    .relatorio-card         { transition: box-shadow 0.2s; }
    .relatorio-card:hover   { box-shadow: 0 4px 16px rgba(0,0,0,0.15); }
    .relatorio-card--futuro { opacity: 0.6; }
    .relatorio-descricao    { color: #555; font-size: 0.9rem;
                              min-height: 44px; margin: 8px 0 0; }
  `]
})
export class RelatoriosMenuComponent implements OnInit {

  private readonly svc    = inject(RelatorioService);
  private readonly router = inject(Router);

  readonly resumo           = signal<RelatorioResumoStatusResponse | null>(null);
  readonly carregandoResumo = signal(true);

  ngOnInit(): void {
    this.svc.getResumoStatus().subscribe({
      next:  r  => { this.resumo.set(r); this.carregandoResumo.set(false); },
      error: () => { this.carregandoResumo.set(false); }
    });
  }

  irParaLicenciamentos(): void {
    this.router.navigate(['/app/relatorios/licenciamentos']);
  }

  corStatus(status: string): string {
    return (STATUS_COLOR as Record<string, string>)[status] ?? '#9e9e9e';
  }
}
