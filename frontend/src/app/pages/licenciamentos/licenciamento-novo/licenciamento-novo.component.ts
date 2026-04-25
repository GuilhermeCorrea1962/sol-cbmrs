import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule } from '@angular/forms';
import { MatStepperModule } from '@angular/material/stepper';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatCardModule } from '@angular/material/card';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatDividerModule } from '@angular/material/divider';
import { LicenciamentoService } from '../../../core/services/licenciamento.service';
import { LicenciamentoCreateDTO, UF_OPTIONS } from '../../../core/models/licenciamento-create.model';
import { ErrorAlertComponent } from '../../../shared/components/error-alert/error-alert.component';

@Component({
  selector: 'sol-licenciamento-novo',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    MatStepperModule,
    MatFormFieldModule,
    MatInputModule,
    MatSelectModule,
    MatButtonModule,
    MatIconModule,
    MatCardModule,
    MatProgressSpinnerModule,
    MatDividerModule,
    ErrorAlertComponent,
  ],
  template: `
    <div class="page-header">
      <div>
        <h1 class="page-title">Nova Solicitacao de Licenciamento</h1>
        <p class="page-subtitle">Preencha as informacoes para iniciar o processo</p>
      </div>
    </div>

    <sol-error-alert [message]="error()" (dismissed)="error.set(null)" />

    <mat-card appearance="outlined" class="wizard-card">
      <mat-card-content>
        <mat-stepper linear #stepper>

          <!-- ═══════════════════════════════════════════════════
               PASSO 1 — Tipo de Licenciamento
               ═══════════════════════════════════════════════════ -->
          <mat-step [stepControl]="tipoForm" label="Tipo">
            <form [formGroup]="tipoForm">
              <p class="step-desc">Selecione o tipo de licenciamento a ser solicitado:</p>

              <div class="tipo-cards">
                <!-- PPCI -->
                <div class="tipo-card"
                     [class.selected]="tipoForm.get('tipo')!.value === 'PPCI'"
                     (click)="tipoForm.get('tipo')!.setValue('PPCI')"
                     role="button" tabindex="0"
                     (keydown.enter)="tipoForm.get('tipo')!.setValue('PPCI')"
                     (keydown.space)="tipoForm.get('tipo')!.setValue('PPCI')">
                  <mat-icon class="tipo-icon">local_fire_department</mat-icon>
                  <div class="tipo-name">PPCI</div>
                  <div class="tipo-desc">Plano de Prevencao e Protecao Contra Incendio</div>
                  <div class="tipo-check">
                    <mat-icon>check_circle</mat-icon>
                  </div>
                </div>

                <!-- PSPCIM -->
                <div class="tipo-card"
                     [class.selected]="tipoForm.get('tipo')!.value === 'PSPCIM'"
                     (click)="tipoForm.get('tipo')!.setValue('PSPCIM')"
                     role="button" tabindex="0"
                     (keydown.enter)="tipoForm.get('tipo')!.setValue('PSPCIM')"
                     (keydown.space)="tipoForm.get('tipo')!.setValue('PSPCIM')">
                  <mat-icon class="tipo-icon">warehouse</mat-icon>
                  <div class="tipo-name">PSPCIM</div>
                  <div class="tipo-desc">Plano de Seguranca contra Panic, Incendio e Materiais Perigosos</div>
                  <div class="tipo-check">
                    <mat-icon>check_circle</mat-icon>
                  </div>
                </div>
              </div>

              @if (tipoForm.get('tipo')!.invalid && tipoForm.get('tipo')!.touched) {
                <p class="validation-msg">Selecione o tipo de licenciamento para continuar.</p>
              }

              <div class="step-actions">
                <button mat-button type="button"
                        (click)="cancelar()">
                  Cancelar
                </button>
                <button mat-raised-button color="primary"
                        type="button"
                        matStepperNext
                        (click)="tipoForm.get('tipo')!.markAsTouched()"
                        [disabled]="tipoForm.invalid">
                  Proximo
                  <mat-icon iconPositionEnd>arrow_forward</mat-icon>
                </button>
              </div>
            </form>
          </mat-step>

          <!-- ═══════════════════════════════════════════════════
               PASSO 2 — Endereco
               ═══════════════════════════════════════════════════ -->
          <mat-step [stepControl]="enderecoForm" label="Endereco">
            <form [formGroup]="enderecoForm">
              <p class="step-desc">Informe o endereco da edificacao a ser licenciada:</p>

              <div class="form-row">
                <mat-form-field appearance="outline" class="field-cep">
                  <mat-label>CEP</mat-label>
                  <input matInput formControlName="cep"
                         placeholder="00000-000" maxlength="9"
                         (input)="onCepInput($event)">
                  <mat-hint>Formato: 00000-000</mat-hint>
                  @if (enderecoForm.get('cep')!.hasError('required') && enderecoForm.get('cep')!.touched) {
                    <mat-error>CEP e obrigatorio</mat-error>
                  }
                  @if (enderecoForm.get('cep')!.hasError('pattern') && enderecoForm.get('cep')!.touched) {
                    <mat-error>CEP invalido — informe 8 digitos</mat-error>
                  }
                </mat-form-field>
              </div>

              <div class="form-row">
                <mat-form-field appearance="outline" class="field-grow">
                  <mat-label>Logradouro</mat-label>
                  <input matInput formControlName="logradouro"
                         placeholder="Rua, Avenida, Travessa...">
                  @if (enderecoForm.get('logradouro')!.hasError('required') && enderecoForm.get('logradouro')!.touched) {
                    <mat-error>Logradouro e obrigatorio</mat-error>
                  }
                </mat-form-field>

                <mat-form-field appearance="outline" class="field-numero">
                  <mat-label>Numero</mat-label>
                  <input matInput formControlName="numero" placeholder="S/N">
                </mat-form-field>
              </div>

              <div class="form-row">
                <mat-form-field appearance="outline" class="field-grow">
                  <mat-label>Complemento</mat-label>
                  <input matInput formControlName="complemento"
                         placeholder="Apto, Sala, Bloco...">
                </mat-form-field>

                <mat-form-field appearance="outline" class="field-grow">
                  <mat-label>Bairro</mat-label>
                  <input matInput formControlName="bairro">
                  @if (enderecoForm.get('bairro')!.hasError('required') && enderecoForm.get('bairro')!.touched) {
                    <mat-error>Bairro e obrigatorio</mat-error>
                  }
                </mat-form-field>
              </div>

              <div class="form-row">
                <mat-form-field appearance="outline" class="field-grow">
                  <mat-label>Municipio</mat-label>
                  <input matInput formControlName="municipio">
                  @if (enderecoForm.get('municipio')!.hasError('required') && enderecoForm.get('municipio')!.touched) {
                    <mat-error>Municipio e obrigatorio</mat-error>
                  }
                </mat-form-field>

                <mat-form-field appearance="outline" class="field-uf">
                  <mat-label>UF</mat-label>
                  <mat-select formControlName="uf">
                    @for (uf of ufOptions; track uf.sigla) {
                      <mat-option [value]="uf.sigla">{{ uf.sigla }} — {{ uf.nome }}</mat-option>
                    }
                  </mat-select>
                  @if (enderecoForm.get('uf')!.hasError('required') && enderecoForm.get('uf')!.touched) {
                    <mat-error>UF e obrigatoria</mat-error>
                  }
                </mat-form-field>
              </div>

              <div class="step-actions">
                <button mat-button type="button" matStepperPrevious>
                  <mat-icon>arrow_back</mat-icon>
                  Voltar
                </button>
                <button mat-raised-button color="primary"
                        type="button"
                        matStepperNext
                        [disabled]="enderecoForm.invalid">
                  Proximo
                  <mat-icon iconPositionEnd>arrow_forward</mat-icon>
                </button>
              </div>
            </form>
          </mat-step>

          <!-- ═══════════════════════════════════════════════════
               PASSO 3 — Dados da Edificacao
               ═══════════════════════════════════════════════════ -->
          <mat-step [stepControl]="edificacaoForm" label="Edificacao">
            <form [formGroup]="edificacaoForm">
              <p class="step-desc">Informe as caracteristicas fisicas da edificacao:</p>

              <div class="form-row">
                <mat-form-field appearance="outline" class="field-grow">
                  <mat-label>Area Construida (m²)</mat-label>
                  <input matInput type="number" formControlName="areaConstruida"
                         min="0.01" step="0.01" placeholder="Ex: 250.00">
                  <mat-hint>Valor em metros quadrados</mat-hint>
                  @if (edificacaoForm.get('areaConstruida')!.hasError('required') && edificacaoForm.get('areaConstruida')!.touched) {
                    <mat-error>Area construida e obrigatoria</mat-error>
                  }
                  @if (edificacaoForm.get('areaConstruida')!.hasError('min') && edificacaoForm.get('areaConstruida')!.touched) {
                    <mat-error>Area deve ser maior que zero</mat-error>
                  }
                </mat-form-field>

                <mat-form-field appearance="outline" class="field-grow">
                  <mat-label>Altura Maxima (m)</mat-label>
                  <input matInput type="number" formControlName="alturaMaxima"
                         min="0.01" step="0.01" placeholder="Ex: 12.00">
                  <mat-hint>Valor em metros</mat-hint>
                  @if (edificacaoForm.get('alturaMaxima')!.hasError('required') && edificacaoForm.get('alturaMaxima')!.touched) {
                    <mat-error>Altura maxima e obrigatoria</mat-error>
                  }
                  @if (edificacaoForm.get('alturaMaxima')!.hasError('min') && edificacaoForm.get('alturaMaxima')!.touched) {
                    <mat-error>Altura deve ser maior que zero</mat-error>
                  }
                </mat-form-field>

                <mat-form-field appearance="outline" class="field-pav">
                  <mat-label>Pavimentos</mat-label>
                  <input matInput type="number" formControlName="numPavimentos"
                         min="1" step="1" placeholder="Ex: 3">
                  @if (edificacaoForm.get('numPavimentos')!.hasError('required') && edificacaoForm.get('numPavimentos')!.touched) {
                    <mat-error>Obrigatorio</mat-error>
                  }
                  @if (edificacaoForm.get('numPavimentos')!.hasError('min') && edificacaoForm.get('numPavimentos')!.touched) {
                    <mat-error>Min: 1</mat-error>
                  }
                </mat-form-field>
              </div>

              <div class="form-row">
                <mat-form-field appearance="outline" class="field-grow">
                  <mat-label>Tipo de Ocupacao</mat-label>
                  <input matInput formControlName="tipoOcupacao"
                         placeholder="Ex: Comercio varejista, Industria, Residencial multifamiliar...">
                  <mat-hint>Conforme classificacao da RTCBMRS (opcional)</mat-hint>
                </mat-form-field>
              </div>

              <div class="form-row">
                <mat-form-field appearance="outline" class="field-grow">
                  <mat-label>Uso Predominante</mat-label>
                  <input matInput formControlName="usoPredominante"
                         placeholder="Ex: Deposito, Escritorio, Hotel...">
                  <mat-hint>Uso principal da edificacao (opcional)</mat-hint>
                </mat-form-field>
              </div>

              <div class="step-actions">
                <button mat-button type="button" matStepperPrevious>
                  <mat-icon>arrow_back</mat-icon>
                  Voltar
                </button>
                <button mat-raised-button color="primary"
                        type="button"
                        matStepperNext
                        [disabled]="edificacaoForm.invalid">
                  Revisar
                  <mat-icon iconPositionEnd>arrow_forward</mat-icon>
                </button>
              </div>
            </form>
          </mat-step>

          <!-- ═══════════════════════════════════════════════════
               PASSO 4 — Revisao e Envio
               ═══════════════════════════════════════════════════ -->
          <mat-step label="Revisao">
            <p class="step-desc">Revise os dados antes de enviar a solicitacao:</p>

            <div class="review-grid">
              <!-- Tipo -->
              <mat-card appearance="outlined" class="review-section">
                <mat-card-header>
                  <mat-icon mat-card-avatar>local_fire_department</mat-icon>
                  <mat-card-title>Tipo de Licenciamento</mat-card-title>
                </mat-card-header>
                <mat-card-content>
                  <div class="review-item">
                    <span class="review-label">Tipo</span>
                    <span class="review-value tipo-highlight">{{ tipoForm.get('tipo')!.value }}</span>
                  </div>
                </mat-card-content>
              </mat-card>

              <!-- Endereco -->
              <mat-card appearance="outlined" class="review-section">
                <mat-card-header>
                  <mat-icon mat-card-avatar>location_on</mat-icon>
                  <mat-card-title>Endereco</mat-card-title>
                </mat-card-header>
                <mat-card-content>
                  <div class="review-item">
                    <span class="review-label">CEP</span>
                    <span class="review-value">{{ enderecoForm.get('cep')!.value }}</span>
                  </div>
                  <div class="review-item">
                    <span class="review-label">Logradouro</span>
                    <span class="review-value">
                      {{ enderecoForm.get('logradouro')!.value }}
                      @if (enderecoForm.get('numero')!.value) {
                        , {{ enderecoForm.get('numero')!.value }}
                      }
                      @if (enderecoForm.get('complemento')!.value) {
                        — {{ enderecoForm.get('complemento')!.value }}
                      }
                    </span>
                  </div>
                  <div class="review-item">
                    <span class="review-label">Bairro</span>
                    <span class="review-value">{{ enderecoForm.get('bairro')!.value }}</span>
                  </div>
                  <div class="review-item">
                    <span class="review-label">Municipio/UF</span>
                    <span class="review-value">
                      {{ enderecoForm.get('municipio')!.value }}/{{ enderecoForm.get('uf')!.value }}
                    </span>
                  </div>
                </mat-card-content>
              </mat-card>

              <!-- Edificacao -->
              <mat-card appearance="outlined" class="review-section">
                <mat-card-header>
                  <mat-icon mat-card-avatar>apartment</mat-icon>
                  <mat-card-title>Dados da Edificacao</mat-card-title>
                </mat-card-header>
                <mat-card-content>
                  <div class="review-item">
                    <span class="review-label">Area Construida</span>
                    <span class="review-value">{{ edificacaoForm.get('areaConstruida')!.value }} m²</span>
                  </div>
                  <div class="review-item">
                    <span class="review-label">Altura Maxima</span>
                    <span class="review-value">{{ edificacaoForm.get('alturaMaxima')!.value }} m</span>
                  </div>
                  <div class="review-item">
                    <span class="review-label">Pavimentos</span>
                    <span class="review-value">{{ edificacaoForm.get('numPavimentos')!.value }}</span>
                  </div>
                  @if (edificacaoForm.get('tipoOcupacao')!.value) {
                    <div class="review-item">
                      <span class="review-label">Tipo de Ocupacao</span>
                      <span class="review-value">{{ edificacaoForm.get('tipoOcupacao')!.value }}</span>
                    </div>
                  }
                  @if (edificacaoForm.get('usoPredominante')!.value) {
                    <div class="review-item">
                      <span class="review-label">Uso Predominante</span>
                      <span class="review-value">{{ edificacaoForm.get('usoPredominante')!.value }}</span>
                    </div>
                  }
                </mat-card-content>
              </mat-card>
            </div>

            <div class="review-info">
              <mat-icon>info</mat-icon>
              <span>
                Ao confirmar, o licenciamento sera criado em status
                <strong>Rascunho</strong> e submetido para analise automaticamente.
                Voce podera acompanhar o andamento na lista de licenciamentos.
              </span>
            </div>

            <div class="step-actions">
              <button mat-button type="button" matStepperPrevious [disabled]="saving()">
                <mat-icon>arrow_back</mat-icon>
                Voltar
              </button>
              <button mat-button type="button"
                      (click)="cancelar()" [disabled]="saving()">
                Cancelar
              </button>
              <button mat-raised-button color="primary"
                      type="button"
                      (click)="confirmar()"
                      [disabled]="saving()">
                @if (saving()) {
                  <ng-container>
                    <mat-spinner diameter="18" color="accent"></mat-spinner>
                    Enviando...
                  </ng-container>
                } @else {
                  <ng-container>
                    <mat-icon>send</mat-icon>
                    Confirmar e Enviar
                  </ng-container>
                }
              </button>
            </div>
          </mat-step>

        </mat-stepper>
      </mat-card-content>
    </mat-card>
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
    .wizard-card {
      max-width: 860px;
    }
    .step-desc {
      font-size: 14px;
      color: #555;
      margin: 16px 0 24px;
    }

    .tipo-cards {
      display: flex;
      gap: 20px;
      flex-wrap: wrap;
      margin-bottom: 8px;
    }
    .tipo-card {
      flex: 1;
      min-width: 220px;
      border: 2px solid #e0e0e0;
      border-radius: 12px;
      padding: 24px 20px;
      cursor: pointer;
      position: relative;
      text-align: center;
    }
    .tipo-card:hover {
      border-color: #3d6b9e;
      box-shadow: 0 2px 8px rgba(61,107,158,0.15);
    }
    .tipo-card.selected {
      border-color: #1a3a5c;
      background: #f0f4f9;
      box-shadow: 0 2px 12px rgba(26,58,92,0.2);
    }
    .tipo-icon {
      font-size: 40px;
      width: 40px;
      height: 40px;
      color: #3d6b9e;
      margin-bottom: 8px;
    }
    .tipo-name {
      font-size: 20px;
      font-weight: 700;
      color: #1a3a5c;
      margin-bottom: 6px;
    }
    .tipo-desc {
      font-size: 13px;
      color: #666;
      line-height: 1.4;
    }
    .tipo-check {
      position: absolute;
      top: 12px;
      right: 12px;
      color: #27ae60;
      opacity: 0;
    }
    .tipo-card.selected .tipo-check {
      opacity: 1;
    }

    .form-row {
      display: flex;
      gap: 16px;
      flex-wrap: wrap;
      margin-bottom: 4px;
    }
    .field-grow { flex: 1; min-width: 180px; }
    .field-cep  { width: 160px; }
    .field-numero { width: 120px; }
    .field-uf   { width: 200px; }
    .field-pav  { width: 130px; }

    .validation-msg {
      color: #cc0000;
      font-size: 12px;
      margin: 4px 0 0;
    }

    .review-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
      gap: 16px;
      margin-bottom: 20px;
    }
    .review-item {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      padding: 6px 0;
      border-bottom: 1px solid #f0f0f0;
      gap: 8px;
    }
    .review-item:last-child { border-bottom: none; }
    .review-label {
      font-size: 12px;
      color: #888;
      white-space: nowrap;
    }
    .review-value {
      font-size: 13px;
      color: #1a1a2e;
      font-weight: 500;
      text-align: right;
    }
    .tipo-highlight {
      color: #1a3a5c;
      font-size: 16px;
      font-weight: 700;
    }
    .review-info {
      display: flex;
      align-items: flex-start;
      gap: 10px;
      background: #e8f4fd;
      border-radius: 8px;
      padding: 12px 16px;
      font-size: 13px;
      color: #1a3a5c;
      margin-bottom: 16px;
    }
    .review-info mat-icon {
      color: #3498db;
      flex-shrink: 0;
    }

    .step-actions {
      display: flex;
      gap: 12px;
      justify-content: flex-end;
      margin-top: 24px;
      padding-top: 16px;
      border-top: 1px solid #f0f0f0;
      flex-wrap: wrap;
    }
  `]
})
export class LicenciamentoNovoComponent implements OnInit {

