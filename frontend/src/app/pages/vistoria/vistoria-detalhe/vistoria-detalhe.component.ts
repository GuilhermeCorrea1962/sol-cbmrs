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
  CivCreateDTO,
  AprovacaoVistoriaCreateDTO
} from '../../../core/models/vistoria.model';
import { LoadingComponent } from '../../../shared/components/loading/loading.component';
import { ErrorAlertComponent } from '../../../shared/components/error-alert/error-alert.component';

type AcaoAtiva = 'civ' | 'aprovar' | null;

/**
 * Sprint F5 -- Tela de Vistoria Presencial de um processo especifico (P07).
 *
 * Exibe os dados do processo e o painel de acoes para INSPETOR/CHEFE_SSEG_BBM:
 *   - VISTORIA_PENDENTE:           botao "Iniciar Vistoria" (-> EM_VISTORIA)
 *   - EM_VISTORIA / EM_VISTORIA_RENOVACAO: dois botoes:
 *       "Emitir CIV"       -> formulario de itens de nao-conformidade (-> CIV_EMITIDO)
 *       "Aprovar Vistoria" -> formulario com laudo opcional        (-> PRPCI_EMITIDO)
 *
 * Rota: /app/vistorias/:id
 * Endpoints consumidos:
 *   GET  /api/licenciamentos/{id}
 *   POST /api/licenciamentos/{id}/iniciar-vistoria
 *   POST /api/licenciamentos/{id}/civ
 *   POST /api/licenciamentos/{id}/aprovar-vistoria
 */
