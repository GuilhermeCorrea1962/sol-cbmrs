import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import {
  FormBuilder, FormArray, FormGroup,
  ReactiveFormsModule, Validators
} from '@angular/forms';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatDividerModule } from '@angular/material/divider';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatTooltipModule } from '@angular/material/tooltip';
import { LicenciamentoService } from '../../../core/services/licenciamento.service';
import {
  LicenciamentoDTO,
  StatusLicenciamento,
  STATUS_LABEL,
  STATUS_COLOR
} from '../../../core/models/licenciamento.model';
import {
  CiaCreateDTO,
  DeferimentoCreateDTO,
  IndeferimentoCreateDTO
} from '../../../core/models/analise.model';
import { LoadingComponent } from '../../../shared/components/loading/loading.component';
import { ErrorAlertComponent } from '../../../shared/components/error-alert/error-alert.component';

type AcaoAtiva = 'cia' | 'deferir' | 'indeferir' | null;

/**
 * Sprint F4 — Tela de Analise Tecnica de um licenciamento especifico.
 *
 * Exibe os dados do processo e o painel de acoes para ANALISTA/CHEFE_SSEG_BBM:
 *   - ANALISE_PENDENTE: botao "Iniciar Analise" (-> EM_ANALISE)
 *   - EM_ANALISE: tres acoes em linha — Emitir CIA / Deferir / Indeferir
 *
 * Rota: /app/analise/:id
 * Endpoints consumidos:
 *   GET  /api/licenciamentos/{id}
 *   POST /api/licenciamentos/{id}/iniciar-analise
 *   POST /api/licenciamentos/{id}/cia
 *   POST /api/licenciamentos/{id}/deferir
 *   POST /api/licenciamentos/{id}/indeferir
 */
