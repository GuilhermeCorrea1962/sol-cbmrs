import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { MatCardModule } from '@angular/material/card';
import { MatTableModule } from '@angular/material/table';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatPaginatorModule, PageEvent } from '@angular/material/paginator';
import { MatTooltipModule } from '@angular/material/tooltip';
import { LicenciamentoService } from '../../../core/services/licenciamento.service';
import {
  LicenciamentoDTO,
  StatusLicenciamento,
  STATUS_LABEL,
  STATUS_COLOR
} from '../../../core/models/licenciamento.model';
import { LoadingComponent } from '../../../shared/components/loading/loading.component';
import { ErrorAlertComponent } from '../../../shared/components/error-alert/error-alert.component';

/**
 * Sprint F4 — Fila de Analise Tecnica
 *
 * Exibe a lista paginada de licenciamentos com status ANALISE_PENDENTE
 * e EM_ANALISE, ordenada por data de entrada (FIFO), para uso pelos
 * perfis ANALISTA e CHEFE_SSEG_BBM.
 *
 * Rota: /app/analise
 * Endpoint: GET /api/licenciamentos/fila-analise
 */
@Component({
  selector: 'sol-analise-fila',
  standalone: true,
  imports: [
    CommonModule,
    RouterLink,
    MatCardModule,
    MatTableModule,
    MatButtonModule,
    MatIconModule,
    MatPaginatorModule,
    MatTooltipModule,
    LoadingComponent,
    ErrorAlertComponent,
  ],
  template: `
    <sol-loading [show]="loading()" message="Carregando fila de analise..." />
    <sol-error-alert [message]="error()" (dismissed)="error.set(null)" />

    <div class="page-header">
      <h2>Fila de Analise Tecnica</h2>
      <p class="page-subtitle">
        Processos com status <strong>ANALISE_PENDENTE</strong> e <strong>EM_ANALISE</strong>
        — ordenados por data de entrada (FIFO)
      </p>
    </div>

    @if (!loading() && items().length === 0 && !error()) {
      <mat-card appearance="outlined" class="empty-card">
        <mat-card-content>
          <mat-icon class="empty-icon">done_all</mat-icon>
          <p>Nenhum processo na fila de analise no momento.</p>
        </mat-card-content>
      </mat-card>
    }

    @if (items().length > 0) {
      <mat-card appearance="outlined">
        <table mat-table [dataSource]="items()" class="fila-table">

          <!-- Coluna: Numero PPCI -->
          <ng-container matColumnDef="numero">
            <th mat-header-cell *matHeaderCellDef>Numero PPCI</th>
            <td mat-cell *matCellDef="let row">
              <span class="numero-ppci">{{ row.numeroPpci ?? 'Sem numero' }}</span>
            </td>
          </ng-container>

          <!-- Coluna: Tipo -->
          <ng-container matColumnDef="tipo">
            <th mat-header-cell *matHeaderCellDef>Tipo</th>
            <td mat-cell *matCellDef="let row">{{ row.tipo }}</td>
          </ng-container>

          <!-- Coluna: Status -->
          <ng-container matColumnDef="status">
            <th mat-header-cell *matHeaderCellDef>Status</th>
            <td mat-cell *matCellDef="let row">
              <span class="status-badge"
                    [style.background]="getStatusColor(row.status)">
                {{ getStatusLabel(row.status) }}
              </span>
            </td>
          </ng-container>

          <!-- Coluna: Municipio -->
          <ng-container matColumnDef="municipio">
            <th mat-header-cell *matHeaderCellDef>Municipio</th>
            <td mat-cell *matCellDef="let row">
              {{ row.endereco.municipio }}/{{ row.endereco.uf }}
            </td>
          </ng-container>

          <!-- Coluna: Area construida -->
          <ng-container matColumnDef="area">
            <th mat-header-cell *matHeaderCellDef>Area (m2)</th>
            <td mat-cell *matCellDef="let row">
              {{ row.areaConstruida | number:'1.0-0' }}
            </td>
          </ng-container>

          <!-- Coluna: Data de entrada na fila -->
          <ng-container matColumnDef="entrada">
            <th mat-header-cell *matHeaderCellDef>Entrada</th>
            <td mat-cell *matCellDef="let row">
              {{ row.dataCriacao | date:'dd/MM/yyyy' }}
            </td>
          </ng-container>

          <!-- Coluna: Acoes -->
          <ng-container matColumnDef="acoes">
            <th mat-header-cell *matHeaderCellDef></th>
            <td mat-cell *matCellDef="let row">
              <a mat-stroked-button color="primary"
                 [routerLink]="['/app/analise', row.id]"
                 matTooltip="Abrir tela de analise tecnica deste processo">
                <mat-icon>rate_review</mat-icon>
                Analisar
              </a>
            </td>
          </ng-container>

          <tr mat-header-row *matHeaderRowDef="colunas"></tr>
          <tr mat-row *matRowDef="let row; columns: colunas;"></tr>
        </table>

        <mat-paginator
          [length]="total()"
          [pageSize]="10"
          [pageSizeOptions]="[10, 25, 50]"
          (page)="onPage($event)"
          showFirstLastButtons>
        </mat-paginator>
      </mat-card>
    }
  `,
  styles: [`
    .page-header {
      margin-bottom: 24px;
    }
    .page-header h2 {
      margin: 0 0 4px;
      font-size: 20px;
      font-weight: 500;
      color: #333;
    }
    .page-subtitle {
      margin: 0;
      color: #666;
      font-size: 13px;
    }
    .empty-card {
      text-align: center;
      padding: 48px 24px;
    }
    .empty-icon {
      font-size: 48px;
      width: 48px;
      height: 48px;
      color: #b0bec5;
      display: block;
      margin: 0 auto 16px;
    }
    .fila-table {
      width: 100%;
    }
    .numero-ppci {
      font-family: monospace;
      font-size: 13px;
    }
    .status-badge {
      display: inline-block;
      padding: 3px 10px;
      border-radius: 12px;
      font-size: 12px;
      font-weight: 500;
      color: #fff;
      white-space: nowrap;
    }
  `]
})
export class AnaliseFilaComponent implements OnInit {

  private readonly svc = inject(LicenciamentoService);

  readonly colunas = ['numero', 'tipo', 'status', 'municipio', 'area', 'entrada', 'acoes'];

  items   = signal<LicenciamentoDTO[]>([]);
  total   = signal(0);
  loading = signal(false);
  error   = signal<string | null>(null);

  private page = 0;

  ngOnInit(): void {
    this.carregar();
  }

  onPage(event: PageEvent): void {
    this.page = event.pageIndex;
    this.carregar();
  }

  private carregar(): void {
    this.loading.set(true);
    this.svc.getFilaAnalise(this.page).subscribe({
      next: res => {
        this.items.set(res.content);
        this.total.set(res.totalElements);
        this.loading.set(false);
      },
      error: err => {
        this.error.set('Erro ao carregar a fila de analise. Verifique sua conexao e tente novamente.');
        this.loading.set(false);
        console.error(err);
      }
    });
  }

  getStatusLabel(s: StatusLicenciamento): string { return STATUS_LABEL[s] ?? s; }
  getStatusColor(s: StatusLicenciamento): string { return STATUS_COLOR[s] ?? '#9e9e9e'; }
}
