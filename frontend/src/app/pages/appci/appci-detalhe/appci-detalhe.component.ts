import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { FormBuilder, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { MatCardModule } from '@angular/material/card';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatDividerModule } from '@angular/material/divider';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { LicenciamentoService } from '../../../core/services/licenciamento.service';
import {
  LicenciamentoDTO,
  StatusLicenciamento,
  STATUS_LABEL,
  STATUS_COLOR
} from '../../../core/models/licenciamento.model';
import { AppciEmitirDTO } from '../../../core/models/appci.model';
import { LoadingComponent } from '../../../shared/components/loading/loading.component';
import { ErrorAlertComponent } from '../../../shared/components/error-alert/error-alert.component';

/**
 * Sprint F6 -- Tela de Emissao de APPCI para um processo especifico (P08).
 *
 * Exibe os dados do processo e o painel de emissao do APPCI para ADMIN/CHEFE_SSEG_BBM:
 *   - PRPCI_EMITIDO: painel "Emitir APPCI" com formulario de laudo opcional
 *       POST /api/licenciamentos/{id}/emitir-appci -> APPCI_EMITIDO
 *
 * Ao confirmar a emissao, navega para /app/appci (processo concluido para este modulo).
 *
 * Rota: /app/appci/:id
 * Endpoints consumidos:
 *   GET  /api/licenciamentos/{id}
 *   POST /api/licenciamentos/{id}/emitir-appci
 */
@Component({
  selector: 'sol-appci-detalhe',
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
    <sol-loading [show]="loading()" message="Carregando processo..." />
    <sol-error-alert [message]="error()" (dismissed)="error.set(null)" />

    <div class="page-header">
      <a mat-button routerLink="/app/appci">
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

      <!-- Prazos (se ja houver) -->
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

      <!-- Painel de Emissao de APPCI -->
      @if (l.status === 'PRPCI_EMITIDO') {
        <mat-card class="section-card action-panel" appearance="outlined">
          <mat-card-header>
            <mat-card-title>Emissao do APPCI</mat-card-title>
          </mat-card-header>
          <mat-card-content>

            @if (!formularioAberto()) {
              <p class="action-hint">
                O PrPCI foi aprovado na vistoria presencial. Clique em "Emitir APPCI" para
                emitir o Alvara de Prevencao e Protecao Contra Incendio e concluir o
                processo de licenciamento.
              </p>
              <p class="action-hint">
                A validade do APPCI (2 anos para ocupacoes habituais ou 5 anos para demais)
                sera calculada automaticamente pelo sistema com base no tipo de ocupacao
                da edificacao, conforme RTCBMRS N.01/2024.
              </p>
              <button mat-raised-button color="primary"
                      (click)="abrirFormulario()">
                <mat-icon>workspace_premium</mat-icon>
                Emitir APPCI
              </button>
            }

            @if (formularioAberto()) {
              <mat-divider class="form-divider"></mat-divider>
              <div class="acao-form" [formGroup]="appciForm">
                <h4 class="form-title">Confirmar Emissao do APPCI</h4>
                <p class="action-hint warn-text">
                  Esta acao encerra o processo com status
                  <strong>APPCI_EMITIDO</strong> e nao pode ser desfeita pelo sistema.
                  O alvara sera gerado com os dados do processo.
                </p>
                <mat-form-field appearance="outline" class="field-obs">
                  <mat-label>Observacoes / laudo (opcional)</mat-label>
                  <textarea matInput
                            formControlName="observacao"
                            rows="4"
                            placeholder="Registro tecnico para o historico do processo">
                  </textarea>
                  @if (appciForm.get('observacao')?.hasError('maxlength')) {
                    <mat-error>Maximo de 5000 caracteres</mat-error>
                  }
                </mat-form-field>
                <div class="form-actions">
                  <button mat-button type="button"
                          [disabled]="saving()"
                          (click)="cancelarFormulario()">
                    Cancelar
                  </button>
                  <button mat-raised-button color="primary" type="button"
                          [disabled]="appciForm.invalid || saving()"
                          (click)="confirmarEmissao()">
                    @if (saving()) {
                      <ng-container>
                        <mat-spinner diameter="18" color="accent"></mat-spinner>
                        Emitindo...
                      </ng-container>
                    } @else {
                      <ng-container>
                        <mat-icon>workspace_premium</mat-icon>
                        Confirmar Emissao
                      </ng-container>
                    }
                  </button>
                </div>
              </div>
            }

          </mat-card-content>
        </mat-card>
      }

      <!-- Status terminal: APPCI ja emitido -->
      @if (l.status === 'APPCI_EMITIDO') {
        <mat-card class="section-card appci-emitido-panel" appearance="outlined">
          <mat-card-content>
            <div class="appci-emitido-info">
              <mat-icon class="appci-icon">workspace_premium</mat-icon>
              <div>
                <strong>APPCI emitido com sucesso.</strong>
                <p>O processo foi concluido. O alvara esta disponivel para consulta na tela de detalhe do licenciamento.</p>
              </div>
            </div>
          </mat-card-content>
        </mat-card>
      }
    }
  `,
  styles: [`
    .page-header { margin-bottom: 16px; }
    .section-card { margin-bottom: 16px; }
    .action-panel { border: 2px solid #1976d2; }
    .appci-emitido-panel { border: 2px solid #27ae60; }
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
    .warn-text { color: #1a3a5c !important; }
    .form-divider { margin: 20px 0; }
    .acao-form { padding: 8px 0; }
    .form-title { margin: 0 0 16px; font-size: 16px; font-weight: 500; color: #333; }
    .field-obs { width: 100%; }
    .form-actions {
      display: flex; gap: 12px; justify-content: flex-end; margin-top: 16px;
    }
    .appci-emitido-info {
      display: flex; align-items: flex-start; gap: 16px; padding: 8px 0;
    }
    .appci-icon { font-size: 40px; width: 40px; height: 40px; color: #27ae60; }
    .appci-emitido-info p { margin: 4px 0 0; font-size: 14px; color: #555; }
  `]
})
export class AppciDetalheComponent implements OnInit {

  private readonly svc    = inject(LicenciamentoService);
  private readonly route  = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly fb     = inject(FormBuilder);

  lic            = signal<LicenciamentoDTO | null>(null);
  loading        = signal(false);
  error          = signal<string | null>(null);
  saving         = signal(false);
  formularioAberto = signal(false);

  appciForm: FormGroup = this.fb.group({
    observacao: ['', Validators.maxLength(5000)]
  });

  ngOnInit(): void {
    const id = Number(this.route.snapshot.paramMap.get('id'));
    this.carregarLicenciamento(id);
  }

  abrirFormulario(): void {
    this.formularioAberto.set(true);
  }

  cancelarFormulario(): void {
    this.formularioAberto.set(false);
    this.appciForm.reset();
  }

  confirmarEmissao(): void {
    if (this.appciForm.invalid) return;
    const id = this.lic()?.id;
    if (!id) return;
    this.saving.set(true);
    const dto: AppciEmitirDTO = {
      observacao: this.appciForm.value.observacao || undefined
    };
    this.svc.emitirAppci(id, dto).subscribe({
      next: () => {
        this.saving.set(false);
        this.router.navigate(['/app/appci']);
      },
      error: err => {
        this.error.set('Erro ao emitir APPCI. Tente novamente.');
        this.saving.set(false);
        console.error(err);
      }
    });
  }

  getStatusLabel(s: StatusLicenciamento): string { return STATUS_LABEL[s] ?? s; }
  getStatusColor(s: StatusLicenciamento): string { return STATUS_COLOR[s] ?? '#9e9e9e'; }

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
}