@Component({
  selector: 'sol-licenciamento-analise',
  standalone: true,
  imports: [
    CommonModule,
    RouterLink,
    ReactiveFormsModule,
    MatCardModule,
    MatButtonModule,
    MatIconModule,
    MatDividerModule,
    MatFormFieldModule,
    MatInputModule,
    MatProgressSpinnerModule,
    MatTooltipModule,
    LoadingComponent,
    ErrorAlertComponent,
  ],
  template: `
    <sol-loading [show]="loading()" message="Carregando processo..." />
    <sol-error-alert [message]="error()" (dismissed)="error.set(null)" />

    <div class="page-header">
      <a mat-button routerLink="/app/analise">
        <mat-icon>arrow_back</mat-icon>
        Voltar para a fila
      </a>
    </div>

    @if (lic(); as l) {

      <!-- Identificacao -->
      <mat-card class="section-card" appearance="outlined">
        <mat-card-header>
          <mat-card-title>{{ l.numeroPpci ?? 'Processo sem numero' }}</mat-card-title>
          <mat-card-subtitle>
            <span class="status-badge" [style.background]="getStatusColor(l.status)">
              {{ getStatusLabel(l.status) }}
            </span>
            &nbsp; Tipo: <strong>{{ l.tipo }}</strong>
          </mat-card-subtitle>
        </mat-card-header>
        <mat-card-content>
          <div class="meta-row">
            <span class="meta-item">
              <mat-icon class="meta-icon">calendar_today</mat-icon>
              Criado em {{ l.dataCriacao | date:'dd/MM/yyyy HH:mm' }}
            </span>
            <span class="meta-item">
              <mat-icon class="meta-icon">update</mat-icon>
              Atualizado em {{ l.dataAtualizacao | date:'dd/MM/yyyy HH:mm' }}
            </span>
          </div>
        </mat-card-content>
      </mat-card>

      <!-- Dados da Edificacao -->
      <mat-card class="section-card" appearance="outlined">
        <mat-card-header>
          <mat-card-title>Dados da Edificacao</mat-card-title>
        </mat-card-header>
        <mat-card-content>
          <div class="fields-grid">
            <div class="field">
              <label>Area Construida</label>
              <span>{{ l.areaConstruida != null ? (l.areaConstruida | number:'1.2-2') + ' m2' : '-' }}</span>
            </div>
            <div class="field">
              <label>Altura Maxima</label>
              <span>{{ l.alturaMaxima != null ? (l.alturaMaxima | number:'1.2-2') + ' m' : '-' }}</span>
            </div>
            <div class="field">
              <label>Numero de Pavimentos</label>
              <span>{{ l.numPavimentos ?? '-' }}</span>
            </div>
            <div class="field">
              <label>Tipo de Ocupacao</label>
              <span>{{ l.tipoOcupacao ?? '-' }}</span>
            </div>
            <div class="field">
              <label>Uso Predominante</label>
              <span>{{ l.usoPredominante ?? '-' }}</span>
            </div>
          </div>
        </mat-card-content>
      </mat-card>

      <!-- Endereco -->
      <mat-card class="section-card" appearance="outlined">
        <mat-card-header>
          <mat-card-title>Endereco da Edificacao</mat-card-title>
        </mat-card-header>
        <mat-card-content>
          <div class="fields-grid">
            <div class="field">
              <label>Logradouro</label>
              <span>{{ l.endereco.logradouro }}, {{ l.endereco.numero }}</span>
            </div>
            @if (l.endereco.complemento) {
              <div class="field">
                <label>Complemento</label>
                <span>{{ l.endereco.complemento }}</span>
              </div>
            }
            <div class="field">
              <label>Bairro</label>
              <span>{{ l.endereco.bairro }}</span>
            </div>
            <div class="field">
              <label>Municipio / UF</label>
              <span>{{ l.endereco.municipio }}/{{ l.endereco.uf }}</span>
            </div>
            <div class="field">
              <label>CEP</label>
              <span>{{ l.endereco.cep }}</span>
            </div>
          </div>
        </mat-card-content>
      </mat-card>

      <!-- Painel de Acoes — visivel apenas quando o status admite acao do analista -->
      @if (l.status === 'ANALISE_PENDENTE' || l.status === 'EM_ANALISE') {
        <mat-card class="section-card action-panel" appearance="outlined">
          <mat-card-header>
            <mat-card-title>Acoes de Analise Tecnica</mat-card-title>
          </mat-card-header>
          <mat-card-content>

            <!-- ANALISE_PENDENTE: unica acao e assumir o processo -->
            @if (l.status === 'ANALISE_PENDENTE') {
              <p class="action-hint">
                Clique em "Iniciar Analise" para assumir este processo.
                O status sera alterado para <strong>EM_ANALISE</strong>
                e as opcoes de CIA, Deferimento e Indeferimento serao habilitadas.
              </p>
              <button mat-raised-button color="primary"
                      [disabled]="saving()"
                      (click)="iniciarAnalise()">
                @if (saving()) {
                  <ng-container>
                    <mat-spinner diameter="18" color="accent"></mat-spinner>
                    Iniciando...
                  </ng-container>
                } @else {
                  <ng-container>
                    <mat-icon>play_circle</mat-icon>
                    Iniciar Analise
                  </ng-container>
                }
              </button>
            }

            <!-- EM_ANALISE: tres acoes disponiveis -->
            @if (l.status === 'EM_ANALISE') {
              <div class="action-buttons">
                <button mat-raised-button color="warn"
                        [class.active-btn]="acaoAtiva() === 'cia'"
                        (click)="toggleAcao('cia')"
                        matTooltip="Emitir Comunicado de Inconformidade na Analise — solicita correcoes ao RT">
                  <mat-icon>report_problem</mat-icon>
                  Emitir CIA
                </button>
                <button mat-raised-button color="primary"
                        [class.active-btn]="acaoAtiva() === 'deferir'"
                        (click)="toggleAcao('deferir')"
                        matTooltip="Deferir a analise — processo avanca para vistoria ou deferimento final">
                  <mat-icon>check_circle</mat-icon>
                  Deferir
                </button>
                <button mat-stroked-button color="warn"
                        [class.active-btn]="acaoAtiva() === 'indeferir'"
                        (click)="toggleAcao('indeferir')"
                        matTooltip="Indeferir — encerra o processo com status INDEFERIDO">
                  <mat-icon>cancel</mat-icon>
                  Indeferir
                </button>
              </div>

              <!-- === FORMULARIO CIA === -->
              @if (acaoAtiva() === 'cia') {
                <mat-divider class="form-divider"></mat-divider>
                <div class="acao-form" [formGroup]="ciaForm">
                  <h4 class="form-title">Emitir Comunicado de Inconformidade na Analise (CIA)</h4>

                  <mat-form-field appearance="outline" class="field-prazo">
                    <mat-label>Prazo para correcao (dias)</mat-label>
                    <input matInput type="number"
                           formControlName="prazoCorrecaoEmDias"
                           min="1" max="365" />
                    <mat-hint>Conforme RTCBMRS N.01/2024 — padrao 30 dias corridos</mat-hint>
                    @if (ciaForm.get('prazoCorrecaoEmDias')?.invalid && ciaForm.get('prazoCorrecaoEmDias')?.touched) {
                      <mat-error>Prazo invalido (minimo 1, maximo 365)</mat-error>
                    }
                  </mat-form-field>

                  <h5 class="items-title">
                    Itens de nao-conformidade
                    <span class="items-count">
                      ({{ itensCia.length }} item{{ itensCia.length !== 1 ? 's' : '' }})
                    </span>
                  </h5>

                  <div formArrayName="itens">
                    @for (ctrl of itensCiaControls; track $index; let i = $index) {
                      <div class="cia-item-row" [formGroupName]="i">
                        <mat-form-field appearance="outline" class="field-descricao">
                          <mat-label>Inconformidade {{ i + 1 }}</mat-label>
                          <textarea matInput
                                    formControlName="descricao"
                                    rows="2"
                                    placeholder="Descreva objetivamente a inconformidade encontrada no projeto">
                          </textarea>
                          @if (ctrl.get('descricao')?.hasError('required') && ctrl.get('descricao')?.touched) {
                            <mat-error>Descricao e obrigatoria</mat-error>
                          }
                        </mat-form-field>
                        <mat-form-field appearance="outline" class="field-norma">
                          <mat-label>Referencia normativa (opcional)</mat-label>
                          <input matInput
                                 formControlName="normaReferencia"
                                 placeholder="Ex: RTCBMRS N.01/2024 Art. 15" />
                        </mat-form-field>
                        @if (itensCia.length > 1) {
                          <button mat-icon-button color="warn" type="button"
                                  (click)="removerItemCia(i)"
                                  matTooltip="Remover esta inconformidade">
                            <mat-icon>delete</mat-icon>
                          </button>
                        }
                      </div>
                    }
                  </div>

                  <button mat-stroked-button type="button"
                          class="btn-add-item"
                          (click)="adicionarItemCia()">
                    <mat-icon>add</mat-icon>
                    Adicionar inconformidade
                  </button>

                  <mat-form-field appearance="outline" class="field-obs field-obs-top">
                    <mat-label>Observacao geral (opcional)</mat-label>
                    <textarea matInput
                              formControlName="observacaoGeral"
                              rows="3"
                              placeholder="Observacoes adicionais para o RT / cidadao">
                    </textarea>
                  </mat-form-field>

                  <div class="form-actions">
                    <button mat-button type="button" (click)="cancelarAcao()">Cancelar</button>
                    <button mat-raised-button color="warn" type="button"
                            [disabled]="ciaForm.invalid || saving()"
                            (click)="confirmarCia()">
                      @if (saving()) {
                        <ng-container>
                          <mat-spinner diameter="18" color="accent"></mat-spinner>
                          Emitindo...
                        </ng-container>
                      } @else {
                        <ng-container>
                          <mat-icon>send</mat-icon>
                          Confirmar CIA
                        </ng-container>
                      }
                    </button>
                  </div>
                </div>
              }

              <!-- === FORMULARIO DEFERIMENTO === -->
              @if (acaoAtiva() === 'deferir') {
                <mat-divider class="form-divider"></mat-divider>
                <div class="acao-form" [formGroup]="deferimentoForm">
                  <h4 class="form-title">Deferir Analise Tecnica</h4>
                  <p class="action-hint">
                    O processo sera encaminhado para a proxima etapa do fluxo:<br>
                    <strong>PPCI</strong> — avanca para <strong>VISTORIA_PENDENTE</strong>.<br>
                    <strong>PSPCIM</strong> — recebe status <strong>DEFERIDO</strong>
                    (sem exigencia de vistoria presencial).
                  </p>
                  <mat-form-field appearance="outline" class="field-obs">
                    <mat-label>Observacao tecnica (opcional)</mat-label>
                    <textarea matInput
                              formControlName="observacao"
                              rows="3"
                              placeholder="Observacoes registradas no historico do processo">
                    </textarea>
                  </mat-form-field>
                  <div class="form-actions">
                    <button mat-button type="button" (click)="cancelarAcao()">Cancelar</button>
                    <button mat-raised-button color="primary" type="button"
                            [disabled]="saving()"
                            (click)="confirmarDeferimento()">
                      @if (saving()) {
                        <ng-container>
                          <mat-spinner diameter="18" color="accent"></mat-spinner>
                          Deferindo...
                        </ng-container>
                      } @else {
                        <ng-container>
                          <mat-icon>check_circle</mat-icon>
                          Confirmar Deferimento
                        </ng-container>
                      }
                    </button>
                  </div>
                </div>
              }

              <!-- === FORMULARIO INDEFERIMENTO === -->
              @if (acaoAtiva() === 'indeferir') {
                <mat-divider class="form-divider"></mat-divider>
                <div class="acao-form" [formGroup]="indeferimentoForm">
                  <h4 class="form-title">Indeferir Analise Tecnica</h4>
                  <p class="action-hint warn-text">
                    O indeferimento encerra o processo com status <strong>INDEFERIDO</strong>.
                    Esta acao nao pode ser desfeita pelo sistema.
                    Registre a justificativa tecnica completa antes de confirmar.
                  </p>
                  <mat-form-field appearance="outline" class="field-obs">
                    <mat-label>Justificativa do indeferimento *</mat-label>
                    <textarea matInput
                              formControlName="justificativa"
                              rows="5"
                              placeholder="Descreva a justificativa tecnica completa para o indeferimento (minimo 20 caracteres)">
                    </textarea>
                    @if (indeferimentoForm.get('justificativa')?.hasError('required') && indeferimentoForm.get('justificativa')?.touched) {
                      <mat-error>Justificativa e obrigatoria</mat-error>
                    }
                    @if (indeferimentoForm.get('justificativa')?.hasError('minlength')) {
                      <mat-error>Justificativa deve ter ao menos 20 caracteres</mat-error>
                    }
                  </mat-form-field>
                  <div class="form-actions">
                    <button mat-button type="button" (click)="cancelarAcao()">Cancelar</button>
                    <button mat-raised-button color="warn" type="button"
                            [disabled]="indeferimentoForm.invalid || saving()"
                            (click)="confirmarIndeferimento()">
                      @if (saving()) {
                        <ng-container>
                          <mat-spinner diameter="18" color="accent"></mat-spinner>
                          Indeferindo...
                        </ng-container>
                      } @else {
                        <ng-container>
                          <mat-icon>cancel</mat-icon>
                          Confirmar Indeferimento
                        </ng-container>
                      }
                    </button>
                  </div>
                </div>
              }
            }
          </mat-card-content>
        </mat-card>
      }
    }
  `,
  styles: [`
    .page-header { margin-bottom: 16px; }
    .section-card { margin-bottom: 16px; }
    .action-panel { border: 2px solid #3498db; }
    .status-badge {
      display: inline-block; padding: 3px 10px; border-radius: 12px;
      font-size: 12px; font-weight: 500; color: #fff;
    }
    .meta-row { display: flex; gap: 24px; flex-wrap: wrap; margin-top: 12px; }
    .meta-item { display: flex; align-items: center; gap: 4px; font-size: 13px; color: #666; }
    .meta-icon { font-size: 16px; width: 16px; height: 16px; }
    .fields-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
      gap: 20px; margin-top: 12px;
    }
    .field { display: flex; flex-direction: column; gap: 3px; }
    .field label {
      font-size: 11px; text-transform: uppercase; letter-spacing: .5px;
      color: #888; font-weight: 600;
    }
    .field span { font-size: 14px; color: #333; }
    .action-hint { color: #555; font-size: 14px; margin-bottom: 16px; line-height: 1.6; }
    .warn-text { color: #c0392b !important; }
    .action-buttons { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 8px; }
    .active-btn { outline: 3px solid #333 !important; }
    .form-divider { margin: 20px 0; }
    .acao-form { padding: 8px 0; }
    .form-title { margin: 0 0 16px; font-size: 16px; font-weight: 500; color: #333; }
    .items-title { margin: 0 0 12px; font-size: 14px; font-weight: 500; }
    .items-count { font-weight: normal; color: #888; }
    .cia-item-row {
      display: flex; gap: 12px; align-items: flex-start;
      margin-bottom: 8px; flex-wrap: wrap;
    }
    .field-prazo { width: 220px; }
    .field-descricao { flex: 2; min-width: 280px; }
    .field-norma { flex: 1; min-width: 200px; }
    .field-obs { width: 100%; }
    .field-obs-top { margin-top: 16px; }
    .btn-add-item { margin-top: 4px; }
    .form-actions {
      display: flex; gap: 12px; justify-content: flex-end; margin-top: 16px;
    }
  `]
})
export class LicenciamentoAnaliseComponent implements OnInit {

