import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { MatCardModule } from '@angular/material/card';
import { MatTableModule } from '@angular/material/table';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatTooltipModule } from '@angular/material/tooltip';
import { MatSnackBar, MatSnackBarModule } from '@angular/material/snack-bar';

import { UsuarioService } from '../../core/services/usuario.service';
import {
  UsuarioDTO,
  TipoUsuario,
  TIPO_USUARIO_LABEL,
  TIPO_USUARIO_COLOR,
} from '../../core/models/usuario.model';
import { LoadingComponent } from '../../shared/components/loading/loading.component';
import { ErrorAlertComponent } from '../../shared/components/error-alert/error-alert.component';

@Component({
  selector: 'sol-usuarios',
  standalone: true,
  imports: [
    CommonModule,
    ReactiveFormsModule,
    MatCardModule,
    MatTableModule,
    MatButtonModule,
    MatIconModule,
    MatTooltipModule,
    MatSnackBarModule,
    LoadingComponent,
    ErrorAlertComponent,
  ],
  template: `
    <sol-loading [show]="loading()" message="Carregando usuarios..." />
    <sol-error-alert [message]="error()" (dismissed)="error.set(null)" />

    <div class="page-header">
      <div>
        <h2>Gestao de Usuarios</h2>
        <p class="page-subtitle">Gerencie contas e perfis de acesso ao SOL.</p>
      </div>
      <button mat-raised-button color="primary" (click)="abrirNovoUsuario()">
        <mat-icon>person_add</mat-icon>
        Novo Usuario
      </button>
    </div>

    @if (!loading() && usuarios().length === 0 && !error()) {
      <mat-card appearance="outlined" class="empty-card">
        <mat-card-content>
          <mat-icon class="empty-icon">people_outline</mat-icon>
          <p>Nenhum usuario cadastrado.</p>
        </mat-card-content>
      </mat-card>
    }

    @if (usuarios().length > 0) {
      <mat-card appearance="outlined">
        <table mat-table [dataSource]="usuarios()" class="usuarios-table">

          <ng-container matColumnDef="nome">
            <th mat-header-cell *matHeaderCellDef>Nome</th>
            <td mat-cell *matCellDef="let u">
              <span class="user-nome">{{ u.nome }}</span>
              <br><small class="user-email">{{ u.email }}</small>
            </td>
          </ng-container>

          <ng-container matColumnDef="cpf">
            <th mat-header-cell *matHeaderCellDef>CPF</th>
            <td mat-cell *matCellDef="let u">{{ mascaraCpf(u.cpf) }}</td>
          </ng-container>

          <ng-container matColumnDef="tipo">
            <th mat-header-cell *matHeaderCellDef>Perfil</th>
            <td mat-cell *matCellDef="let u">
              <span class="tipo-badge"
                    [style.background]="tipoColor(u.tipoUsuario)">
                {{ tipoLabel(u.tipoUsuario) }}
              </span>
            </td>
          </ng-container>

          <ng-container matColumnDef="status">
            <th mat-header-cell *matHeaderCellDef>Status</th>
            <td mat-cell *matCellDef="let u">
              <mat-icon [class]="u.ativo ? 'icon-ativo' : 'icon-inativo'"
                        [matTooltip]="u.ativo ? 'Ativo' : 'Inativo'">
                {{ u.ativo ? 'check_circle' : 'cancel' }}
              </mat-icon>
            </td>
          </ng-container>

          <ng-container matColumnDef="acoes">
            <th mat-header-cell *matHeaderCellDef>Acoes</th>
            <td mat-cell *matCellDef="let u">
              <button mat-icon-button color="primary"
                      [matTooltip]="'Editar ' + u.nome"
                      (click)="abrirEditar(u)">
                <mat-icon>edit</mat-icon>
              </button>
              @if (u.ativo) {
                <button mat-icon-button color="warn"
                        [matTooltip]="'Desativar ' + u.nome"
                        (click)="desativar(u)">
                  <mat-icon>block</mat-icon>
                </button>
              }
            </td>
          </ng-container>

          <tr mat-header-row *matHeaderRowDef="colunas"></tr>
          <tr mat-row *matRowDef="let row; columns: colunas;"></tr>
        </table>
      </mat-card>
    }

    <!-- Modal customizado (nao usa MatDialog/CDK Overlay) -->
    @if (modalAberto()) {
      <div class="sol-modal-backdrop" (click)="fecharModal()"></div>
      <div class="sol-modal" role="dialog" aria-modal="true">
        <h2 class="sol-modal-title">{{ editandoId() ? 'Editar Usuario' : 'Novo Usuario' }}</h2>

        <form [formGroup]="form" class="sol-modal-form" (ngSubmit)="salvar()">
          <label class="sol-field">
            <span>Nome completo</span>
            <input type="text" formControlName="nome" maxlength="200" />
            @if (form.controls.nome.touched && form.controls.nome.invalid) {
              <small class="sol-error">Nome e obrigatorio.</small>
            }
          </label>

          <label class="sol-field">
            <span>CPF (somente digitos)</span>
            <input type="text" formControlName="cpf" maxlength="11"
                   [readonly]="!!editandoId()" />
            @if (form.controls.cpf.touched && form.controls.cpf.invalid) {
              <small class="sol-error">CPF deve ter 11 digitos.</small>
            }
          </label>

          <label class="sol-field">
            <span>E-mail</span>
            <input type="email" formControlName="email" />
            @if (form.controls.email.touched && form.controls.email.invalid) {
              <small class="sol-error">E-mail invalido.</small>
            }
          </label>

          <label class="sol-field">
            <span>Telefone</span>
            <input type="text" formControlName="telefone" />
          </label>

          <label class="sol-field">
            <span>Perfil de acesso</span>
            <select formControlName="tipoUsuario">
              <option value="">Selecione...</option>
              <option value="CIDADAO">Cidadao</option>
              <option value="RT">Resp. Tecnico</option>
              <option value="ANALISTA">Analista</option>
              <option value="INSPETOR">Inspetor</option>
              <option value="ADMIN">Administrador</option>
              <option value="CHEFE_SSEG_BBM">Chefe SSEG/BBM</option>
            </select>
            @if (form.controls.tipoUsuario.touched && form.controls.tipoUsuario.invalid) {
              <small class="sol-error">Perfil e obrigatorio.</small>
            }
          </label>

          @if (!editandoId()) {
            <label class="sol-field">
              <span>Senha inicial</span>
              <input type="password" formControlName="senha" />
              @if (form.controls.senha.touched && form.controls.senha.invalid) {
                <small class="sol-error">Minimo 8 caracteres.</small>
              }
            </label>
          }

          <div class="sol-modal-actions">
            <button type="button" class="btn-cancel" (click)="fecharModal()">Cancelar</button>
            <button type="submit" class="btn-submit" [disabled]="form.invalid">
              {{ editandoId() ? 'Salvar' : 'Criar' }}
            </button>
          </div>
        </form>
      </div>
    }
  `,
  styles: [`
    .page-header {
      display: flex; align-items: flex-start; justify-content: space-between;
      margin-bottom: 24px; gap: 16px;
    }
    .page-header h2 { font-size: 22px; font-weight: 600; color: #1a1a2e; margin: 0 0 4px; }
    .page-subtitle  { font-size: 13px; color: #666; margin: 0; }

    .empty-card { text-align: center; padding: 48px 24px; }
    .empty-icon { font-size: 48px; width: 48px; height: 48px; color: #ccc; margin-bottom: 12px; }

    .usuarios-table { width: 100%; }
    .user-nome  { font-weight: 500; }
    .user-email { color: #888; font-size: 12px; }

    .tipo-badge {
      display: inline-block; padding: 2px 10px; border-radius: 12px;
      font-size: 11px; font-weight: 600; text-transform: uppercase;
      letter-spacing: .4px; color: #fff;
    }

    .icon-ativo   { color: #27ae60; }
    .icon-inativo { color: #bbb; }

    /* ======== Modal customizado ======== */
    .sol-modal-backdrop {
      position: fixed; top: 0; left: 0; right: 0; bottom: 0;
      background: rgba(0,0,0,0.5); z-index: 2000;
    }
    .sol-modal {
      position: fixed;
      top: 50%; left: 50%;
      transform: translate(-50%, -50%);
      background: #fff; border-radius: 8px;
      box-shadow: 0 10px 40px rgba(0,0,0,0.25);
      width: 480px; max-width: calc(100vw - 32px);
      max-height: calc(100vh - 32px); overflow-y: auto;
      z-index: 2001; padding: 24px;
    }
    .sol-modal-title {
      margin: 0 0 16px; font-size: 20px; font-weight: 600; color: #1a1a2e;
    }
    .sol-modal-form { display: flex; flex-direction: column; gap: 14px; }
    .sol-field { display: flex; flex-direction: column; gap: 4px; }
    .sol-field span { font-size: 13px; font-weight: 500; color: #444; }
    .sol-field input, .sol-field select {
      padding: 10px 12px; font-size: 14px;
      border: 1px solid #ccc; border-radius: 4px;
      background: #fff; color: #333;
      font-family: inherit;
    }
    .sol-field input:focus, .sol-field select:focus {
      outline: none; border-color: #cc0000;
      box-shadow: 0 0 0 2px rgba(204,0,0,0.15);
    }
    .sol-field input[readonly] { background: #f5f5f5; color: #666; }
    .sol-error { color: #cc0000; font-size: 12px; }

    .sol-modal-actions {
      display: flex; justify-content: flex-end; gap: 8px; margin-top: 8px;
    }
    .btn-cancel, .btn-submit {
      padding: 8px 20px; font-size: 14px; font-weight: 500;
      border-radius: 4px; cursor: pointer; border: none;
      font-family: inherit;
    }
    .btn-cancel { background: transparent; color: #666; }
    .btn-cancel:hover { background: #f0f0f0; }
    .btn-submit { background: #cc0000; color: #fff; }
    .btn-submit:hover:not([disabled]) { background: #990000; }
    .btn-submit[disabled] { background: #ccc; cursor: not-allowed; }
  `]
})
export class UsuariosComponent implements OnInit {
  private readonly svc   = inject(UsuarioService);
  private readonly snack = inject(MatSnackBar);
  private readonly fb    = inject(FormBuilder);

