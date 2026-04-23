import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, Validators } from '@angular/forms';
import { MAT_DIALOG_DATA, MatDialogModule, MatDialogRef } from '@angular/material/dialog';
import { MatButtonModule } from '@angular/material/button';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';

import {
  TipoUsuario,
  TIPO_USUARIO_LABEL,
  UsuarioDTO,
} from '../../core/models/usuario.model';

export interface UsuarioDialogData {
  usuario?: UsuarioDTO;
}

export interface UsuarioDialogResult {
  nome: string;
  cpf: string;
  email: string;
  telefone?: string;
  tipoUsuario: TipoUsuario;
  senha?: string;
}

@Component({
  selector: 'sol-usuario-dialog',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    MatDialogModule,
    MatButtonModule,
    MatFormFieldModule,
    MatInputModule,
    MatSelectModule,
    MatProgressSpinnerModule,
  ],
  template: `
    <h2 mat-dialog-title>{{ editando ? 'Editar Usuario' : 'Novo Usuario' }}</h2>

    <mat-dialog-content>
      <form [formGroup]="form" class="dialog-form">
        <mat-form-field appearance="outline" class="full-width">
          <mat-label>Nome completo</mat-label>
          <input matInput formControlName="nome" />
          <mat-error>Nome e obrigatorio.</mat-error>
        </mat-form-field>

        <mat-form-field appearance="outline" class="full-width">
          <mat-label>CPF (somente digitos)</mat-label>
          <input matInput formControlName="cpf" maxlength="11" />
          <mat-error>CPF deve ter 11 digitos.</mat-error>
        </mat-form-field>

        <mat-form-field appearance="outline" class="full-width">
          <mat-label>E-mail</mat-label>
          <input matInput formControlName="email" type="email" />
          <mat-error>E-mail invalido.</mat-error>
        </mat-form-field>

        <mat-form-field appearance="outline" class="full-width">
          <mat-label>Telefone</mat-label>
          <input matInput formControlName="telefone" />
        </mat-form-field>

        <mat-form-field appearance="outline" class="full-width">
          <mat-label>Perfil de acesso</mat-label>
          <mat-select formControlName="tipoUsuario">
            <mat-option value="CIDADAO">{{ labels.CIDADAO }}</mat-option>
            <mat-option value="RT">{{ labels.RT }}</mat-option>
            <mat-option value="ANALISTA">{{ labels.ANALISTA }}</mat-option>
            <mat-option value="INSPETOR">{{ labels.INSPETOR }}</mat-option>
            <mat-option value="ADMIN">{{ labels.ADMIN }}</mat-option>
            <mat-option value="CHEFE_SSEG_BBM">{{ labels.CHEFE_SSEG_BBM }}</mat-option>
          </mat-select>
          <mat-error>Perfil e obrigatorio.</mat-error>
        </mat-form-field>

        @if (!editando) {
          <mat-form-field appearance="outline" class="full-width">
            <mat-label>Senha inicial</mat-label>
            <input matInput formControlName="senha" type="password" />
            <mat-error>Minimo 8 caracteres.</mat-error>
          </mat-form-field>
        }
      </form>
    </mat-dialog-content>

    <mat-dialog-actions align="end">
      <button mat-button mat-dialog-close>Cancelar</button>
      <button mat-raised-button color="primary"
              [disabled]="form.invalid"
              (click)="confirmar()">
        {{ editando ? 'Salvar' : 'Criar' }}
      </button>
    </mat-dialog-actions>
  `,
  styles: [`
    .dialog-form { display: flex; flex-direction: column; gap: 4px; padding-top: 8px; min-width: 420px; }
    .full-width { width: 100%; }
  `]
})
export class UsuarioDialogComponent {
  private readonly fb     = inject(FormBuilder);
  private readonly ref    = inject(MatDialogRef<UsuarioDialogComponent>);
  readonly data: UsuarioDialogData = inject(MAT_DIALOG_DATA);

  readonly labels = TIPO_USUARIO_LABEL;
  readonly editando = !!this.data?.usuario;

  form = this.fb.group({
    nome:        [this.data?.usuario?.nome        ?? '', [Validators.required, Validators.maxLength(200)]],
    cpf:         [this.data?.usuario?.cpf         ?? '', [Validators.required, Validators.pattern(/^\d{11}$/)]],
    email:       [this.data?.usuario?.email       ?? '', [Validators.required, Validators.email]],
    telefone:    [this.data?.usuario?.telefone    ?? ''],
    tipoUsuario: [this.data?.usuario?.tipoUsuario ?? '' as TipoUsuario, Validators.required],
    senha:       ['', this.editando ? [] : [Validators.required, Validators.minLength(8)]],
  });

  confirmar(): void {
    if (this.form.invalid) return;
    const v = this.form.value;
    const result: UsuarioDialogResult = {
      nome:        v.nome!,
      cpf:         v.cpf!,
      email:       v.email!,
      telefone:    v.telefone || undefined,
      tipoUsuario: v.tipoUsuario as TipoUsuario,
      senha:       v.senha || undefined,
    };
    this.ref.close(result);
  }
}
