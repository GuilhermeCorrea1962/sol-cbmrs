import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MatCardModule } from '@angular/material/card';
import { MatTableModule } from '@angular/material/table';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatTooltipModule } from '@angular/material/tooltip';
import { MatDialog, MatDialogModule } from '@angular/material/dialog';
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
import {
  UsuarioDialogComponent,
  UsuarioDialogData,
  UsuarioDialogResult,
} from './usuario-dialog.component';

@Component({
  selector: 'sol-usuarios',
  standalone: true,
  imports: [
    CommonModule,
    MatCardModule,
    MatTableModule,
    MatButtonModule,
    MatIconModule,
    MatTooltipModule,
    MatDialogModule,
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

    .empty-card { text-align: center; padding: 48px 24px; }
    .empty-icon  { font-size: 48px; width: 48px; height: 48px; color: #ccc; margin-bottom: 12px; }

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
      color: #fff;
    }

    .icon-ativo   { color: #27ae60; }
    .icon-inativo { color: #bbb; }
  `]
})
export class UsuariosComponent implements OnInit {
  private readonly svc   = inject(UsuarioService);
  private readonly snack = inject(MatSnackBar);
  private readonly dialog = inject(MatDialog);

  readonly colunas = ['nome', 'cpf', 'tipo', 'status', 'acoes'];

  usuarios = signal<UsuarioDTO[]>([]);
  loading  = signal(true);
  error    = signal<string | null>(null);

  ngOnInit(): void { this.carregar(); }

  private carregar(): void {
    this.loading.set(true);
    this.svc.listar().subscribe({
      next:  u => { this.usuarios.set(u); this.loading.set(false); },
      error: e => { this.error.set('Erro ao carregar usuarios: ' + (e.error?.message ?? e.message)); this.loading.set(false); }
    });
  }

  abrirNovoUsuario(): void {
    this.dialog.open<UsuarioDialogComponent, UsuarioDialogData, UsuarioDialogResult>(
      UsuarioDialogComponent,
      { data: {}, width: '480px', disableClose: false }
    ).afterClosed().subscribe(result => {
      if (!result) return;
      this.svc.criar({
        cpf:         result.cpf,
        nome:        result.nome,
        email:       result.email,
        telefone:    result.telefone,
        tipoUsuario: result.tipoUsuario,
        senha:       result.senha!,
      }).subscribe({
        next:  () => { this.snack.open('Usuario criado com sucesso.', 'OK', { duration: 3000 }); this.carregar(); },
        error: e => this.snack.open('Erro: ' + (e.error?.message ?? e.message), 'OK', { duration: 5000 })
      });
    });
  }

  abrirEditar(u: UsuarioDTO): void {
    this.dialog.open<UsuarioDialogComponent, UsuarioDialogData, UsuarioDialogResult>(
      UsuarioDialogComponent,
      { data: { usuario: u }, width: '480px', disableClose: false }
    ).afterClosed().subscribe(result => {
      if (!result) return;
      this.svc.atualizar(u.id, {
        nome:        result.nome,
        email:       result.email,
        telefone:    result.telefone,
        tipoUsuario: result.tipoUsuario,
      }).subscribe({
        next:  () => { this.snack.open('Usuario atualizado.', 'OK', { duration: 3000 }); this.carregar(); },
        error: e => this.snack.open('Erro: ' + (e.error?.message ?? e.message), 'OK', { duration: 5000 })
      });
    });
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
