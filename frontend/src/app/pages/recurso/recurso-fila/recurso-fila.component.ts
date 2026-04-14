import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { MatTableModule } from '@angular/material/table';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatCardModule } from '@angular/material/card';
import { MatTooltipModule } from '@angular/material/tooltip';
import { MatChipsModule } from '@angular/material/chips';
import { LicenciamentoService } from '../../../core/services/licenciamento.service';
import { LicenciamentoDTO, STATUS_LABEL, STATUS_COLOR } from '../../../core/models/licenciamento.model';
import { LoadingComponent } from '../../../shared/components/loading/loading.component';
import { ErrorAlertComponent } from '../../../shared/components/error-alert/error-alert.component';

@Component({
  selector: 'sol-recurso-fila',
  standalone: true,
  imports: [
    CommonModule,
    RouterLink,
    MatTableModule,
    MatButtonModule,
    MatIconModule,
    MatCardModule,
    MatTooltipModule,
    MatChipsModule,
    LoadingComponent,
    ErrorAlertComponent,
  ],
  template: `
    <div class="page-header">
      <div>
        <h1 class="page-title">Fila de Recursos</h1>
        <p class="page-subtitle">
          Recursos CIA/CIV aguardando triagem ou em analise pela comissao
        </p>
      </div>
    </div>

    <sol-loading [show]="loading()" message="Carregando fila de recursos..." />
    <sol-error-alert [message]="error()" (dismissed)="error.set(null)" />

    @if (!loading()) {
      @if (recursos().length === 0) {
        <mat-card appearance="outlined" class="empty-card">
          <mat-card-content>
            <mat-icon class="empty-icon">gavel</mat-icon>
            <p>Nenhum recurso pendente no momento.</p>
          </mat-card-content>
        </mat-card>
      } @else {
        <mat-card appearance="outlined">
          <mat-card-content class="table-container">
            <table mat-table [dataSource]="recursos()" class="full-width">

              <!-- Numero -->
              <ng-container matColumnDef="numero">
                <th mat-header-cell *matHeaderCellDef>Numero</th>
                <td mat-cell *matCellDef="let row">
                  <span class="numero-cell">{{ row.numeroPpci ?? '—' }}</span>
                </td>
              </ng-container>

              <!-- Tipo -->
              <ng-container matColumnDef="tipo">
                <th mat-header-cell *matHeaderCellDef>Tipo</th>
                <td mat-cell *matCellDef="let row">
                  <span class="tipo-badge">{{ row.tipo }}</span>
                </td>
              </ng-container>

              <!-- Status -->
              <ng-container matColumnDef="status">
                <th mat-header-cell *matHeaderCellDef>Status</th>
                <td mat-cell *matCellDef="let row">
                  <span class="status-badge"
                        [style.background]="getStatusColor(row.status)">
                    {{ getStatusLabel(row.status) }}
                  </span>
                </td>
              </ng-container>

              <!-- Municipio -->
              <ng-container matColumnDef="municipio">
                <th mat-header-cell *matHeaderCellDef>Municipio</th>
                <td mat-cell *matCellDef="let row">{{ row.endereco.municipio ?? '—' }}</td>
              </ng-container>

              <!-- Area -->
              <ng-container matColumnDef="area">
                <th mat-header-cell *matHeaderCellDef>Area (m2)</th>
                <td mat-cell *matCellDef="let row">
                  {{ row.areaConstruida != null ? (row.areaConstruida | number:'1.0-0') : '—' }}
                </td>
              </ng-container>

              <!-- Data de entrada do recurso -->
              <ng-container matColumnDef="entrada">
                <th mat-header-cell *matHeaderCellDef>Entrada</th>
                <td mat-cell *matCellDef="let row">
                  {{ row.dataAtualizacao | date:'dd/MM/yyyy' }}
                </td>
              </ng-container>

              <!-- Acoes -->
              <ng-container matColumnDef="acoes">
                <th mat-header-cell *matHeaderCellDef></th>
                <td mat-cell *matCellDef="let row">
                  <a mat-icon-button
                     [routerLink]="['/app/recursos', row.id]"
                     matTooltip="Abrir recurso">
                    <mat-icon>open_in_new</mat-icon>
                  </a>
                </td>
              </ng-container>

              <tr mat-header-row *matHeaderRowDef="colunas"></tr>
              <tr mat-row *matRowDef="let row; columns: colunas;"
                  class="row-hover"
                  [routerLink]="['/app/recursos', row.id]"
                  style="cursor:pointer"></tr>
            </table>
          </mat-card-content>
        </mat-card>
      }
    }
  `,
  styles: [`
    .page-header {
      margin-bottom: 24px;
    }
    .page-title {
      font-size: 22px;
      font-weight: 600;
      color: #1a1a2e;
      margin: 0 0 4px;
    }
    .page-subtitle {
      font-size: 13px;
      color: #666;
      margin: 0;
    }
    .table-container {
      overflow-x: auto;
      padding: 0;
    }
    .full-width {
      width: 100%;
    }
    .numero-cell {
      font-family: monospace;
      font-size: 13px;
      font-weight: 600;
      color: #1a3a5c;
    }
    .tipo-badge {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 4px;
      font-size: 11px;
      font-weight: 700;
      background: #e8eaf6;
      color: #3949ab;
    }
    .status-badge {
      display: inline-block;
      padding: 3px 10px;
      border-radius: 12px;
      font-size: 11px;
      font-weight: 500;
      color: #fff;
    }
    .row-hover:hover {
      background: #f5f5f5;
    }
    .empty-card {
      text-align: center;
      padding: 48px 24px;
    }
    .empty-icon {
      font-size: 48px;
      width: 48px;
      height: 48px;
      color: #bdbdbd;
      margin-bottom: 12px;
    }
  `]
})
export class RecursoFilaComponent implements OnInit {

  private readonly svc = inject(LicenciamentoService);

  readonly colunas = ['numero', 'tipo', 'status', 'municipio', 'area', 'entrada', 'acoes'];

  recursos = signal<LicenciamentoDTO[]>([]);
  loading  = signal(true);
  error    = signal<string | null>(null);

  ngOnInit(): void {
    this.svc.getFilaRecurso().subscribe({
      next: page => {
        this.recursos.set(page.content);
        this.loading.set(false);
      },
      error: err => {
        this.error.set('Nao foi possivel carregar a fila de recursos.');
        this.loading.set(false);
        console.error(err);
      }
    });
  }

  getStatusLabel(status: string): string {
    return STATUS_LABEL[status as keyof typeof STATUS_LABEL] ?? status;
  }

  getStatusColor(status: string): string {
    return STATUS_COLOR[status as keyof typeof STATUS_COLOR] ?? '#9e9e9e';
  }
}