  private readonly fb   = inject(FormBuilder);
  private readonly svc  = inject(LicenciamentoService);
  private readonly router = inject(Router);

  saving = signal(false);
  error  = signal<string | null>(null);

  readonly ufOptions = UF_OPTIONS;

  tipoForm!:      FormGroup;
  enderecoForm!:  FormGroup;
  edificacaoForm!: FormGroup;

  ngOnInit(): void {
    this.tipoForm = this.fb.group({
      tipo: ['', Validators.required]
    });

    this.enderecoForm = this.fb.group({
      cep:         ['', [Validators.required, Validators.pattern(/^\d{8}$/)]],
      logradouro:  ['', Validators.required],
      numero:      [''],
      complemento: [''],
      bairro:      ['', Validators.required],
      municipio:   ['', Validators.required],
      uf:          ['RS', Validators.required]
    });

    this.edificacaoForm = this.fb.group({
      areaConstruida:  [null, [Validators.required, Validators.min(0.01)]],
      alturaMaxima:    [null, [Validators.required, Validators.min(0.01)]],
      numPavimentos:   [null, [Validators.required, Validators.min(1)]],
      tipoOcupacao:    [''],
      usoPredominante: ['']
    });
  }

  onCepInput(event: Event): void {
    const input = event.target as HTMLInputElement;
    const digits = input.value.replace(/\D/g, '').slice(0, 8);
    const formatted = digits.length > 5 ? `${digits.slice(0, 5)}-${digits.slice(5)}` : digits;
    input.value = formatted;
    this.enderecoForm.get('cep')!.setValue(digits, { emitEvent: false });
  }

