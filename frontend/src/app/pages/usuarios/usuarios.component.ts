import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, Validators } from '@angular/forms';
import { MatCardModule } from '@angular/material/card';
import { MatTableModule } from '@angular/material/table';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatChipsModule } from '@angular/material/chips';
import { MatTooltipModule } from '@angular/material/tooltip';
import { MatDialogModule, MatDialog } from '@angular/material/dialog';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { MatSnackBar, MatSnackBarModule } from '@angular/material/snack-bar';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { MatDividerModule } from '@angular/material/divider';

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
    MatChipsModule,
    MatTooltipModule,
    MatDialogModule,
    MatFormFieldModule,
    MatInputModule,
    MatSelectModule,
    MatSnackBarModule,
    MatProgressSpinnerModule,
    MatDividerModule,
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
                    [style.background]="tipoColor(u.tipoUsuario)"
                    [style.color]="'#fff'">
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

    <!-- Dialog: criar/editar usuario -->
    @if (dialogAberto()) {
      <div class="dialog-backdrop" (click)="fecharDialog()">
        <div class="dialog-panel" (click)="$event.stopPropagation()">
          <div class="dialog-header">
            <h3>{{ editando() ? 'Editar Usuario' : 'Novo Usuario' }}</h3>
            <button mat-icon-button (click)="fecharDialog()">
              <mat-icon>close</mat-icon>
            </button>
          </div>
          <mat-divider />

          <form [formGroup]="form" class="dialog-form" (ngSubmit)="salvar()">
            <mat-form-field appearance="outline">
              <mat-label>Nome completo</mat-label>
              <input matInput formControlName="nome" />
              <mat-error>Nome e obrigatorio.</mat-error>
            </mat-form-field>

            <mat-form-field appearance="outline">
              <mat-label>CPF (somente digitos)</mat-label>
              <input matInput formControlName="cpf" maxlength="11" />
              <mat-error>CPF deve ter 11 digitos.</mat-error>
            </mat-form-field>

            <mat-form-field appearance="outline">
              <mat-label>E-mail</mat-label>
              <input matInput formControlName="email" type="email" />
              <mat-error>E-mail invalido.</mat-error>
            </mat-form-field>

            <mat-form-field appearance="outline">
              <mat-label>Telefone</mat-label>
              <input matInput formControlName="telefone" />
            </mat-form-field>

            <mat-form-field appearance="outline">
              <mat-label>Perfil de acesso</mat-label>
              <mat-select formControlName="tipoUsuario">
                @for (tipo of tiposDisponiveis; track tipo.value) {
                  <mat-option [value]="tipo.value">{{ tipo.label }}</mat-option>
                }
              </mat-select>
              <mat-error>Perfil e obrigatorio.</mat-error>
            </mat-form-field>

            @if (!editando()) {
              <mat-form-field appearance="outline">
                <mat-label>Senha inicial</mat-label>
                <input matInput formControlName="senha" type="password" />
                <mat-error>Senha deve ter no minimo 8 caracteres.</mat-error>
              </mat-form-field>
            }

            <div class="dialog-actions">
              <button mat-button type="button" (click)="fecharDialog()">Cancelar</button>
              <button mat-raised-button color="primary" type="submit"
                      [disabled]="salvando() || form.invalid">
                @if (salvando()) {
                  <mat-spinner diameter="18" />
                } @else {
                  {{ editando() ? 'Salvar' : 'Criar' }}
                }
              </button>
            </div>
          </form>
        </div>
      </div>
    }
  `,
  styles: [`
    .page-header {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: 24px;
      gap: 16px;
    }

    .page-header h2 { font-size: 22px; font-weight: 600; color: #1a1a2e; margin: 0 0 4px; }
    .page-subtitle  { font-size: 13px; color: #666; margin: 0; }

    .empty-card {
      text-align: center;
      padding: 48px 24px;
    }
    .empty-icon { font-size: 48px; width: 48px; height: 48px; color: #ccc; margin-bottom: 12px; }

    .usuarios-table { width: 100%; }

    .user-nome  { font-weight: 500; }
    .user-email { color: #888; font-size: 12px; }

    .tipo-badge {
      display: inline-block;
      padding: 2px 10px;
      border-radius: 12px;
      font-size: 11px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: .4px;
    }

    .icon-ativo   { color: #27ae60; }
    .icon-inativo { color: #bbb; }

    /* Dialog embutido */
    .dialog-backdrop {
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,.45);
      z-index: 1000;
      display: flex;
      align-items: center;
      justify-content: center;
    }

    .dialog-panel {
      background: #fff;
      border-radius: 8px;
      width: 480px;
      max-width: calc(100vw - 32px);
      max-height: calc(100vh - 64px);
      overflow-y: auto;
      box-shadow: 0 8px 32px rgba(0,0,0,.2);
    }

    .dialog-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 16px 20px 12px;
    }

    .dialog-header h3 { margin: 0; font-size: 18px; font-weight: 600; color: #1a1a2e; }

    .dialog-form {
      display: flex;
      flex-direction: column;
      gap: 4px;
      padding: 16px 20px;
    }

    .dialog-form mat-form-field { width: 100%; }

    .dialog-actions {
      display: flex;
      justify-content: flex-end;
      gap: 8px;
      margin-top: 8px;
    }

    mat-spinner { display: inline-block; }
  `]
})
export class UsuariosComponent implements OnInit {
  private readonly svc    = inject(UsuarioService);
  private readonly snack  = inject(MatSnackBar);
  private readonly fb     = inject(FormBuilder);

  readonly colunas = ['nome', 'cpf', 'tipo', 'status', 'acoes'];

  usuarios   = signal<UsuarioDTO[]>([]);
  loading    = signal(true);
  error      = signal<string | null>(null);
  dialogAberto = signal(false);
  editando   = signal<UsuarioDTO | null>(null);
  salvando   = signal(false);

  readonly tiposDisponiveis: { value: TipoUsuario; label: string }[] = [
    { value: 'CIDADAO',        label: TIPO_USUARIO_LABEL.CIDADAO },
    { value: 'RT',             label: TIPO_USUARIO_LABEL.RT },
    { value: 'ANALISTA',       label: TIPO_USUARIO_LABEL.ANALISTA },
    { value: 'INSPETOR',       label: TIPO_USUARIO_LABEL.INSPETOR },
    { value: 'ADMIN',          label: TIPO_USUARIO_LABEL.ADMIN },
    { value: 'CHEFE_SSEG_BBM', label: TIPO_USUARIO_LABEL.CHEFE_SSEG_BBM },
  ];

  form = this.fb.group({
    nome:        ['', [Validators.required, Validators.maxLength(200)]],
    cpf:         ['', [Validators.required, Validators.minLength(11), Validators.maxLength(11), Validators.pattern(/^\d{11}$/)]],
    email:       ['', [Validators.required, Validators.email, Validators.maxLength(200)]],
    telefone:    [''],
    tipoUsuario: ['' as TipoUsuario, Validators.required],
    senha:       [''],
  });

  ngOnInit(): void {
    this.carregar();
  }

  private carregar(): void {
    this.loading.set(true);
    this.svc.listar().subscribe({
      next: u => { this.usuarios.set(u); this.loading.set(false); },
      error: e => { this.error.set('Erro ao carregar usuarios: ' + (e.error?.message ?? e.message)); this.loading.set(false); }
    });
  }

  abrirNovoUsuario(): void {
    this.editando.set(null);
    this.form.reset();
    this.form.get('senha')!.setValidators([Validators.required, Validators.minLength(8)]);
    this.form.get('senha')!.updateValueAndValidity();
    this.dialogAberto.set(true);
  }

  abrirEditar(u: UsuarioDTO): void {
    this.editando.set(u);
    this.form.patchValue({
      nome:        u.nome,
      cpf:         u.cpf,
      email:       u.email,
      telefone:    u.telefone ?? '',
      tipoUsuario: u.tipoUsuario,
      senha:       '',
    });
    this.form.get('senha')!.clearValidators();
    this.form.get('senha')!.updateValueAndValidity();
    this.dialogAberto.set(true);
  }

  fecharDialog(): void {
    this.dialogAberto.set(false);
    this.editando.set(null);
    this.form.reset();
  }

  salvar(): void {
    if (this.form.invalid) return;
    this.salvando.set(true);
    const v = this.form.value;
    const user = this.editando();

    if (user) {
      this.svc.atualizar(user.id, {
        nome:        v.nome!,
        email:       v.email!,
        telefone:    v.telefone ?? undefined,
        tipoUsuario: v.tipoUsuario as TipoUsuario,
      }).subscribe({
        next: () => { this.snack.open('Usuario atualizado com sucesso.', 'OK', { duration: 3000 }); this.fecharDialog(); this.carregar(); this.salvando.set(false); },
        error: e => { this.snack.open('Erro: ' + (e.error?.message ?? e.message), 'OK', { duration: 5000 }); this.salvando.set(false); }
      });
    } else {
      this.svc.criar({
        cpf:         v.cpf!,
        nome:        v.nome!,
        email:       v.email!,
        telefone:    v.telefone ?? undefined,
        tipoUsuario: v.tipoUsuario as TipoUsuario,
        senha:       v.senha!,
      }).subscribe({
        next: () => { this.snack.open('Usuario criado com sucesso.', 'OK', { duration: 3000 }); this.fecharDialog(); this.carregar(); this.salvando.set(false); },
        error: e => { this.snack.open('Erro: ' + (e.error?.message ?? e.message), 'OK', { duration: 5000 }); this.salvando.set(false); }
      });
    }
  }

  desativar(u: UsuarioDTO): void {
    if (!confirm(`Desativar o usuario "${u.nome}"?`)) return;
    this.svc.desativar(u.id).subscribe({
      next: () => { this.snack.open('Usuario desativado.', 'OK', { duration: 3000 }); this.carregar(); },
      error: e => this.snack.open('Erro ao desativar: ' + (e.error?.message ?? e.message), 'OK', { duration: 5000 })
    });
  }

  mascaraCpf(cpf: string): string {
    if (!cpf || cpf.length !== 11) return cpf;
    return `${cpf.slice(0,3)}.${cpf.slice(3,6)}.${cpf.slice(6,9)}-${cpf.slice(9)}`;
  }

  tipoLabel(tipo: TipoUsuario): string  { return TIPO_USUARIO_LABEL[tipo] ?? tipo; }
  tipoColor(tipo: TipoUsuario): string  { return TIPO_USUARIO_COLOR[tipo] ?? '#888'; }
}
