import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule } from '@angular/forms';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatDividerModule } from '@angular/material/divider';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { LicenciamentoService } from '../../../core/services/licenciamento.service';
import { AuthService } from '../../../core/services/auth.service';
import {
  LicenciamentoDTO,
  STATUS_LABEL,
  STATUS_COLOR
} from '../../../core/models/licenciamento.model';
import { LoadingComponent } from '../../../shared/components/loading/loading.component';
import { ErrorAlertComponent } from '../../../shared/components/error-alert/error-alert.component';

/**
 * Acao de formulario ativa no momento.
 *  aceitar  — Admin confirma a troca (campo observacao opcional)
 *  rejeitar — Admin rejeita com motivo obrigatorio
 */
type AcaoAtiva = 'aceitar' | 'rejeitar' | null;

@Component({
  selector: 'sol-troca-detalhe',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    MatCardModule,
    MatButtonModule,
    MatIconModule,
    MatFormFieldModule,
    MatInputModule,
    MatDividerModule,
    MatProgressSpinnerModule,
    LoadingComponent,
    ErrorAlertComponent,
  ],
  template: `
    <sol-loading [show]="loading()" message="Carregando solicitacao de troca..." />
    <sol-error-alert [message]="error()" (dismissed)="error.set(null)" />

    <!-- Botao voltar -->
    <div class="page-header">
      <button mat-button type="button" (click)="voltar()">
        <mat-icon>arrow_back</mat-icon>
        Voltar para a fila
      </button>
    </div>

    @if (lic(); as l) {

      <!-- Identificacao do licenciamento -->
      <mat-card appearance="outlined" class="section-card">
        <mat-card-header>
          <mat-icon mat-card-avatar>manage_accounts</mat-icon>
          <mat-card-title>{{ l.numeroPpci ?? 'Licenciamento #' + l.id }}</mat-card-title>
          <mat-card-subtitle>
            <span class="status-badge" [style.background]="getStatusColor(l.status)">
              {{ getStatusLabel(l.status) }}
            </span>
            &nbsp; Tipo: <strong>{{ l.tipo }}</strong>
            &nbsp; Municipio: <strong>{{ l.endereco.municipio }}</strong>
          </mat-card-subtitle>
        </mat-card-header>
        <mat-card-content>
          <div class="meta-row">
            <span class="meta-item">
              <mat-icon class="meta-icon">square_foot</mat-icon>
              {{ l.areaConstruida != null ? (l.areaConstruida | number:'1.2-2') + ' m2' : '—' }}
            </span>
            <span class="meta-item">
              <mat-icon class="meta-icon">update</mat-icon>
              Solicitacao em {{ l.dataAtualizacao | date:'dd/MM/yyyy HH:mm' }}
            </span>
          </div>
        </mat-card-content>
      </mat-card>

      <!-- Justificativa da solicitacao -->
      @if (l.justificativaTroca) {
        <mat-card appearance="outlined" class="section-card">
          <mat-card-header>
            <mat-card-title>Justificativa do RT</mat-card-title>
            <mat-card-subtitle>Motivo apresentado pelo Responsavel Tecnico para a saida</mat-card-subtitle>
          </mat-card-header>
          <mat-card-content>
            <p class="justificativa-texto">{{ l.justificativaTroca }}</p>
          </mat-card-content>
        </mat-card>
      }

      <!-- ═══════════════════════════════════════════════════════════
           PAINEL DE ACAO — triagem da solicitacao pelo Admin
           Opcoes: Aceitar (com observacao opcional) | Rejeitar (com motivo)
           Visivel apenas quando: podeGerenciar && l.trocaPendente
           ═══════════════════════════════════════════════════════════ -->
      @if (podeGerenciar && l.trocaPendente) {
        <mat-card appearance="outlined" class="section-card action-card">
          <mat-card-header>
            <mat-icon mat-card-avatar>how_to_reg</mat-icon>
            <mat-card-title>Analise da Solicitacao</mat-card-title>
            <mat-card-subtitle>
              Aceite para liberar a substituicao do RT, ou rejeite com justificativa.
              Se aceito, o sistema notifica o novo RT indicado para que ele se associe.
            </mat-card-subtitle>
          </mat-card-header>
          <mat-card-content>

            @if (acaoAtiva() === null) {
              <div class="botoes-acao">
                <button mat-raised-button color="primary"
                        (click)="acaoAtiva.set('aceitar')"
                        [disabled]="saving()">
                  <mat-icon>how_to_reg</mat-icon>
                  Aceitar Troca
                </button>
                <button mat-stroked-button color="warn"
                        (click)="acaoAtiva.set('rejeitar')"
                        [disabled]="saving()">
                  <mat-icon>person_off</mat-icon>
                  Rejeitar Solicitacao
                </button>
              </div>
            }

            @if (acaoAtiva() === 'aceitar') {
              <form [formGroup]="aceitarForm">
                <mat-form-field appearance="outline" class="field-full">
                  <mat-label>Observacao (opcional)</mat-label>
                  <textarea matInput formControlName="observacao" rows="3"
                            placeholder="Instrucoes para o novo RT ou observacoes sobre a troca..."></textarea>
                </mat-form-field>
                <div class="form-actions">
                  <button mat-button type="button"
                          (click)="acaoAtiva.set(null)"
                          [disabled]="saving()">
                    Cancelar
                  </button>
                  <button mat-raised-button color="primary"
                          (click)="confirmarAceite(l.id)"
                          [disabled]="saving()">
                    @if (saving()) {
                      <ng-container>
                        <mat-spinner diameter="18" color="accent"></mat-spinner>
                        Salvando...
                      </ng-container>
                    } @else {
                      <ng-container>
                        <mat-icon>how_to_reg</mat-icon>
                        Confirmar Aceite
                      </ng-container>
                    }
                  </button>
                </div>
              </form>
            }

            @if (acaoAtiva() === 'rejeitar') {
              <form [formGroup]="rejeitarForm">
                <mat-form-field appearance="outline" class="field-full">
                  <mat-label>Motivo da Rejeicao</mat-label>
                  <textarea matInput formControlName="motivo" rows="4"
                            placeholder="Informe o motivo pelo qual a troca de RT nao sera autorizada..."></textarea>
                  @if (rejeitarForm.get('motivo')!.hasError('required') && rejeitarForm.get('motivo')!.touched) {
                    <mat-error>Motivo e obrigatorio</mat-error>
                  }
                  @if (rejeitarForm.get('motivo')!.hasError('minlength') && rejeitarForm.get('motivo')!.touched) {
                    <mat-error>Minimo de 20 caracteres</mat-error>
                  }
                </mat-form-field>
                <div class="form-actions">
                  <button mat-button type="button"
                          (click)="acaoAtiva.set(null)"
                          [disabled]="saving()">
                    Cancelar
                  </button>
                  <button mat-raised-button color="warn"
                          (click)="confirmarRejeicao(l.id)"
                          [disabled]="rejeitarForm.invalid || saving()">
                    @if (saving()) {
                      <ng-container>
                        <mat-spinner diameter="18" color="accent"></mat-spinner>
                        Salvando...
                      </ng-container>
                    } @else {
                      <ng-container>
                        <mat-icon>person_off</mat-icon>
                        Confirmar Rejeicao
                      </ng-container>
                    }
                  </button>
                </div>
              </form>
            }

          </mat-card-content>
        </mat-card>
      }

      <!-- Painel informativo: solicitacao ja processada (sem trocaPendente) -->
      @if (!l.trocaPendente) {
        <mat-card appearance="outlined" class="section-card info-card">
          <mat-card-content>
            <div class="info-row">
              <mat-icon>info</mat-icon>
              <span>
                Esta solicitacao ja foi processada.
                O licenciamento nao possui troca pendente no momento.
              </span>
            </div>
          </mat-card-content>
        </mat-card>
      }

    }
  `,
  styles: [`
    .page-header {
      margin-bottom: 16px;
    }
    .section-card {
      margin-bottom: 16px;
    }
    .action-card {
      border-left: 4px solid #1a3a5c;
    }
    .status-badge {
      display: inline-block;
      padding: 3px 10px;
      border-radius: 12px;
      font-size: 12px;
      font-weight: 500;
      color: #fff;
    }
    .meta-row {
      display: flex;
      gap: 24px;
      flex-wrap: wrap;
      margin-top: 12px;
    }
    .meta-item {
      display: flex;
      align-items: center;
      gap: 4px;
      font-size: 13px;
      color: #666;
    }
    .meta-icon {
      font-size: 16px;
      width: 16px;
      height: 16px;
    }
    .justificativa-texto {
      font-size: 14px;
      color: #333;
      line-height: 1.6;
      white-space: pre-wrap;
      margin: 8px 0 0;
    }
    .botoes-acao {
      display: flex;
      gap: 12px;
      flex-wrap: wrap;
      margin-top: 8px;
    }
    .field-full {
      width: 100%;
      margin-top: 12px;
    }
    .form-actions {
      display: flex;
      gap: 12px;
      justify-content: flex-end;
      margin-top: 16px;
      padding-top: 12px;
      border-top: 1px solid #f0f0f0;
    }
    .info-card {
      border-left: 4px solid #3498db;
    }
    .info-row {
      display: flex;
      align-items: center;
      gap: 10px;
      font-size: 14px;
      color: #1a5276;
    }
    .info-row mat-icon {
      color: #3498db;
    }
  `]
})
export class TrocaDetalheComponent implements OnInit {

