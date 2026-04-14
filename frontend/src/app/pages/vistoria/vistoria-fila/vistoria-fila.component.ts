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
 * Sprint F5 -- Fila de Vistoria Presencial (P07).
 *
 * Lista paginada de processos aguardando ou em andamento de vistoria presencial,
 * acessivel exclusivamente a INSPETOR e CHEFE_SSEG_BBM.
 *
 * Exibe processos com status: VISTORIA_PENDENTE, EM_VISTORIA, EM_VISTORIA_RENOVACAO.
 * Ordenacao FIFO por dataCriacao (mais antigo primeiro), conforme RTCBMRS N.01/2024.
 *
 * Rota: /app/vistorias
 * Endpoint: GET /api/licenciamentos/fila-vistoria?page=&size=&sort=dataCriacao,asc
 */
@Component({
  selector: 'sol-vistoria-fila',
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
    <sol-loading [show]="loading()" message="Carregando fila de vistoria..." />
    <sol-error-alert [message]="error()" (dismissed)="error.set(null)" />

    <mat-card appearance="outlined">
      <mat-card-header>
        <mat-card-title>Fila de Vistoria Presencial</mat-card-title>
        <mat-card-subtitle>
          Processos aguardando ou em andamento de vistoria (ordem FIFO por data de entrada)
        </mat-card-subtitle>
      </mat-card-header>
      <mat-card-content>

        @if (!loading() && fila().length === 0) {
          <p class="empty-msg">
            <mat-icon>check_circle_outline</mat-icon>
            Nenhum processo aguardando vistoria no momento.
          </p>
        }

        @if (fila().length > 0) {
          <table mat-table [dataSource]="fila()" class="fila-table">

            <!-- Numero PPCI -->
            <ng-container matColumnDef="numero">
              <th mat-header-cell *matHeaderCellDef>Numero PPCI</th>
              <td mat-cell *matCellDef="let row">
                {{ row.numeroPpci ?? '(sem numero)' }}
              </td>
            </ng-container>

            <!-- Tipo -->
            <ng-container matColumnDef="tipo">
              <th mat-header-cell *matHeaderCellDef>Tipo</th>
              <td mat-cell *matCellDef="let row">{{ row.tipo }}</td>
            </ng-container>

            <!-- Status -->
            <ng-container matColumnDef="status">
              <th mat-header-cell *matHeaderCellDef>Status</th>
              <td mat-cell *matCellDef="let row">
                <span class="status-badge" [style.background]="getStatusColor(row.status)">
                  {{ getStatusLabel(row.status) }}
                </span>
              </td>
            </ng-container>

            <!-- Municipio -->
            <ng-container matColumnDef="municipio">
              <th mat-header-cell *matHeaderCellDef>Municipio</th>
              <td mat-cell *matCellDef="let row">
                {{ row.endereco.municipio }}/{{ row.endereco.uf }}
              </td>
            </ng-container>

            <!-- Area -->
            <ng-container matColumnDef="area">
              <th mat-header-cell *matHeaderCellDef>Area (m2)</th>
              <td mat-cell *matCellDef="let row">
                {{ row.areaConstruida != null ? (row.areaConstruida | number:'1.0-0') : '-' }}
              </td>
            </ng-container>

            <!-- Data de Entrada -->
            <ng-container matColumnDef="entrada">
              <th mat-header-cell *matHeaderCellDef>Entrada</th>
              <td mat-cell *matCellDef="let row">
                {{ row.dataCriacao | date:'dd/MM/yyyy' }}
              </td>
            </ng-container>

            <!-- Acoes -->
            <ng-container matColumnDef="acoes">
              <th mat-header-cell *matHeaderCellDef></th>
              <td mat-cell *matCellDef="let row">
                <a mat-icon-button
                   [routerLink]="['/app/vistorias', row.id]"
                   matTooltip="Abrir tela de vistoria">
                  <mat-icon>fact_check</mat-icon>
                </a>
              </td>
            </ng-container>

            <tr mat-header-row *matHeaderRowDef="colunas"></tr>
            <tr mat-row *matRowDef="let row; columns: colunas;" class="fila-row"></tr>
          </table>

          <mat-paginator
            [length]="total()"
            [pageSize]="pageSize"
            [pageSizeOptions]="[10, 25, 50]"
            (page)="onPage($event)"
            aria-label="Paginar fila de vistoria">
          </mat-paginator>
        }

      </mat-card-content>
    </mat-card>
  `,
  styles: [`
    .fila-table { width: 100%; }
    .fila-row:hover { background: #f5f5f5; cursor: pointer; }
    .status-badge {
      display: inline-block; padding: 3px 10px; border-radius: 12px;
      font-size: 12px; font-weight: 500; color: #fff;
    }
    .empty-msg {
      display: flex; align-items: center; gap: 8px;
      color: #666; font-size: 14px; padding: 24px 0;
    }
    .empty-msg mat-icon { color: #4caf50; }
  `]
})
export class VistoriaFilaComponent implements OnInit {

  private readonly svc = inject(LicenciamentoService);

  fila    = signal<LicenciamentoDTO[]>([]);
  total   = signal(0);
  loading = signal(false);
  error   = signal<string | null>(null);

  readonly colunas  = ['numero', 'tipo', 'status', 'municipio', 'area', 'entrada', 'acoes'];
  readonly pageSize = 10;

  ngOnInit(): void {
    this.carregar(0);
  }

  onPage(ev: PageEvent): void {
    this.carregar(ev.pageIndex);
  }

  getStatusLabel(status: StatusLicenciamento): string {
    return STATUS_LABEL[status] ?? status;
  }

  getStatusColor(status: StatusLicenciamento): string {
    return STATUS_COLOR[status] ?? '#9e9e9e';
  }

  private carregar(page: number): void {
    this.loading.set(true);
    this.svc.getFilaVistoria(page, this.pageSize).subscribe({
      next: res => {
        this.fila.set(res.content);
        this.total.set(res.totalElements);
        this.loading.set(false);
      },
      error: err => {
        this.error.set('Erro ao carregar a fila de vistoria. Tente novamente.');
        this.loading.set(false);
        console.error(err);
      }
    });
  }
}
