import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule } from '@angular/forms';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatRadioModule } from '@angular/material/radio';
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
 *  recusar  — Admin recusa o recurso na triagem (precisa de motivo)
 *  votar    — Analista registra voto na comissao
 *  decidir  — Admin registra decisao final apos votacao
 */
type AcaoAtiva = 'recusar' | 'votar' | 'decidir' | null;

@Component({
  selector: 'sol-recurso-detalhe',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    MatCardModule,
    MatButtonModule,
    MatIconModule,
    MatFormFieldModule,
    MatInputModule,
    MatRadioModule,
    MatDividerModule,
    MatProgressSpinnerModule,
    LoadingComponent,
    ErrorAlertComponent,
  ],
  template: `
    <sol-loading [show]="loading()" message="Carregando recurso..." />
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
          <mat-icon mat-card-avatar>gavel</mat-icon>
          <mat-card-title>{{ l.numeroPpci ?? 'Recurso #' + l.id }}</mat-card-title>
          <mat-card-subtitle>
            <span class="status-badge" [style.background]="getStatusColor(l.status)">
              {{ getStatusLabel(l.status) }}
            </span>
            &nbsp; Tipo: <strong>{{ l.tipo }}</strong>
            &nbsp; Municipio: <strong>{{ l.endereco.municipio ?? '—' }}</strong>
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
              Atualizado em {{ l.dataAtualizacao | date:'dd/MM/yyyy HH:mm' }}
            </span>
          </div>
        </mat-card-content>
      </mat-card>

      <!-- Justificativa do recurso (campos opcionais — dependem do backend incluir no DTO) -->
      @if (l.justificativaRecurso) {
        <mat-card appearance="outlined" class="section-card">
          <mat-card-header>
            <mat-card-title>Justificativa do Recurso</mat-card-title>
            <mat-card-subtitle>Texto submetido pelo Responsavel Tecnico</mat-card-subtitle>
          </mat-card-header>
          <mat-card-content>
            <p class="justificativa-texto">{{ l.justificativaRecurso }}</p>
          </mat-card-content>
        </mat-card>
      }

      <!-- ═══════════════════════════════════════════════════════════
           PAINEL DE ACAO: RECURSO_SUBMETIDO — triagem pelo Admin
           Opcoes: Aceitar para analise (sem formulario) | Recusar (com motivo)
           ═══════════════════════════════════════════════════════════ -->
      @if (podeTriar && l.status === 'RECURSO_SUBMETIDO') {
        <mat-card appearance="outlined" class="section-card action-card">
          <mat-card-header>
            <mat-icon mat-card-avatar>manage_search</mat-icon>
            <mat-card-title>Triagem do Recurso</mat-card-title>
            <mat-card-subtitle>Aceite para iniciar a analise pela comissao, ou recuse com justificativa.</mat-card-subtitle>
          </mat-card-header>
          <mat-card-content>

            @if (acaoAtiva() === null) {
              <div class="botoes-acao">
                <button mat-raised-button color="primary"
                        (click)="aceitarRecurso(l.id)"
                        [disabled]="saving()">
                  @if (saving()) {
                    <ng-container>
                      <mat-spinner diameter="18" color="accent"></mat-spinner>
                      Processando...
                    </ng-container>
                  } @else {
                    <ng-container>
                      <mat-icon>check_circle</mat-icon>
                      Aceitar para Analise
                    </ng-container>
                  }
                </button>
                <button mat-stroked-button color="warn"
                        (click)="acaoAtiva.set('recusar')"
                        [disabled]="saving()">
                  <mat-icon>cancel</mat-icon>
                  Recusar Recurso
                </button>
              </div>
            }

            @if (acaoAtiva() === 'recusar') {
              <form [formGroup]="recusarForm">
                <mat-form-field appearance="outline" class="field-full">
                  <mat-label>Motivo da Recusa</mat-label>
                  <textarea matInput formControlName="motivo" rows="4"
                            placeholder="Informe o motivo pelo qual o recurso nao sera admitido..."></textarea>
                  @if (recusarForm.get('motivo')!.hasError('required') && recusarForm.get('motivo')!.touched) {
                    <mat-error>Motivo e obrigatorio</mat-error>
                  }
                  @if (recusarForm.get('motivo')!.hasError('minlength') && recusarForm.get('motivo')!.touched) {
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
                          (click)="confirmarRecusa(l.id)"
                          [disabled]="recusarForm.invalid || saving()">
                    @if (saving()) {
                      <ng-container>
                        <mat-spinner diameter="18" color="accent"></mat-spinner>
                        Salvando...
                      </ng-container>
                    } @else {
                      <ng-container>
                        <mat-icon>cancel</mat-icon>
                        Confirmar Recusa
                      </ng-container>
                    }
                  </button>
                </div>
              </form>
            }

          </mat-card-content>
        </mat-card>
      }

      <!-- ═══════════════════════════════════════════════════════════
           PAINEL DE ACAO: RECURSO_EM_ANALISE — voto do analista
           ═══════════════════════════════════════════════════════════ -->
      @if (podeVotar && l.status === 'RECURSO_EM_ANALISE') {
        <mat-card appearance="outlined" class="section-card action-card">
          <mat-card-header>
            <mat-icon mat-card-avatar>how_to_vote</mat-icon>
            <mat-card-title>Registro de Voto</mat-card-title>
            <mat-card-subtitle>Registre seu voto fundamentado sobre o recurso em analise.</mat-card-subtitle>
          </mat-card-header>
          <mat-card-content>
            @if (acaoAtiva() === null) {
              <button mat-raised-button color="accent"
                      (click)="acaoAtiva.set('votar')">
                <mat-icon>how_to_vote</mat-icon>
                Registrar Voto
              </button>
            }

            @if (acaoAtiva() === 'votar') {
              <form [formGroup]="votarForm">
                <div class="radio-group">
                  <label class="radio-label">Decisao *</label>
                  <mat-radio-group formControlName="decisao" class="radio-row">
                    <mat-radio-button value="DEFERIDO">Deferido</mat-radio-button>
                    <mat-radio-button value="INDEFERIDO">Indeferido</mat-radio-button>
                  </mat-radio-group>
                  @if (votarForm.get('decisao')!.hasError('required') && votarForm.get('decisao')!.touched) {
                    <p class="radio-error">Selecione uma decisao</p>
                  }
                </div>

                <mat-form-field appearance="outline" class="field-full">
                  <mat-label>Fundamentacao Tecnica</mat-label>
                  <textarea matInput formControlName="justificativa" rows="5"
                            placeholder="Descreva a fundamentacao tecnica do seu voto..."></textarea>
                  @if (votarForm.get('justificativa')!.hasError('required') && votarForm.get('justificativa')!.touched) {
                    <mat-error>Fundamentacao e obrigatoria</mat-error>
                  }
                  @if (votarForm.get('justificativa')!.hasError('minlength') && votarForm.get('justificativa')!.touched) {
                    <mat-error>Minimo de 30 caracteres</mat-error>
                  }
                </mat-form-field>

                <div class="form-actions">
                  <button mat-button type="button"
                          (click)="acaoAtiva.set(null)"
                          [disabled]="saving()">
                    Cancelar
                  </button>
                  <button mat-raised-button color="accent"
                          (click)="confirmarVoto(l.id)"
                          [disabled]="votarForm.invalid || saving()">
                    @if (saving()) {
                      <ng-container>
                        <mat-spinner diameter="18" color="accent"></mat-spinner>
                        Salvando...
                      </ng-container>
                    } @else {
                      <ng-container>
                        <mat-icon>how_to_vote</mat-icon>
                        Confirmar Voto
                      </ng-container>
                    }
                  </button>
                </div>
              </form>
            }
          </mat-card-content>
        </mat-card>
      }

      <!-- ═══════════════════════════════════════════════════════════
           PAINEL DE ACAO: RECURSO_EM_ANALISE — decisao final (Admin)
           ═══════════════════════════════════════════════════════════ -->
      @if (podeTriar && l.status === 'RECURSO_EM_ANALISE') {
        <mat-card appearance="outlined" class="section-card action-card">
          <mat-card-header>
            <mat-icon mat-card-avatar>assignment_turned_in</mat-icon>
            <mat-card-title>Decisao Final</mat-card-title>
            <mat-card-subtitle>
              Registre a decisao final do recurso apos a votacao da comissao.
              So e possivel decidir quando todos os votos tiverem sido registrados.
            </mat-card-subtitle>
          </mat-card-header>
          <mat-card-content>
            @if (acaoAtiva() === null) {
              <button mat-raised-button color="primary"
                      (click)="acaoAtiva.set('decidir')">
                <mat-icon>assignment_turned_in</mat-icon>
                Registrar Decisao Final
              </button>
            }

            @if (acaoAtiva() === 'decidir') {
              <form [formGroup]="decidirForm">
                <div class="radio-group">
                  <label class="radio-label">Decisao Final *</label>
                  <mat-radio-group formControlName="decisao" class="radio-row">
                    <mat-radio-button value="DEFERIDO">Deferido</mat-radio-button>
                    <mat-radio-button value="INDEFERIDO">Indeferido</mat-radio-button>
                  </mat-radio-group>
                  @if (decidirForm.get('decisao')!.hasError('required') && decidirForm.get('decisao')!.touched) {
                    <p class="radio-error">Selecione uma decisao</p>
                  }
                </div>

                <mat-form-field appearance="outline" class="field-full">
                  <mat-label>Fundamentacao da Decisao</mat-label>
                  <textarea matInput formControlName="fundamentacao" rows="5"
                            placeholder="Sintetize a decisao da comissao e sua fundamentacao..."></textarea>
                  @if (decidirForm.get('fundamentacao')!.hasError('required') && decidirForm.get('fundamentacao')!.touched) {
                    <mat-error>Fundamentacao e obrigatoria</mat-error>
                  }
                  @if (decidirForm.get('fundamentacao')!.hasError('minlength') && decidirForm.get('fundamentacao')!.touched) {
                    <mat-error>Minimo de 50 caracteres</mat-error>
                  }
                </mat-form-field>

                <div class="form-actions">
                  <button mat-button type="button"
                          (click)="acaoAtiva.set(null)"
                          [disabled]="saving()">
                    Cancelar
                  </button>
                  <button mat-raised-button color="primary"
                          (click)="confirmarDecisao(l.id)"
                          [disabled]="decidirForm.invalid || saving()">
                    @if (saving()) {
                      <ng-container>
                        <mat-spinner diameter="18" color="accent"></mat-spinner>
                        Salvando...
                      </ng-container>
                    } @else {
                      <ng-container>
                        <mat-icon>assignment_turned_in</mat-icon>
                        Confirmar Decisao
                      </ng-container>
                    }
                  </button>
                </div>
              </form>
            }
          </mat-card-content>
        </mat-card>
      }

      <!-- ═══════════════════════════════════════════════════════════
           RESULTADO FINAL (status encerrado)
           ═══════════════════════════════════════════════════════════ -->
      @if (l.status === 'RECURSO_DEFERIDO' || l.status === 'RECURSO_INDEFERIDO') {
        <mat-card appearance="outlined" class="section-card resultado-card"
                  [class.deferido]="l.status === 'RECURSO_DEFERIDO'"
                  [class.indeferido]="l.status === 'RECURSO_INDEFERIDO'">
          <mat-card-content>
            <div class="resultado-row">
              <mat-icon>
                {{ l.status === 'RECURSO_DEFERIDO' ? 'check_circle' : 'cancel' }}
              </mat-icon>
              <div>
                <strong>
                  {{ l.status === 'RECURSO_DEFERIDO' ? 'Recurso Deferido' : 'Recurso Indeferido' }}
                </strong>
                @if (l.decisaoRecurso) {
                  <p class="resultado-texto">{{ l.decisaoRecurso }}</p>
                }
              </div>
            </div>
          </mat-card-content>
        </mat-card>
      }

      <!-- Painel informativo: recurso recebido, aguardando triagem (visao apenas leitura) -->
      @if (l.status === 'RECURSO_SUBMETIDO' && !podeTriar) {
        <mat-card appearance="outlined" class="section-card info-card">
          <mat-card-content>
            <div class="info-row">
              <mat-icon>schedule</mat-icon>
              <span>Recurso recebido e aguardando triagem pela administracao.</span>
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
    .radio-group {
      margin: 12px 0 4px;
    }
    .radio-label {
      font-size: 12px;
      color: #666;
      display: block;
      margin-bottom: 8px;
    }
    .radio-row {
      display: flex;
      gap: 24px;
    }
    .radio-error {
      color: #f44336;
      font-size: 12px;
      margin: 4px 0 0;
    }
    .form-actions {
      display: flex;
      gap: 12px;
      justify-content: flex-end;
      margin-top: 16px;
      padding-top: 12px;
      border-top: 1px solid #f0f0f0;
    }
    .resultado-card {
      border-left: 4px solid #9e9e9e;
    }
    .resultado-card.deferido {
      border-left-color: #27ae60;
    }
    .resultado-card.indeferido {
      border-left-color: #e74c3c;
    }
    .resultado-row {
      display: flex;
      align-items: flex-start;
      gap: 12px;
    }
    .resultado-row mat-icon {
      font-size: 28px;
      width: 28px;
      height: 28px;
    }
    .deferido .resultado-row mat-icon { color: #27ae60; }
    .indeferido .resultado-row mat-icon { color: #e74c3c; }
    .resultado-texto {
      font-size: 13px;
      color: #555;
      margin: 4px 0 0;
      line-height: 1.5;
    }
    .info-card {
      border-left: 4px solid #f39c12;
    }
    .info-row {
      display: flex;
      align-items: center;
      gap: 10px;
      font-size: 14px;
      color: #7f6000;
    }
    .info-row mat-icon {
      color: #f39c12;
    }
  `]
})
export class RecursoDetalheComponent implements OnInit {