  private readonly svc    = inject(LicenciamentoService);
  private readonly route  = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly fb     = inject(FormBuilder);

  lic       = signal<LicenciamentoDTO | null>(null);
  loading   = signal(false);
  error     = signal<string | null>(null);
  saving    = signal(false);
  acaoAtiva = signal<AcaoAtiva>(null);

  // Formulario CIA — inicializado com 1 item em branco
  ciaForm = this.fb.group({
    prazoCorrecaoEmDias: [30, [Validators.required, Validators.min(1), Validators.max(365)]],
    observacaoGeral: [''],
    itens: this.fb.array<FormGroup>([
      this.fb.group({
        descricao:       ['', [Validators.required, Validators.maxLength(500)]],
        normaReferencia: ['', Validators.maxLength(200)]
      })
    ])
  });

  // Formulario Deferimento
  deferimentoForm = this.fb.group({
    observacao: ['', Validators.maxLength(2000)]
  });

  // Formulario Indeferimento
  indeferimentoForm = this.fb.group({
    justificativa: ['', [Validators.required, Validators.minLength(20), Validators.maxLength(2000)]]
  });

  // Acessores para o FormArray de itens CIA
  get itensCia(): FormArray<FormGroup> {
    return this.ciaForm.get('itens') as FormArray<FormGroup>;
  }
  get itensCiaControls(): FormGroup[] {
    return this.itensCia.controls;
  }

