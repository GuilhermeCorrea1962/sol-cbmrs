import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { MatTableModule } from '@angular/material/table';
import { MatPaginatorModule, PageEvent } from '@angular/material/paginator';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatCardModule } from '@angular/material/card';
import { MatTooltipModule } from '@angular/material/tooltip';
import { LicenciamentoService } from '../../core/services/licenciamento.service';
import { LicenciamentoDTO, StatusLicenciamento, STATUS_LABEL, STATUS_COLOR } from '../../core/models/licenciamento.model';
import { AuthService } from '../../core/services/auth.service';
import { LoadingComponent } from '../../shared/components/loading/loading.component';
import { ErrorAlertComponent } from '../../shared/components/error-alert/error-alert.component';

@Component({
  selector: 'sol-licenciamentos',
  standalone: true,
  imports: [
    CommonModule,
    RouterLink,
    MatTableModule,
    MatPaginatorModule,
    MatButtonModule,
    MatIconModule,
    MatCardModule,
    MatTooltipModule,
    LoadingComponent,
    ErrorAlertComponent,
  ],
  template: `
    <sol-loading [show]="loading() && totalElements() === 0" message="Carregando licenciamentos..." />

    <div class="page-header">
      <div>
        <h1 class="page-title">{{ titulo }}</h1>
        <p class="page-subtitle">{{ subtitulo }}</p>
      </div>
      @if (podeNovaSolicitacao) {
        <a mat-raised-button color="primary"
           routerLink="/app/licenciamentos/novo">
          <mat-icon>add</mat-icon>
          Nova Solicitacao
        </a>
      }
    </div>

    <sol-error-alert [message]="error()" (dismissed)="error.set(null)" />

    @if (!loading() && licenciamentos().length === 0 && !error()) {
      <mat-card class="empty-card" appearance="outlined">
        <mat-card-content>
          <mat-icon class="empty-icon">folder_open</mat-icon>
          <p class="empty-text">Voce ainda nao possui licenciamentos cadastrados.</p>
          <p class="empty-sub">Utilize "Nova Solicitacao" para iniciar um processo de licenciamento.</p>
        </mat-card-content>
      </mat-card>
    }

    @if (totalElements() > 0) {
      <mat-card appearance="outlined">
        <mat-card-content class="table-container">
          <table mat-table [dataSource]="licenciamentos()"
                 [style.opacity]="loading() ? '0.4' : '1'"
                 [style.pointer-events]="loading() ? 'none' : 'auto'">

            <!-- Coluna: Numero / Tipo -->
            <ng-container matColumnDef="numero">
              <th mat-header-cell *matHeaderCellDef>Numero / Tipo</th>
              <td mat-cell *matCellDef="let row">
                <div class="numero-cell">
                  <span class="numero">{{ row.numeroPpci ?? 'Sem numero' }}</span>
                  <span class="tipo-badge">{{ row.tipo }}</span>
                </div>
              </td>
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

            <!-- Coluna: Endereco -->
            <ng-container matColumnDef="endereco">
              <th mat-header-cell *matHeaderCellDef>Endereco</th>
              <td mat-cell *matCellDef="let row">
                {{ row.endereco.logradouro }}, {{ row.endereco.numero }} —
                {{ row.endereco.municipio }}/{{ row.endereco.uf }}
              </td>
            </ng-container>

            <!-- Coluna: Data -->
            <ng-container matColumnDef="data">
              <th mat-header-cell *matHeaderCellDef>Data</th>
              <td mat-cell *matCellDef="let row">
                {{ row.dataCriacao | date:'dd/MM/yyyy' }}
              </td>
            </ng-container>

            <!-- Coluna: Acoes -->
            <ng-container matColumnDef="acoes">
              <th mat-header-cell *matHeaderCellDef></th>
              <td mat-cell *matCellDef="let row">
                <a mat-icon-button color="primary"
                   [routerLink]="['/app/licenciamentos', row.id]"
                   matTooltip="Ver detalhes">
                  <mat-icon>visibility</mat-icon>
                </a>
              </td>
            </ng-container>

            <tr mat-header-row *matHeaderRowDef="displayedColumns"></tr>
            <tr mat-row *matRowDef="let row; columns: displayedColumns;"></tr>
          </table>
        </mat-card-content>

        <mat-card-actions>
          <mat-paginator
            [length]="totalElements()"
            [pageSize]="pageSize"
            [pageIndex]="currentPage"
            [pageSizeOptions]="[5, 10, 20]"
            [disabled]="loading()"
            (page)="onPage($event)"
            showFirstLastButtons
            aria-label="Paginar licenciamentos">
          </mat-paginator>
        </mat-card-actions>
      </mat-card>
    }
  `,
  styles: [`
    .page-header {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: 24px;
      flex-wrap: wrap;
      gap: 12px;
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
    }
    table {
      width: 100%;
    }
    .numero-cell {
      display: flex;
      flex-direction: column;
      gap: 2px;
    }
    .numero {
      font-family: monospace;
      font-size: 13px;
      font-weight: 600;
      color: #1a1a2e;
    }
    .tipo-badge {
      font-size: 11px;
      color: #888;
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
    .empty-card {
      text-align: center;
      padding: 48px 24px;
    }
    .empty-icon {
      font-size: 64px;
      width: 64px;
      height: 64px;
      color: #ccc;
      display: block;
      margin: 0 auto 16px;
    }
    .empty-text {
      font-size: 16px;
      color: #555;
      margin: 0 0 4px;
    }
    .empty-sub {
      font-size: 13px;
      color: #888;
      margin: 0;
    }
  `]
})
export class LicenciamentosComponent implements OnInit {

