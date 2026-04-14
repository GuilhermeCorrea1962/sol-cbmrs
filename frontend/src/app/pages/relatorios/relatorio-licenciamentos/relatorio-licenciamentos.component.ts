import { Component, OnInit, inject, signal } from '@angular/core';
import { Router } from '@angular/router';
import { FormBuilder, ReactiveFormsModule } from '@angular/forms';
import { MatTableModule } from '@angular/material/table';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { MatDatepickerModule } from '@angular/material/datepicker';
import { MatNativeDateModule } from '@angular/material/core';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatPaginatorModule } from '@angular/material/paginator';
import { MatIconModule } from '@angular/material/icon';
import { MatTooltipModule } from '@angular/material/tooltip';
import { MatDividerModule } from '@angular/material/divider';
import { DatePipe } from '@angular/common';
import { RelatorioService } from '../../../core/services/relatorio.service';
import {
  RelatorioLicenciamentosItem,
  RelatorioLicenciamentosRequest
} from '../../../core/models/relatorio.model';
import { STATUS_LABEL, STATUS_COLOR } from '../../../core/models/licenciamento.model';

@Component({
  selector: 'sol-relatorio-licenciamentos',
  standalone: true,
  imports: [
    ReactiveFormsModule,
    MatTableModule,
    MatCardModule,
    MatButtonModule,
    MatFormFieldModule,
    MatInputModule,
    MatSelectModule,
    MatDatepickerModule,
    MatNativeDateModule,
    MatProgressSpinnerModule,
    MatPaginatorModule,
    MatIconModule,
    MatTooltipModule,
    MatDividerModule,
    DatePipe
  ],
  template: `
    <div class="rellic-container">

      <!-- Cabecalho -->
      <div class="rellic-header">
        <button mat-icon-button (click)="voltar()" matTooltip="Voltar ao menu de relatorios">
          <mat-icon>arrow_back</mat-icon>
        </button>
        <h2 class="rellic-title">Licenciamentos por Periodo</h2>
      </div>

      <!-- Formulario de filtros -->
      <mat-card class="rellic-filtro-card">
        <mat-card-header>
          <mat-card-title>Filtros</mat-card-title>
        </mat-card-header>
        <mat-card-content>
          <form [formGroup]="filtroForm" class="rellic-filtro-form">

            <mat-form-field appearance="outline">
              <mat-label>Data de inicio</mat-label>
              <input matInput [matDatepicker]="dpInicio" formControlName="dataInicio"
                     placeholder="dd/mm/aaaa">
              <mat-datepicker-toggle matIconSuffix [for]="dpInicio"></mat-datepicker-toggle>
              <mat-datepicker #dpInicio></mat-datepicker>
            </mat-form-field>

            <mat-form-field appearance="outline">
              <mat-label>Data de fim</mat-label>
              <input matInput [matDatepicker]="dpFim" formControlName="dataFim"
                     placeholder="dd/mm/aaaa">
              <mat-datepicker-toggle matIconSuffix [for]="dpFim"></mat-datepicker-toggle>
              <mat-datepicker #dpFim></mat-datepicker>
            </mat-form-field>

            <mat-form-field appearance="outline">
              <mat-label>Status</mat-label>
              <mat-select formControlName="status">
                @for (op of STATUS_OPCOES; track op.valor) {
                  <mat-option [value]="op.valor">{{ op.label }}</mat-option>
                }
              </mat-select>
            </mat-form-field>

            <mat-form-field appearance="outline">
              <mat-label>Municipio</mat-label>
              <input matInput formControlName="municipio" placeholder="Ex.: Porto Alegre">
              <mat-icon matSuffix>location_on</mat-icon>
            </mat-form-field>

            <mat-form-field appearance="outline">
              <mat-label>Tipo</mat-label>
              <mat-select formControlName="tipo">
                <mat-option value="">Todos</mat-option>
                <mat-option value="PPCI">PPCI</mat-option>
                <mat-option value="PSPCIM">PSPCIM</mat-option>
              </mat-select>
            </mat-form-field>

          </form>
        </mat-card-content>
        <mat-card-actions class="rellic-filtro-acoes">
          <button mat-flat-button color="primary" (click)="buscar()" [disabled]="carregando()">
            <mat-icon>search</mat-icon>
            Buscar
          </button>
          <button mat-stroked-button (click)="limpar()">
            <mat-icon>clear</mat-icon>
            Limpar
          </button>
          <span class="rellic-spacer"></span>
          <button mat-stroked-button color="accent"
                  [disabled]="itens().length === 0 || carregando()"
                  (click)="exportarCSV()"
                  matTooltip="Exportar resultado atual em CSV">
            <mat-icon>download</mat-icon>
            Exportar CSV
          </button>
        </mat-card-actions>
      </mat-card>

      <!-- Estado de carregamento -->
      <ng-container>
        @if (carregando()) {
          <div class="rellic-loading">
            <mat-spinner diameter="40"></mat-spinner>
            <span>Consultando...</span>
          </div>
        } @else if (pesquisaRealizada() && itens().length === 0) {
          <!-- Estado vazio -->
          <div class="rellic-empty">
            <mat-icon class="rellic-empty-icon">search_off</mat-icon>
            <p>Nenhum licenciamento encontrado para os filtros informados.</p>
            <button mat-stroked-button (click)="limpar()">Limpar filtros</button>
          </div>
        } @else if (itens().length > 0) {
          <!-- Tabela de resultados -->
          <div class="rellic-table-wrap">
            <p class="rellic-total">
              {{ totalRegistros() }} registro(s) encontrado(s)
            </p>
            <mat-table [dataSource]="itens()" class="rellic-table">

              <ng-container matColumnDef="numeroPpci">
                <mat-header-cell *matHeaderCellDef>Numero</mat-header-cell>
                <mat-cell *matCellDef="let row">
                  {{ row.numeroPpci || '—' }}
                </mat-cell>
              </ng-container>

              <ng-container matColumnDef="tipo">
                <mat-header-cell *matHeaderCellDef>Tipo</mat-header-cell>
                <mat-cell *matCellDef="let row">{{ row.tipo }}</mat-cell>
              </ng-container>

              <ng-container matColumnDef="status">
                <mat-header-cell *matHeaderCellDef>Status</mat-header-cell>
                <mat-cell *matCellDef="let row">
                  <span class="rellic-status-badge"
                        [style.background]="corStatus(row.status)">
                    {{ labelStatus(row.status) }}
                  </span>
                </mat-cell>
              </ng-container>

              <ng-container matColumnDef="municipio">
                <mat-header-cell *matHeaderCellDef>Municipio</mat-header-cell>
                <mat-cell *matCellDef="let row">{{ row.municipio }}</mat-cell>
              </ng-container>

              <ng-container matColumnDef="area">
                <mat-header-cell *matHeaderCellDef>Area (m2)</mat-header-cell>
                <mat-cell *matCellDef="let row">
                  {{ row.areaConstruida != null ? row.areaConstruida : '—' }}
                </mat-cell>
              </ng-container>

              <ng-container matColumnDef="nomeRT">
                <mat-header-cell *matHeaderCellDef>Responsavel Tecnico</mat-header-cell>
                <mat-cell *matCellDef="let row">{{ row.nomeRT || '—' }}</mat-cell>
              </ng-container>

              <ng-container matColumnDef="dataCriacao">
                <mat-header-cell *matHeaderCellDef>Data de Entrada</mat-header-cell>
                <mat-cell *matCellDef="let row">
                  {{ row.dataCriacao | date:'dd/MM/yyyy' }}
                </mat-cell>
              </ng-container>

              <ng-container matColumnDef="acoes">
                <mat-header-cell *matHeaderCellDef></mat-header-cell>
                <mat-cell *matCellDef="let row">
                  <button mat-icon-button color="primary"
                          (click)="verDetalhe(row.id)"
                          matTooltip="Ver detalhe do licenciamento">
                    <mat-icon>open_in_new</mat-icon>
                  </button>
                </mat-cell>
              </ng-container>

              <mat-header-row *matHeaderRowDef="colunas"></mat-header-row>
              <mat-row *matRowDef="let row; columns: colunas;"></mat-row>

            </mat-table>

            <mat-paginator
              [length]="totalRegistros()"
              [pageSize]="tamanhoPagina"
              [pageSizeOptions]="[20, 50, 100]"
              (page)="onPage($event)"
              showFirstLastButtons>
            </mat-paginator>
          </div>
        }
      </ng-container>

    </div>
  `,
  styles: [`
    .rellic-container     { padding: 24px; max-width: 1200px; margin: 0 auto; }
    .rellic-header        { display: flex; align-items: center; gap: 8px; margin-bottom: 16px; }
    .rellic-title         { margin: 0; font-size: 1.4rem; font-weight: 600; }
    .rellic-filtro-card   { margin-bottom: 24px; }
    .rellic-filtro-form   { display: flex; flex-wrap: wrap; gap: 12px; padding-top: 8px; }
    .rellic-filtro-form mat-form-field { flex: 1 1 200px; }
    .rellic-filtro-acoes  { display: flex; align-items: center; gap: 8px;
                            padding: 8px 16px 16px; flex-wrap: wrap; }
    .rellic-spacer        { flex: 1; }
    .rellic-loading       { display: flex; align-items: center; gap: 16px;
                            justify-content: center; padding: 40px 0; color: #666; }
    .rellic-empty         { display: flex; flex-direction: column; align-items: center;
                            padding: 48px 16px; gap: 12px; color: #777; }
    .rellic-empty-icon    { font-size: 48px; width: 48px; height: 48px; color: #bbb; }
    .rellic-total         { margin: 8px 0; font-size: 0.9rem; color: #666; }
    .rellic-table-wrap    { overflow-x: auto; }
    .rellic-table         { width: 100%; }
    .rellic-status-badge  { color: #fff; padding: 2px 8px; border-radius: 12px;
                            font-size: 0.75rem; white-space: nowrap; }
  `]
})
export class RelatorioLicenciamentosComponent implements OnInit {

