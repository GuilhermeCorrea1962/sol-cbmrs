import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule } from '@angular/forms';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatDividerModule } from '@angular/material/divider';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { LicenciamentoService } from '../../../core/services/licenciamento.service';
import { AuthService } from '../../../core/services/auth.service';
import {
  LicenciamentoDTO,
  StatusLicenciamento,
  STATUS_LABEL,
  STATUS_COLOR
} from '../../../core/models/licenciamento.model';
import { LoadingComponent } from '../../../shared/components/loading/loading.component';
import { ErrorAlertComponent } from '../../../shared/components/error-alert/error-alert.component';

@Component({
  selector: 'sol-licenciamento-detalhe',
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
    LoadingComponent,
    ErrorAlertComponent,
  ],
  template: `
    <sol-loading [show]="loading()" message="Carregando licenciamento..." />
    <sol-error-alert [message]="error()" (dismissed)="error.set(null)" />

    <!-- Botao voltar -->
    <div class="page-header">
      <a mat-button routerLink="/app/licenciamentos">
        <mat-icon>arrow_back</mat-icon>
        Voltar para a lista
      </a>
    </div>

    @if (lic(); as l) {

      <!-- Atalho de analise tecnica — visivel apenas para ANALISTA/CHEFE quando o
           processo esta em um status que admite acao do analista -->
      @if (podeAnalisar && (l.status === 'ANALISE_PENDENTE' || l.status === 'EM_ANALISE')) {
        <div class="analise-action-bar">
          <a mat-raised-button color="primary"
             [routerLink]="['/app/analise', l.id]">
            <mat-icon>rate_review</mat-icon>
            Abrir Analise Tecnica
          </a>
        </div>
      }

      @if (podeVistoriar && (l.status === 'VISTORIA_PENDENTE' || l.status === 'EM_VISTORIA' || l.status === 'EM_VISTORIA_RENOVACAO')) {
        <div class="vistoria-action-bar">
          <a mat-raised-button color="accent"
             [routerLink]="['/app/vistorias', l.id]">
            <mat-icon>fact_check</mat-icon>
            Abrir Vistoria
          </a>
        </div>
      }

      @if (podeEmitirAppci && l.status === 'PRPCI_EMITIDO') {
        <div class="appci-action-bar">
          <a mat-raised-button color="primary"
             [routerLink]="['/app/appci', l.id]">
            <mat-icon>workspace_premium</mat-icon>
            Emitir APPCI
          </a>
        </div>
      }

      <!-- Sprint F7: Submeter Recurso (RT/cidadao — nao exibido para staff) -->
      @if (podeSubmeterRecurso && (l.status === 'CIA_EMITIDO' || l.status === 'CIV_EMITIDO')) {
        <div class="recurso-action-bar">
          @if (!recursoAberto()) {
            <button mat-raised-button color="warn" (click)="recursoAberto.set(true)">
              <mat-icon>gavel</mat-icon>
              Submeter Recurso
            </button>
          } @else {
            <mat-card appearance="outlined" class="recurso-form-card">
              <mat-card-header>
                <mat-icon mat-card-avatar>gavel</mat-icon>
                <mat-card-title>Submeter Recurso</mat-card-title>
                <mat-card-subtitle>
                  Informe a justificativa para contestar o
                  {{ l.status === 'CIA_EMITIDO' ? 'CIA (Comunicado de Inconformidade na Analise)' : 'CIV (Comunicado de Inconformidade na Vistoria)' }}
                  emitido.
                </mat-card-subtitle>
              </mat-card-header>
              <mat-card-content>
                <form [formGroup]="recursoForm">
                  <mat-form-field appearance="outline" class="field-full">
                    <mat-label>Justificativa</mat-label>
                    <textarea matInput formControlName="justificativa"
                              rows="6"
                              placeholder="Descreva os motivos pelos quais voce contesta as inconformidades apontadas..."></textarea>
                    <mat-hint align="end">
                      {{ recursoForm.get('justificativa')!.value?.length ?? 0 }} / min 50
                    </mat-hint>
                    @if (recursoForm.get('justificativa')!.hasError('required') && recursoForm.get('justificativa')!.touched) {
                      <mat-error>Justificativa e obrigatoria</mat-error>
                    }
                    @if (recursoForm.get('justificativa')!.hasError('minlength') && recursoForm.get('justificativa')!.touched) {
                      <mat-error>Minimo de 50 caracteres</mat-error>
                    }
                  </mat-form-field>
                </form>
              </mat-card-content>
              <mat-card-actions align="end">
                <button mat-button type="button"
                        (click)="recursoAberto.set(false)"
                        [disabled]="salvandoRecurso()">
                  Cancelar
                </button>
                <button mat-raised-button color="warn"
                        (click)="confirmarRecurso(l.id)"
                        [disabled]="recursoForm.invalid || salvandoRecurso()">
                  @if (salvandoRecurso()) {
                    <ng-container>
                      <mat-spinner diameter="18" color="accent"></mat-spinner>
                      Enviando...
                    </ng-container>
                  } @else {
                    <ng-container>
                      <mat-icon>gavel</mat-icon>
                      Confirmar Recurso
                    </ng-container>
                  }
                </button>
              </mat-card-actions>
            </mat-card>
          }
        </div>
      }

      <!-- Sprint F8: Solicitar Troca de RT (RT/cidadao — nao exibido para staff) -->
      @if (podeSubmeterTroca && isStatusAtivoParaTroca(l.status)) {
        @if (l.trocaPendente) {
          <!-- Painel informativo: solicitacao ja enviada, aguardando aprovacao -->
          <mat-card appearance="outlined" class="troca-info-card">
            <mat-card-content>
              <div class="troca-info-row">
                <mat-icon>hourglass_top</mat-icon>
                <span>
                  Sua solicitacao de substituicao de RT foi enviada e esta
                  aguardando aprovacao pelo administrador.
                </span>
              </div>
            </mat-card-content>
          </mat-card>
        } @else {
          <div class="troca-action-bar">
            @if (!trocaAberta()) {
              <button mat-stroked-button color="primary" (click)="trocaAberta.set(true)">
                <mat-icon>manage_accounts</mat-icon>
                Solicitar Troca de RT
              </button>
            } @else {
              <mat-card appearance="outlined" class="troca-form-card">
                <mat-card-header>
                  <mat-icon mat-card-avatar>manage_accounts</mat-icon>
                  <mat-card-title>Solicitar Substituicao de RT</mat-card-title>
                  <mat-card-subtitle>
                    Informe o motivo da sua saida como Responsavel Tecnico deste licenciamento.
                    A solicitacao sera analisada pela administracao do CBMRS.
                  </mat-card-subtitle>
                </mat-card-header>
                <mat-card-content>
                  <form [formGroup]="trocaForm">
                    <mat-form-field appearance="outline" class="field-full">
                      <mat-label>Justificativa</mat-label>
                      <textarea matInput formControlName="justificativa"
                                rows="5"
                                placeholder="Descreva o motivo pelo qual voce esta solicitando sua saida como RT..."></textarea>
                      <mat-hint align="end">
                        {{ trocaForm.get('justificativa')!.value?.length ?? 0 }} / min 30
                      </mat-hint>
                      @if (trocaForm.get('justificativa')!.hasError('required') && trocaForm.get('justificativa')!.touched) {
                        <mat-error>Justificativa e obrigatoria</mat-error>
                      }
                      @if (trocaForm.get('justificativa')!.hasError('minlength') && trocaForm.get('justificativa')!.touched) {
                        <mat-error>Minimo de 30 caracteres</mat-error>
                      }
                    </mat-form-field>
                  </form>
                </mat-card-content>
                <mat-card-actions align="end">
                  <button mat-button type="button"
                          (click)="trocaAberta.set(false)"
                          [disabled]="salvandoTroca()">
                    Cancelar
                  </button>
                  <button mat-raised-button color="primary"
                          (click)="confirmarTroca(l.id)"
                          [disabled]="trocaForm.invalid || salvandoTroca()">
                    @if (salvandoTroca()) {
                      <ng-container>
                        <mat-spinner diameter="18" color="accent"></mat-spinner>
                        Enviando...
                      </ng-container>
                    } @else {
                      <ng-container>
                        <mat-icon>send</mat-icon>
                        Enviar Solicitacao
                      </ng-container>
                    }
                  </button>
                </mat-card-actions>
              </mat-card>
            }
          </div>
        }
      }

      <!-- Secao: Identificacao -->
      <mat-card class="section-card" appearance="outlined">
        <mat-card-header>
          <mat-card-title>{{ l.numeroPpci ?? 'Licenciamento sem numero' }}</mat-card-title>
          <mat-card-subtitle>
            <span class="status-badge"
                  [style.background]="getStatusColor(l.status)">
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

      <!-- Secao: Dados da Edificacao -->
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

      <!-- Secao: Endereco -->
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

      <!-- Secao: Prazos (exibida apenas quando preenchidos) -->
      @if (l.dtValidadeAppci || l.dtVencimentoPrpci) {
        <mat-card class="section-card" appearance="outlined">
          <mat-card-header>
            <mat-card-title>Prazos</mat-card-title>
          </mat-card-header>
          <mat-card-content>
            <div class="fields-grid">
              @if (l.dtValidadeAppci) {
                <div class="field">
                  <label>Validade APPCI</label>
                  <span>{{ l.dtValidadeAppci | date:'dd/MM/yyyy' }}</span>
                </div>
              }
              @if (l.dtVencimentoPrpci) {
                <div class="field">
                  <label>Vencimento PrPCI</label>
                  <span>{{ l.dtVencimentoPrpci | date:'dd/MM/yyyy' }}</span>
                </div>
              }
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
    .analise-action-bar {
      display: flex;
      justify-content: flex-end;
      margin-bottom: 16px;
    }
    .vistoria-action-bar {
      display: flex;
      justify-content: flex-end;
      margin-bottom: 16px;
    }
    .appci-action-bar {
      display: flex;
      justify-content: flex-end;
      margin-bottom: 16px;
    }
    .recurso-action-bar {
      margin-bottom: 16px;
    }
    .recurso-form-card {
      border-left: 4px solid #e74c3c;
    }
    .troca-action-bar {
      margin-bottom: 16px;
    }
    .troca-form-card {
      border-left: 4px solid #2980b9;
      margin-bottom: 16px;
    }
    .troca-info-card {
      border-left: 4px solid #f39c12;
      margin-bottom: 16px;
    }
    .troca-info-row {
      display: flex;
      align-items: center;
      gap: 10px;
      font-size: 14px;
      color: #7f6000;
    }
    .troca-info-row mat-icon {
      color: #f39c12;
    }
    .field-full {
      width: 100%;
      margin-top: 8px;
    }
    .section-card {
      margin-bottom: 16px;
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
    .fields-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
      gap: 20px;
      margin-top: 12px;
    }
    .field {
      display: flex;
      flex-direction: column;
      gap: 3px;
    }
    .field label {
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: .5px;
      color: #888;
      font-weight: 600;
    }
    .field span {
      font-size: 14px;
      color: #333;
    }
  `]
})
export class LicenciamentoDetalheComponent implements OnInit {