  readonly colunas = ['nome', 'cpf', 'tipo', 'status', 'acoes'];

  usuarios    = signal<UsuarioDTO[]>([]);
  loading     = signal(true);
  error       = signal<string | null>(null);
  modalAberto = signal(false);
  editandoId  = signal<number | null>(null);

  form = this.fb.group({
    nome:        ['', [Validators.required, Validators.maxLength(200)]],
    cpf:         ['', [Validators.required, Validators.pattern(/^\d{11}$/)]],
    email:       ['', [Validators.required, Validators.email]],
    telefone:    [''],
    tipoUsuario: ['' as TipoUsuario | '', Validators.required],
    senha:       ['', [Validators.required, Validators.minLength(8)]],
  });

  ngOnInit(): void { this.carregar(); }

  private carregar(): void {
    this.loading.set(true);
    this.svc.listar().subscribe({
      next:  u => { this.usuarios.set(u); this.loading.set(false); },
      error: e => { this.error.set('Erro ao carregar usuarios: ' + (e.error?.message ?? e.message)); this.loading.set(false); }
    });
  }

  abrirNovoUsuario(): void {
    this.editandoId.set(null);
    this.form.reset({
      nome: '', cpf: '', email: '', telefone: '',
      tipoUsuario: '', senha: '',
    });
    this.form.controls.senha.setValidators([Validators.required, Validators.minLength(8)]);
    this.form.controls.senha.updateValueAndValidity();
    this.modalAberto.set(true);
  }

