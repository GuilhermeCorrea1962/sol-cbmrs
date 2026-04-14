/**
 * troca-envolvidos.model.ts
 * DTOs para o modulo de Troca de Envolvidos (P09 — Sprint F8).
 *
 * Fluxo:
 *   RT atual (formulario inline em licenciamento-detalhe) solicita sua saida
 *     -> LicenciamentoDTO.trocaPendente = true
 *     -> LicenciamentoDTO.justificativaTroca guarda o texto da solicitacao
 *   Admin (tela /app/trocas/:id) aceita ou rejeita
 *     -> aceitarTroca: backend envia notificacao ao novo RT (associacao externa)
 *     -> rejeitarTroca: trocaPendente volta a false; licenciamento continua normal
 *
 * A solicitacao e registrada em tabela separada no backend (troca_envolvidos).
 * O campo LicenciamentoDTO.trocaPendente expoe o estado ao frontend.
 *
 * RNs relevantes (P09):
 *   - Apenas o RT atual do licenciamento pode solicitar sua propria saida.
 *   - Troca bloqueada se houver recurso ativo (RN-089) ou status terminal.
 *   - Backend valida unicidade: so uma solicitacao pendente por licenciamento.
 *   - Endpoint: POST /api/licenciamentos/{id}/solicitar-troca
 *   - Endpoint: POST /api/licenciamentos/{id}/aceitar-troca
 *   - Endpoint: POST /api/licenciamentos/{id}/rejeitar-troca
 */

/**
 * Enviado pelo RT ao solicitar sua saida do licenciamento.
 * Roles: RT atual do licenciamento (autenticado)
 * Transicao: trocaPendente false -> true
 */
export interface TrocaSolicitarDTO {
  /** Justificativa da solicitacao de saida. Minimo de 30 caracteres. */
  justificativa: string;
}

/**
 * Enviado pelo Admin ao aceitar a solicitacao de troca.
 * Roles: ADMIN, CHEFE_SSEG_BBM
 * Transicao: trocaPendente mantido como true ate novo RT se associar
 */
export interface TrocaAceitarDTO {
  /** Observacao do Admin (opcional). */
  observacao?: string;
}

/**
 * Enviado pelo Admin ao rejeitar a solicitacao de troca.
 * Roles: ADMIN, CHEFE_SSEG_BBM
 * Transicao: trocaPendente true -> false (RT permanece no licenciamento)
 */
export interface TrocaRejeitarDTO {
  /** Motivo da rejeicao. Obrigatorio, minimo de 20 caracteres. */
  motivo: string;
}
