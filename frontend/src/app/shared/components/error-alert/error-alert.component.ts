import { Component, Input, Output, EventEmitter } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MatIconModule } from '@angular/material/icon';
import { MatButtonModule } from '@angular/material/button';

/**
 * Componente de alerta de erro inline.
 *
 * Uso:
 *   <sol-error-alert
 *     [message]="erroApi"
 *     (dismissed)="erroApi = null" />
 *
 * Exibe um banner vermelho com icone de erro e botao de fechar.
 * Invisivel quando message e nulo ou vazio.
 */
@Component({
  selector: 'sol-error-alert',
  standalone: true,
  imports: [CommonModule, MatIconModule, MatButtonModule],
  template: `
    @if (message) {
      <div class="error-alert" role="alert">
        <mat-icon class="error-icon">error_outline</mat-icon>
        <span class="error-text">{{ message }}</span>
        <button mat-icon-button class="error-close"
                aria-label="Fechar alerta"
                (click)="dismiss()">
          <mat-icon>close</mat-icon>
        </button>
      </div>
    }
  `,
  styles: [`
    .error-alert {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 12px 16px;
      background: #fdecea;
      border: 1px solid #f5c6cb;
      border-left: 4px solid #cc0000;
      border-radius: 4px;
      margin-bottom: 16px;
    }

    .error-icon {
      color: #cc0000;
      flex-shrink: 0;
    }

    .error-text {
      flex: 1;
      font-size: 14px;
      color: #721c24;
    }

    .error-close {
      color: #721c24;
      flex-shrink: 0;
    }
  `]
})
export class ErrorAlertComponent {
  @Input() message: string | null = null;
  @Output() dismissed = new EventEmitter<void>();

  dismiss(): void {
    this.dismissed.emit();
  }
}