  cancelar(): void {
    this.router.navigate(['/app/licenciamentos']);
  }

  confirmar(): void {
    if (this.tipoForm.invalid || this.enderecoForm.invalid || this.edificacaoForm.invalid) {
      return;
    }

    const dto: LicenciamentoCreateDTO = {
      tipo:            this.tipoForm.get('tipo')!.value,
      areaConstruida:  +this.edificacaoForm.get('areaConstruida')!.value,
      alturaMaxima:    +this.edificacaoForm.get('alturaMaxima')!.value,
      numPavimentos:   +this.edificacaoForm.get('numPavimentos')!.value,
      tipoOcupacao:    this.edificacaoForm.get('tipoOcupacao')!.value || undefined,
      usoPredominante: this.edificacaoForm.get('usoPredominante')!.value || undefined,
      endereco: {
        cep:         this.enderecoForm.get('cep')!.value,
        logradouro:  this.enderecoForm.get('logradouro')!.value,
        numero:      this.enderecoForm.get('numero')!.value || undefined,
        complemento: this.enderecoForm.get('complemento')!.value || undefined,
        bairro:      this.enderecoForm.get('bairro')!.value,
        municipio:   this.enderecoForm.get('municipio')!.value,
        uf:          this.enderecoForm.get('uf')!.value
      }
    };

    this.saving.set(true);
    this.error.set(null);

    this.svc.criar(dto).subscribe({
      next: licenciamento => {
        // Apos criar com sucesso, submete automaticamente para analise
        this.svc.submeter(licenciamento.id).subscribe({
          next: () => {
            this.saving.set(false);
            this.router.navigate(['/app/licenciamentos', licenciamento.id]);
          },
          error: () => {
            // Criou mas nao conseguiu submeter — navega para detalhe em RASCUNHO
            this.saving.set(false);
            this.router.navigate(['/app/licenciamentos', licenciamento.id]);
          }
        });
      },
      error: err => {
        this.saving.set(false);
        const msg = err?.error?.message ?? err?.message ?? 'Erro desconhecido';
        this.error.set(`Nao foi possivel criar o licenciamento: ${msg}`);
        console.error(err);
      }
    });
  }
}