  private readonly svc   = inject(LicenciamentoService);
  private readonly auth  = inject(AuthService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly fb    = inject(FormBuilder);

  lic      = signal<LicenciamentoDTO | null>(null);
  loading  = signal(true);
  saving   = signal(false);
  error    = signal<string | null>(null);
  acaoAtiva = signal<AcaoAtiva>(null);

  /**
   * Verdadeiro para ADMIN e CHEFE_SSEG_BBM.
   * Controla acoes de triagem (aceitar/recusar) e decisao final.
   */
  readonly podeTriar = this.auth.hasAnyRole(['ADMIN', 'CHEFE_SSEG_BBM']);

  /**
   * Verdadeiro para ANALISTA e CHEFE_SSEG_BBM.
   * Controla a acao de votacao na comissao.
   */
  readonly podeVotar = this.auth.hasAnyRole(['ANALISTA', 'CHEFE_SSEG_BBM']);

  recusarForm!: FormGroup;
  votarForm!:   FormGroup;
  decidirForm!: FormGroup;

  ngOnInit(): void {
    this.recusarForm = this.fb.group({
      motivo: ['', [Validators.required, Validators.minLength(20)]]
    });

    this.votarForm = this.fb.group({
      decisao:      ['', Validators.required],
      justificativa: ['', [Validators.required, Validators.minLength(30)]]
    });

    this.decidirForm = this.fb.group({
      decisao:      ['', Validators.required],
      fundamentacao: ['', [Validators.required, Validators.minLength(50)]]
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
    this.router.navigate(['/app/recursos']);
  }

  aceitarRecurso(id: number): void {
    this.saving.set(true);
    this.error.set(null);
    this.svc.aceitarRecurso(id).subscribe({
      next: updated => {
        this.lic.set(updated);
        this.saving.set(false);
      },
      error: err => {
        const msg = err?.error?.message ?? err?.message ?? 'Erro desconhecido';
        this.error.set(`Nao foi possivel aceitar o recurso: ${msg}`);
        this.saving.set(false);
        console.error(err);
      }
    });
  }

  confirmarRecusa(id: number): void {
    if (this.recusarForm.invalid) return;
    this.saving.set(true);
    this.error.set(null);
    this.svc.recusarRecurso(id, this.recusarForm.value).subscribe({
      next: updated => {
        this.lic.set(updated);
        this.acaoAtiva.set(null);
        this.saving.set(false);
        this.router.navigate(['/app/recursos']);
      },
      error: err => {
        const msg = err?.error?.message ?? err?.message ?? 'Erro desconhecido';
        this.error.set(`Nao foi possivel recusar o recurso: ${msg}`);
        this.saving.set(false);
        console.error(err);
      }
    });
  }

  confirmarVoto(id: number): void {
    if (this.votarForm.invalid) return;
    this.saving.set(true);
    this.error.set(null);
    this.svc.votarRecurso(id, this.votarForm.value).subscribe({
      next: updated => {
        this.lic.set(updated);
        this.acaoAtiva.set(null);
        this.votarForm.reset();
        this.saving.set(false);
        this.router.navigate(['/app/recursos']);
      },
      error: err => {
        const msg = err?.error?.message ?? err?.message ?? 'Erro desconhecido';
        this.error.set(`Nao foi possivel registrar o voto: ${msg}`);
        this.saving.set(false);
        console.error(err);
      }
    });
  }

  confirmarDecisao(id: number): void {
    if (this.decidirForm.invalid) return;
    this.saving.set(true);
    this.error.set(null);
    this.svc.decidirRecurso(id, this.decidirForm.value).subscribe({
      next: updated => {
        this.lic.set(updated);
        this.acaoAtiva.set(null);
        this.saving.set(false);
        this.router.navigate(['/app/recursos']);
      },
      error: err => {
        const msg = err?.error?.message ?? err?.message ?? 'Erro desconhecido';
        this.error.set(`Nao foi possivel registrar a decisao: ${msg}`);
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