  abrirEditar(u: UsuarioDTO): void {
    this.editandoId.set(u.id);
    this.form.reset({
      nome: u.nome, cpf: u.cpf, email: u.email,
      telefone: u.telefone ?? '',
      tipoUsuario: u.tipoUsuario,
      senha: '',
    });
    this.form.controls.senha.clearValidators();
    this.form.controls.senha.updateValueAndValidity();
    this.modalAberto.set(true);
  }

  fecharModal(): void {
    this.modalAberto.set(false);
    this.editandoId.set(null);
  }

  salvar(): void {
    if (this.form.invalid) { this.form.markAllAsTouched(); return; }
    const v = this.form.value;
    const id = this.editandoId();

    if (id !== null) {
      this.svc.atualizar(id, {
        nome:        v.nome!,
        email:       v.email!,
        telefone:    v.telefone || undefined,
        tipoUsuario: v.tipoUsuario as TipoUsuario,
      }).subscribe({
        next: () => {
          this.snack.open('Usuario atualizado.', 'OK', { duration: 3000 });
          this.fecharModal();
          this.carregar();
        },
        error: e => this.snack.open('Erro: ' + (e.error?.message ?? e.message), 'OK', { duration: 5000 })
      });
    } else {
      this.svc.criar({
        cpf:         v.cpf!,
        nome:        v.nome!,
        email:       v.email!,
        telefone:    v.telefone || undefined,
        tipoUsuario: v.tipoUsuario as TipoUsuario,
        senha:       v.senha!,
      }).subscribe({
        next: () => {
          this.snack.open('Usuario criado com sucesso.', 'OK', { duration: 3000 });
          this.fecharModal();
          this.carregar();
        },
        error: e => this.snack.open('Erro: ' + (e.error?.message ?? e.message), 'OK', { duration: 5000 })
      });
    }
  }

  desativar(u: UsuarioDTO): void {
    if (!confirm(`Desativar o usuario "${u.nome}"?`)) return;
    this.svc.desativar(u.id).subscribe({
      next:  () => { this.snack.open('Usuario desativado.', 'OK', { duration: 3000 }); this.carregar(); },
      error: e => this.snack.open('Erro ao desativar: ' + (e.error?.message ?? e.message), 'OK', { duration: 5000 })
    });
  }

  mascaraCpf(cpf: string): string {
    if (!cpf || cpf.length !== 11) return cpf;
    return `${cpf.slice(0,3)}.${cpf.slice(3,6)}.${cpf.slice(6,9)}-${cpf.slice(9)}`;
  }

  tipoLabel(tipo: TipoUsuario): string { return TIPO_USUARIO_LABEL[tipo] ?? tipo; }
  tipoColor(tipo: TipoUsuario): string { return TIPO_USUARIO_COLOR[tipo] ?? '#888'; }
}