  private readonly svc    = inject(LicenciamentoService);
  private readonly auth   = inject(AuthService);
  private readonly route  = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly fb     = inject(FormBuilder);

  lic       = signal<LicenciamentoDTO | null>(null);
  loading   = signal(true);
  saving    = signal(false);
  error     = signal<string | null>(null);
  acaoAtiva = signal<AcaoAtiva>(null);

  /**
   * Verdadeiro para ADMIN e CHEFE_SSEG_BBM.
   * Controla as acoes de aceitar e rejeitar a solicitacao de troca.
   */
  readonly podeGerenciar = this.auth.hasAnyRole(['ADMIN', 'CHEFE_SSEG_BBM']);

  aceitarForm!: FormGroup;
  rejeitarForm!: FormGroup;

  ngOnInit(): void {
    this.aceitarForm = this.fb.group({
      observacao: ['']
    });

    this.rejeitarForm = this.fb.group({
      motivo: ['', [Validators.required, Validators.minLength(20)]]
    });

    const id = Number(this.route.snapshot.paramMap.get('id'));
    this.svc.getById(id).subscribe({
      next: data => {
        this.lic.set(data);
        this.loading.set(false);
      },
      error: err => {
        this.error.set('Licenciamento nao encontrado ou sem permissao de acesso.');
        this.loading.set(false);
        console.error(err);
      }
    });
  }