  ngOnInit(): void {
    const id = Number(this.route.snapshot.paramMap.get('id'));
    this.carregarLicenciamento(id);
  }

  // ---------------------------------------------------------------------------
  // Controle de acao ativa (toggle: clique no mesmo botao fecha o formulario)
  // ---------------------------------------------------------------------------

  toggleAcao(acao: AcaoAtiva): void {
    this.acaoAtiva.set(this.acaoAtiva() === acao ? null : acao);
  }

  cancelarAcao(): void {
    this.acaoAtiva.set(null);
  }

  // ---------------------------------------------------------------------------
  // CIA — gerenciamento do FormArray
  // ---------------------------------------------------------------------------

  novoItemCia(): FormGroup {
    return this.fb.group({
      descricao:       ['', [Validators.required, Validators.maxLength(500)]],
      normaReferencia: ['', Validators.maxLength(200)]
    });
  }

  adicionarItemCia(): void {
    this.itensCia.push(this.novoItemCia());
  }

  removerItemCia(i: number): void {
    if (this.itensCia.length > 1) {
      this.itensCia.removeAt(i);
    }
  }

  // ---------------------------------------------------------------------------
  // Acoes de analise
  // ---------------------------------------------------------------------------

  iniciarAnalise(): void {
    const id = this.lic()?.id;
    if (!id) return;
    this.saving.set(true);
    this.svc.iniciarAnalise(id).subscribe({
      next: updated => {
        this.lic.set(updated);
        this.saving.set(false);
      },
      error: err => {
        this.error.set('Erro ao iniciar analise. Tente novamente.');
        this.saving.set(false);
        console.error(err);
      }
    });
  }