  private readonly svc  = inject(LicenciamentoService);
  private readonly auth = inject(AuthService);

  /** Exibe o botao "Nova Solicitacao" apenas para CIDADAO e ADMIN. */
  readonly podeNovaSolicitacao = this.auth.hasAnyRole(['CIDADAO', 'ADMIN']);

  /**
   * Usa a visao administrativa (GET /licenciamentos) quando o perfil tem
   * permissao para ver todos os processos; caso contrario usa /meus.
   */
  private readonly visaoAdmin = this.auth.hasAnyRole(
    ['ADMIN', 'ANALISTA', 'INSPETOR', 'CHEFE_SSEG_BBM']
  );

  readonly titulo    = this.visaoAdmin ? 'Licenciamentos' : 'Meus Licenciamentos';
  readonly subtitulo = this.visaoAdmin
    ? 'Consulte todos os processos de licenciamento PPCI e PSPCIM do sistema.'
    : 'Acompanhe seus processos de licenciamento PPCI e PSPCIM.';

  licenciamentos = signal<LicenciamentoDTO[]>([]);
  totalElements  = signal(0);
  loading        = signal(false);
  error          = signal<string | null>(null);

  readonly displayedColumns = ['numero', 'status', 'endereco', 'data', 'acoes'];
  pageSize    = 10;
  currentPage = 0;

  ngOnInit(): void {
    this.load();
  }

  private load(): void {
    this.loading.set(true);
    this.error.set(null);
    const source$ = this.visaoAdmin
      ? this.svc.getTodos(this.currentPage, this.pageSize)
      : this.svc.getMeus(this.currentPage, this.pageSize);
    source$.subscribe({
      next: page => {
        this.licenciamentos.set(page.content);
        this.totalElements.set(page.totalElements);
        this.loading.set(false);
      },
      error: err => {
        this.error.set('Nao foi possivel carregar os licenciamentos. Verifique sua conexao e tente novamente.');
        this.loading.set(false);
        console.error(err);
      }
    });
  }

  onPage(event: PageEvent): void {
    this.currentPage = event.pageIndex;
    this.pageSize    = event.pageSize;
    this.load();
  }

  getStatusLabel(status: StatusLicenciamento): string {
    return STATUS_LABEL[status] ?? status;
  }

  getStatusColor(status: StatusLicenciamento): string {
    return STATUS_COLOR[status] ?? '#9e9e9e';
  }
}