  private readonly svc    = inject(RelatorioService);
  private readonly router = inject(Router);
  private readonly fb     = inject(FormBuilder);

  readonly colunas = [
    'numeroPpci', 'tipo', 'status', 'municipio',
    'area', 'nomeRT', 'dataCriacao', 'acoes'
  ];

  readonly STATUS_OPCOES = [
    { valor: '',                    label: 'Todos'                },
    { valor: 'RASCUNHO',            label: 'Rascunho'             },
    { valor: 'ANALISE_PENDENTE',    label: 'Analise Pendente'     },
    { valor: 'EM_ANALISE',          label: 'Em Analise'           },
    { valor: 'CIA_EMITIDO',         label: 'CIA Emitido'          },
    { valor: 'CIA_CIENCIA',         label: 'CIA - Ciencia RT'     },
    { valor: 'DEFERIDO',            label: 'Deferido'             },
    { valor: 'INDEFERIDO',          label: 'Indeferido'           },
    { valor: 'VISTORIA_PENDENTE',   label: 'Vistoria Pendente'    },
    { valor: 'EM_VISTORIA',         label: 'Em Vistoria'          },
    { valor: 'CIV_EMITIDO',         label: 'CIV Emitido'          },
    { valor: 'PRPCI_EMITIDO',       label: 'PrPCI Emitido'        },
    { valor: 'APPCI_EMITIDO',       label: 'APPCI Emitido'        },
    { valor: 'RECURSO_SUBMETIDO',   label: 'Recurso Submetido'    },
    { valor: 'RECURSO_EM_ANALISE',  label: 'Recurso em Analise'   },
    { valor: 'RECURSO_DEFERIDO',    label: 'Recurso Deferido'     },
    { valor: 'RECURSO_INDEFERIDO',  label: 'Recurso Indeferido'   },
    { valor: 'SUSPENSO',            label: 'Suspenso'             },
    { valor: 'EXTINTO',             label: 'Extinto'              },
    { valor: 'RENOVADO',            label: 'Renovado'             }
  ];