  voltar(): void {
    this.router.navigate(['/app/trocas']);
  }

  confirmarAceite(id: number): void {
    this.saving.set(true);
    this.error.set(null);
    const dto = this.aceitarForm.value.observacao
      ? { observacao: this.aceitarForm.value.observacao }
      : {};
    this.svc.aceitarTroca(id, dto).subscribe({
      next: updated => {
        this.lic.set(updated);
        this.acaoAtiva.set(null);
        this.saving.set(false);
        this.router.navigate(['/app/trocas']);
      },
      error: err => {
        const msg = err?.error?.message ?? err?.message ?? 'Erro desconhecido';
        this.error.set(`Nao foi possivel aceitar a troca: ${msg}`);
        this.saving.set(false);
        console.error(err);
      }
    });
  }

  confirmarRejeicao(id: number): void {
    if (this.rejeitarForm.invalid) return;
    this.saving.set(true);
    this.error.set(null);
    this.svc.rejeitarTroca(id, this.rejeitarForm.value).subscribe({
      next: updated => {
        this.lic.set(updated);
        this.acaoAtiva.set(null);
        this.saving.set(false);
        this.router.navigate(['/app/trocas']);
      },
      error: err => {
        const msg = err?.error?.message ?? err?.message ?? 'Erro desconhecido';
        this.error.set(`Nao foi possivel rejeitar a solicitacao: ${msg}`);
        this.saving.set(false);
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