  confirmarCia(): void {
    if (this.ciaForm.invalid) return;
    const id = this.lic()?.id;
    if (!id) return;

    this.saving.set(true);
    const dto: CiaCreateDTO = {
      prazoCorrecaoEmDias: this.ciaForm.value.prazoCorrecaoEmDias!,
      observacaoGeral: this.ciaForm.value.observacaoGeral || undefined,
      itens: this.itensCia.value.map((v: { descricao: string; normaReferencia: string }) => ({
        descricao: v.descricao,
        normaReferencia: v.normaReferencia || undefined
      }))
    };

    this.svc.emitirCia(id, dto).subscribe({
      next: updated => {
        this.lic.set(updated);
        this.acaoAtiva.set(null);
        this.saving.set(false);
        this.resetarFormCia();
      },
      error: err => {
        this.error.set('Erro ao emitir CIA. Verifique os dados e tente novamente.');
        this.saving.set(false);
        console.error(err);
      }
    });
  }

  confirmarDeferimento(): void {
    const id = this.lic()?.id;
    if (!id) return;
    this.saving.set(true);
    const dto: DeferimentoCreateDTO = {
      observacao: this.deferimentoForm.value.observacao || undefined
    };
    this.svc.deferir(id, dto).subscribe({
      next: () => {
        this.saving.set(false);
        this.router.navigate(['/app/analise']);
      },
      error: err => {
        this.error.set('Erro ao deferir o processo. Tente novamente.');
        this.saving.set(false);
        console.error(err);
      }
    });
  }

