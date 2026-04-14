/**
 * Sprint F6 -- Emissao de APPCI (P08)
 * DTO de criacao usado na requisicao POST para emissao do APPCI.
 */

/**
 * Payload para emissao do APPCI (Alvara de Prevencao e Protecao Contra Incendio).
 * Endpoint: POST /api/licenciamentos/{id}/emitir-appci
 * Transicao: PRPCI_EMITIDO -> APPCI_EMITIDO
 * Roles: ADMIN, CHEFE_SSEG_BBM
 *
 * A validade do APPCI (2 ou 5 anos) e calculada automaticamente pelo backend
 * com base no tipo de ocupacao da edificacao, conforme RTCBMRS N.01/2024.
 */
export interface AppciEmitirDTO {
  /**
   * Observacoes/laudo do responsavel pela emissao (opcional).
   * Registradas no historico do processo. Maximo 5000 caracteres.
   */
  observacao?: string;
}