@Component({
  selector: 'sol-vistoria-detalhe',
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
      <a mat-button routerLink="/app/vistorias">
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

      <!-- Painel de Acoes -->
      @if (l.status === 'VISTORIA_PENDENTE' || l.status === 'EM_VISTORIA' || l.status === 'EM_VISTORIA_RENOVACAO') {
        <mat-card class="section-card action-panel" appearance="outlined">
          <mat-card-header>
            <mat-card-title>Acoes de Vistoria Presencial</mat-card-title>
          </mat-card-header>
          <mat-card-content>

            <!-- VISTORIA_PENDENTE: unica acao e assumir o processo -->
            @if (l.status === 'VISTORIA_PENDENTE') {
              <p class="action-hint">
                Clique em "Iniciar Vistoria" para assumir este processo.
                O status sera alterado para <strong>EM_VISTORIA</strong>
                e as opcoes de emissao de CIV e aprovacao serao habilitadas.
              </p>
              <button mat-raised-button color="primary"
                      [disabled]="saving()"
                      (click)="iniciarVistoria()">
                @if (saving()) {
                  <ng-container>
                    <mat-spinner diameter="18" color="accent"></mat-spinner>
                    Iniciando...
                  </ng-container>
                } @else {
                  <ng-container>
                    <mat-icon>play_circle</mat-icon>
                    Iniciar Vistoria
                  </ng-container>
                }
              </button>
            }

            <!-- EM_VISTORIA / EM_VISTORIA_RENOVACAO: duas acoes disponiveis -->
            @if (l.status === 'EM_VISTORIA' || l.status === 'EM_VISTORIA_RENOVACAO') {
              <div class="action-buttons">
                <button mat-raised-button color="warn"
                        [class.active-btn]="acaoAtiva() === 'civ'"
                        (click)="toggleAcao('civ')"
                        matTooltip="Emitir CIV -- registra nao-conformidades e concede prazo para correcao">
                  <mat-icon>report_problem</mat-icon>
                  Emitir CIV
                </button>
                <button mat-raised-button color="primary"
                        [class.active-btn]="acaoAtiva() === 'aprovar'"
                        (click)="toggleAcao('aprovar')"
                        matTooltip="Aprovar vistoria -- emite o PrPCI e avanca o processo">
                  <mat-icon>verified</mat-icon>
                  Aprovar Vistoria
                </button>
              </div>

              <!-- === FORMULARIO CIV === -->
              @if (acaoAtiva() === 'civ') {
                <mat-divider class="form-divider"></mat-divider>
                <div class="acao-form" [formGroup]="civForm">
                  <h4 class="form-title">Emitir Comunicado de Inconformidade na Vistoria (CIV)</h4>

                  <mat-form-field appearance="outline" class="field-prazo">
                    <mat-label>Prazo para correcao (dias)</mat-label>
                    <input matInput type="number"
                           formControlName="prazoCorrecaoEmDias"
                           min="1" max="365" />
                    <mat-hint>Conforme RTCBMRS N.01/2024 -- padrao 30 dias corridos</mat-hint>
                    @if (civForm.get('prazoCorrecaoEmDias')?.invalid && civForm.get('prazoCorrecaoEmDias')?.touched) {
                      <mat-error>Prazo invalido (minimo 1, maximo 365)</mat-error>
                    }
                  </mat-form-field>

                  <h5 class="items-title">
                    Itens de nao-conformidade
                    <span class="items-count">
                      ({{ itensCiv.length }} item{{ itensCiv.length !== 1 ? 's' : '' }})
                    </span>
                  </h5>

                  <div formArrayName="itens">
                    @for (ctrl of itensCivControls; track $index; let i = $index) {
                      <div class="civ-item-row" [formGroupName]="i">
                        <mat-form-field appearance="outline" class="field-descricao">
                          <mat-label>Inconformidade {{ i + 1 }}</mat-label>
                          <textarea matInput
                                    formControlName="descricao"
                                    rows="2"
                                    placeholder="Descreva objetivamente a nao-conformidade encontrada">
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
                        @if (itensCiv.length > 1) {
                          <button mat-icon-button color="warn" type="button"
                                  (click)="removerItemCiv(i)"
                                  matTooltip="Remover esta inconformidade">
                            <mat-icon>delete</mat-icon>
                          </button>
                        }
                      </div>
                    }
                  </div>

                  <button mat-stroked-button type="button"
                          class="btn-add-item"
                          (click)="adicionarItemCiv()">
                    <mat-icon>add</mat-icon>
                    Adicionar inconformidade
                  </button>

                  <mat-form-field appearance="outline" class="field-obs field-obs-top">
                    <mat-label>Observacao geral (opcional)</mat-label>
                    <textarea matInput
                              formControlName="observacaoGeral"
                              rows="3"
                              placeholder="Observacoes adicionais para o RT / responsavel pelo uso">
                    </textarea>
                  </mat-form-field>

                  <div class="form-actions">
                    <button mat-button type="button" (click)="cancelarAcao()">Cancelar</button>
                    <button mat-raised-button color="warn" type="button"
                            [disabled]="civForm.invalid || saving()"
                            (click)="confirmarCiv()">
                      @if (saving()) {
                        <ng-container>
                          <mat-spinner diameter="18" color="accent"></mat-spinner>
                          Emitindo...
                        </ng-container>
                      } @else {
                        <ng-container>
                          <mat-icon>send</mat-icon>
                          Confirmar CIV
                        </ng-container>
                      }
                    </button>
                  </div>
                </div>
              }

              <!-- === FORMULARIO APROVACAO === -->
              @if (acaoAtiva() === 'aprovar') {
                <mat-divider class="form-divider"></mat-divider>
                <div class="acao-form" [formGroup]="aprovacaoForm">
                  <h4 class="form-title">Aprovar Vistoria Presencial</h4>
                  <p class="action-hint">
                    A aprovacao da vistoria emite o PrPCI (Projeto de Prevencao e Combate a
                    Incendio Aprovado) e avanca o processo para <strong>PRPCI_EMITIDO</strong>.
                    Esta acao nao pode ser desfeita pelo sistema.
                  </p>
                  <mat-form-field appearance="outline" class="field-obs">
                    <mat-label>Laudo / observacoes do inspetor (opcional)</mat-label>
                    <textarea matInput
                              formControlName="observacao"
                              rows="4"
                              placeholder="Registro tecnico da vistoria para o historico do processo">
                    </textarea>
                    @if (aprovacaoForm.get('observacao')?.hasError('maxlength')) {
                      <mat-error>Maximo de 5000 caracteres</mat-error>
                    }
                  </mat-form-field>
                  <div class="form-actions">
                    <button mat-button type="button" (click)="cancelarAcao()">Cancelar</button>
                    <button mat-raised-button color="primary" type="button"
                            [disabled]="aprovacaoForm.invalid || saving()"
                            (click)="confirmarAprovacao()">
                      @if (saving()) {
                        <ng-container>
                          <mat-spinner diameter="18" color="accent"></mat-spinner>
                          Aprovando...
                        </ng-container>
                      } @else {
                        <ng-container>
                          <mat-icon>verified</mat-icon>
                          Confirmar Aprovacao
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
    .action-panel { border: 2px solid #ff9800; }
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
    .action-buttons { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 8px; }
    .active-btn { outline: 3px solid #333 !important; }
    .form-divider { margin: 20px 0; }
    .acao-form { padding: 8px 0; }
    .form-title { margin: 0 0 16px; font-size: 16px; font-weight: 500; color: #333; }
    .items-title { margin: 0 0 12px; font-size: 14px; font-weight: 500; }
    .items-count { font-weight: normal; color: #888; }
    .civ-item-row {
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
export class VistoriaDetalheComponent implements OnInit {

  private readonly svc    = inject(LicenciamentoService);
  private readonly route  = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly fb     = inject(FormBuilder);

  lic       = signal<LicenciamentoDTO | null>(null);
  loading   = signal(false);
  error     = signal<string | null>(null);
  saving    = signal(false);
  acaoAtiva = signal<AcaoAtiva>(null);

  // Formulario CIV -- inicializado com 1 item em branco
  civForm = this.fb.group({
    prazoCorrecaoEmDias: [30, [Validators.required, Validators.min(1), Validators.max(365)]],
    observacaoGeral: [''],
    itens: this.fb.array<FormGroup>([
      this.fb.group({
        descricao:       ['', [Validators.required, Validators.maxLength(500)]],
        normaReferencia: ['', Validators.maxLength(200)]
      })
    ])
  });

  // Formulario Aprovacao
  aprovacaoForm = this.fb.group({
    observacao: ['', Validators.maxLength(5000)]
  });

  // Acessores para o FormArray de itens CIV
  get itensCiv(): FormArray<FormGroup> {
    return this.civForm.get('itens') as FormArray<FormGroup>;
  }
  get itensCivControls(): FormGroup[] {
    return this.itensCiv.controls;
  }

  ngOnInit(): void {
    const id = Number(this.route.snapshot.paramMap.get('id'));
    this.carregarLicenciamento(id);
  }

  // ---------------------------------------------------------------------------
  // Controle de acao ativa
  // ---------------------------------------------------------------------------

  toggleAcao(acao: AcaoAtiva): void {
    this.acaoAtiva.set(this.acaoAtiva() === acao ? null : acao);
  }

  cancelarAcao(): void {
    this.acaoAtiva.set(null);
  }

  // ---------------------------------------------------------------------------
  // CIV -- gerenciamento do FormArray
  // ---------------------------------------------------------------------------

  novoItemCiv(): FormGroup {
    return this.fb.group({
      descricao:       ['', [Validators.required, Validators.maxLength(500)]],
      normaReferencia: ['', Validators.maxLength(200)]
    });
  }

  adicionarItemCiv(): void {
    this.itensCiv.push(this.novoItemCiv());
  }

  removerItemCiv(i: number): void {
    if (this.itensCiv.length > 1) {
      this.itensCiv.removeAt(i);
    }
  }

  // ---------------------------------------------------------------------------
  // Acoes de vistoria
  // ---------------------------------------------------------------------------

  iniciarVistoria(): void {
    const id = this.lic()?.id;
    if (!id) return;
    this.saving.set(true);
    this.svc.iniciarVistoria(id).subscribe({
      next: updated => {
        this.lic.set(updated);
        this.saving.set(false);
      },
      error: err => {
        this.error.set('Erro ao iniciar vistoria. Tente novamente.');
        this.saving.set(false);
        console.error(err);
      }
    });
  }

  confirmarCiv(): void {
    if (this.civForm.invalid) return;
    const id = this.lic()?.id;
    if (!id) return;

    this.saving.set(true);
    const dto: CivCreateDTO = {
      prazoCorrecaoEmDias: this.civForm.value.prazoCorrecaoEmDias!,
      observacaoGeral: this.civForm.value.observacaoGeral || undefined,
      itens: this.itensCiv.value.map((v: { descricao: string; normaReferencia: string }) => ({
        descricao: v.descricao,
        normaReferencia: v.normaReferencia || undefined
      }))
    };

    this.svc.emitirCiv(id, dto).subscribe({
      next: updated => {
        this.lic.set(updated);
        this.acaoAtiva.set(null);
        this.saving.set(false);
        this.resetarFormCiv();
      },
      error: err => {
        this.error.set('Erro ao emitir CIV. Verifique os dados e tente novamente.');
        this.saving.set(false);
        console.error(err);
      }
    });
  }

  confirmarAprovacao(): void {
    if (this.aprovacaoForm.invalid) return;
    const id = this.lic()?.id;
    if (!id) return;
    this.saving.set(true);
    const dto: AprovacaoVistoriaCreateDTO = {
      observacao: this.aprovacaoForm.value.observacao || undefined
    };
    this.svc.aprovarVistoria(id, dto).subscribe({
      next: () => {
        this.saving.set(false);
        this.router.navigate(['/app/vistorias']);
      },
      error: err => {
        this.error.set('Erro ao aprovar vistoria. Tente novamente.');
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

  private resetarFormCiv(): void {
    while (this.itensCiv.length > 0) this.itensCiv.removeAt(0);
    this.itensCiv.push(this.novoItemCiv());
    this.civForm.patchValue({ prazoCorrecaoEmDias: 30, observacaoGeral: '' });
    this.civForm.markAsPristine();
    this.civForm.markAsUntouched();
  }
}