  confirmarIndeferimento(): void {
    if (this.indeferimentoForm.invalid) return;
    const id = this.lic()?.id;
    if (!id) return;
    this.saving.set(true);
    const dto: IndeferimentoCreateDTO = {
      justificativa: this.indeferimentoForm.value.justificativa as string
    };
    this.svc.indeferir(id, dto).subscribe({
      next: () => {
        this.saving.set(false);
        this.router.navigate(['/app/analise']);
      },
      error: err => {
        this.error.set('Erro ao indeferir o processo. Tente novamente.');
        this.saving.set(false);
        console.error(err);
      }
    });
  }

  getStatusLabel(s: StatusLicenciamento): string { return STATUS_LABEL[s] ?? s; }
  getStatusColor(s: StatusLicenciamento): string { return STATUS_COLOR[s] ?? '#9e9e9e'; }

  // ---------------------------------------------------------------------------
  // Privados
  // ---------------------------------------------------------------------------

  private carregarLicenciamento(id: number): void {
    this.loading.set(true);
    this.svc.getById(id).subscribe({
      next: data => {
        this.lic.set(data);
        this.loading.set(false);
      },
      error: err => {
        this.error.set('Processo nao encontrado ou sem permissao de acesso.');
        this.loading.set(false);
        console.error(err);
      }
    });
  }

  private resetarFormCia(): void {
    while (this.itensCia.length > 0) this.itensCia.removeAt(0);
    this.itensCia.push(this.novoItemCia());
    this.ciaForm.patchValue({ prazoCorrecaoEmDias: 30, observacaoGeral: '' });
    this.ciaForm.markAsPristine();
    this.ciaForm.markAsUntouched();
  }
}