  private readonly svc   = inject(LicenciamentoService);
  private readonly auth  = inject(AuthService);
  private readonly route = inject(ActivatedRoute);
  private readonly fb    = inject(FormBuilder);

  lic     = signal<LicenciamentoDTO | null>(null);
  loading = signal(false);
  error   = signal<string | null>(null);

  /**
   * Verdadeiro quando o usuario autenticado tem perfil de analista.
   * Controla a exibicao do botao "Abrir Analise Tecnica" na tela de detalhe.
   */
  readonly podeAnalisar = this.auth.hasAnyRole(['ANALISTA', 'CHEFE_SSEG_BBM']);

  /**
   * Verdadeiro quando o usuario autenticado tem perfil de inspetor.
   * Controla a exibicao do botao "Abrir Vistoria" na tela de detalhe.
   */
  readonly podeVistoriar = this.auth.hasAnyRole(['INSPETOR', 'CHEFE_SSEG_BBM']);

  /**
   * Verdadeiro quando o usuario autenticado tem perfil de admin.
   * Controla a exibicao do botao "Emitir APPCI" na tela de detalhe.
   */
  readonly podeEmitirAppci = this.auth.hasAnyRole(['ADMIN', 'CHEFE_SSEG_BBM']);

  /**
   * Verdadeiro para usuarios que NAO sao staff (RT / cidadao).
   * Controla a exibicao do formulario "Submeter Recurso" na tela de detalhe.
   * O botao aparece apenas quando o status e CIA_EMITIDO ou CIV_EMITIDO.
   */
  readonly podeSubmeterRecurso = !this.auth.hasAnyRole(['ANALISTA', 'INSPETOR', 'ADMIN', 'CHEFE_SSEG_BBM']);