  readonly tamanhoPagina  = 50;
  readonly itens          = signal<RelatorioLicenciamentosItem[]>([]);
  readonly totalRegistros = signal(0);
  readonly carregando     = signal(false);
  readonly pesquisaRealizada = signal(false);

  private paginaAtual = 0;

  filtroForm = this.fb.group({
    dataInicio: [null as Date | null],
    dataFim:    [null as Date | null],
    status:     [''],
    municipio:  [''],
    tipo:       ['']
  });

  ngOnInit(): void {
    // Executa busca inicial sem filtros ao abrir o relatorio
    this.buscar();
  }

  buscar(): void {
    this.paginaAtual = 0;
    this.executarBusca();
  }

  limpar(): void {
    this.filtroForm.reset({ dataInicio: null, dataFim: null, status: '', municipio: '', tipo: '' });
    this.itens.set([]);
    this.totalRegistros.set(0);
    this.pesquisaRealizada.set(false);
    this.paginaAtual = 0;
  }

  onPage(evento: { pageIndex: number; pageSize: number }): void {
    this.paginaAtual = evento.pageIndex;
    this.executarBusca();
  }

  exportarCSV(): void {
    const filtro = this.buildFiltro();
    this.svc.exportarCSV(filtro).subscribe({
      next: (blob) => {
        const hoje = new Date().toISOString().split('T')[0];
        const url  = URL.createObjectURL(blob);
        const a    = document.createElement('a');
        a.href     = url;
        a.download = `relatorio-licenciamentos-${hoje}.csv`;
        a.click();
        URL.revokeObjectURL(url);
      }
    });
  }

  verDetalhe(id: number): void {
    this.router.navigate(['/app/licenciamentos', id]);
  }

  voltar(): void {
    this.router.navigate(['/app/relatorios']);
  }

  labelStatus(status: string): string {
    return (STATUS_LABEL as Record<string, string>)[status] ?? status;
  }

  corStatus(status: string): string {
    return (STATUS_COLOR as Record<string, string>)[status] ?? '#9e9e9e';
  }

  private executarBusca(): void {
    this.carregando.set(true);
    const filtro = this.buildFiltro();
    this.svc.getLicenciamentos(filtro, this.paginaAtual, this.tamanhoPagina).subscribe({
      next: (pagina) => {
        this.itens.set(pagina.content);
        this.totalRegistros.set(pagina.totalElements);
        this.carregando.set(false);
        this.pesquisaRealizada.set(true);
      },
      error: () => {
        this.itens.set([]);
        this.carregando.set(false);
        this.pesquisaRealizada.set(true);
      }
    });
  }

  private buildFiltro(): RelatorioLicenciamentosRequest {
    const v   = this.filtroForm.value;
    const fmt = (d: Date | null | undefined): string | undefined =>
      d ? d.toISOString().split('T')[0] : undefined;
    return {
      dataInicio: fmt(v.dataInicio),
      dataFim:    fmt(v.dataFim),
      status:     v.status    || undefined,
      municipio:  v.municipio || undefined,
      tipo:       v.tipo      || undefined
    };
  }
}
