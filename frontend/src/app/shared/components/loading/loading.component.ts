import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';

/**
 * Componente de indicador de carregamento.
 *
 * Uso:
 *   <sol-loading [show]="isLoading" message="Carregando dados..." />
 *
 * Quando show=true, exibe um overlay semi-transparente com spinner centralizado.
 */
@Component({
  selector: 'sol-loading',
  standalone: true,
  imports: [CommonModule, MatProgressSpinnerModule],
  template: `
    @if (show) {
      <div class="loading-overlay">
        <div class="loading-box">
          <mat-spinner diameter="48" color="warn" />
          @if (message) {
            <p class="loading-message">{{ message }}</p>
          }
        </div>
      </div>
    }
  `,
  styles: [`
    .loading-overlay {
      position: fixed;
      inset: 0;
      background: rgba(255, 255, 255, 0.75);
      display: flex;
      align-items: center;
      justify-content: center;
      z-index: 9999;
    }

    .loading-box {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 16px;
    }

    .loading-message {
      font-size: 14px;
      color: #555;
      margin: 0;
    }
  `]
})
export class LoadingComponent {
  @Input() show = false;
  @Input() message = '';
}