  /**
   * Verdadeiro para usuarios que NAO sao staff (RT / cidadao).
   * Controla a exibicao do formulario "Solicitar Troca de RT" na tela de detalhe.
   * O botao aparece quando: nao ha troca pendente e o status e ativo (nao terminal).
   */
  readonly podeSubmeterTroca = !this.auth.hasAnyRole(['ANALISTA', 'INSPETOR', 'ADMIN', 'CHEFE_SSEG_BBM']);

  /** Status terminais — troca de RT nao faz sentido nesses estados. */
  private readonly STATUSES_TERMINAL_TROCA = new Set([
    'RASCUNHO', 'DEFERIDO', 'INDEFERIDO', 'EXTINTO', 'SUSPENSO',
    'RENOVADO', 'RECURSO_DEFERIDO', 'RECURSO_INDEFERIDO',
    'APPCI_EMITIDO', 'ALVARA_VENCIDO'
  ]);

  recursoAberto   = signal(false);
  salvandoRecurso = signal(false);
  recursoForm!:   FormGroup;

  trocaAberta   = signal(false);
  salvandoTroca = signal(false);
  trocaForm!:   FormGroup;

  ngOnInit(): void {
    this.recursoForm = this.fb.group({
      justificativa: ['', [Validators.required, Validators.minLength(50)]]
    });

    this.trocaForm = this.fb.group({
      justificativa: ['', [Validators.required, Validators.minLength(30)]]
    });

    const id = Number(this.route.snapshot.paramMap.get('id'));
    this.loading.set(true);
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

  isStatusAtivoParaTroca(status: string): boolean {
    return !this.STATUSES_TERMINAL_TROCA.has(status);
  }

  confirmarTroca(id: number): void {
    if (this.trocaForm.invalid) return;
    this.salvandoTroca.set(true);
    this.error.set(null);
    this.svc.solicitarTroca(id, this.trocaForm.value).subscribe({
      next: updated => {
        this.lic.set(updated);
        this.trocaAberta.set(false);
        this.salvandoTroca.set(false);
        this.trocaForm.reset();
      },
      error: err => {
        const msg = err?.error?.message ?? err?.message ?? 'Erro desconhecido';
        this.error.set(`Nao foi possivel solicitar a troca: ${msg}`);
        this.salvandoTroca.set(false);
        console.error(err);
      }
    });
  }

  confirmarRecurso(id: number): void {
    if (this.recursoForm.invalid) return;
    this.salvandoRecurso.set(true);
    this.error.set(null);
    this.svc.submeterRecurso(id, this.recursoForm.value).subscribe({
      next: updated => {
        this.lic.set(updated);
        this.recursoAberto.set(false);
        this.salvandoRecurso.set(false);
        this.recursoForm.reset();
      },
      error: err => {
        const msg = err?.error?.message ?? err?.message ?? 'Erro desconhecido';
        this.error.set(`Nao foi possivel submeter o recurso: ${msg}`);
        this.salvandoRecurso.set(false);
        console.error(err);
      }
    });
  }

  getStatusLabel(status: StatusLicenciamento): string {
    return STATUS_LABEL[status] ?? status;
  }

  getStatusColor(status: StatusLicenciamento): string {
    return STATUS_COLOR[status] ?? '#9e9e9e';
  }
}
