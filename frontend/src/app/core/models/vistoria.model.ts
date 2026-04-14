/**
 * Sprint F5 -- Vistoria Presencial (P07)
 * DTOs de criacao usados nas requisicoes POST para os endpoints de vistoria.
 */

/** Item individual de nao-conformidade identificado durante a vistoria presencial. */
export interface CivItemCreateDTO {
  /** Descricao objetiva da nao-conformidade. Maximo 500 caracteres. */
  descricao: string;
  /** Referencia normativa aplicavel (ex: RTCBMRS N.01/2024 Art. 15). Opcional, max 200 chars. */
  normaReferencia?: string;
}

/**
 * Payload para emissao de CIV (Comunicado de Inconformidade na Vistoria).
 * Endpoint: POST /api/licenciamentos/{id}/civ
 * Transicao: EM_VISTORIA -> CIV_EMITIDO
 * Roles: INSPETOR, CHEFE_SSEG_BBM
 */
export interface CivCreateDTO {
  /** Lista de nao-conformidades identificadas durante a vistoria. Minimo 1 item obrigatorio. */
  itens: CivItemCreateDTO[];
  /** Observacao geral do inspetor sobre a vistoria (opcional). */
  observacaoGeral?: string;
  /**
   * Prazo em dias corridos para o RT/RU corrigir as inconformidades e solicitar re-vistoria.
   * Conforme RTCBMRS N.01/2024: padrao 30 dias, minimo 1, maximo 365.
   */
  prazoCorrecaoEmDias: number;
}

/**
 * Payload para aprovacao da vistoria presencial (emissao do PrPCI).
 * Endpoint: POST /api/licenciamentos/{id}/aprovar-vistoria
 * Transicao: EM_VISTORIA -> PRPCI_EMITIDO
 * Roles: INSPETOR, CHEFE_SSEG_BBM
 */
export interface AprovacaoVistoriaCreateDTO {
  /**
   * Laudo/observacoes do inspetor registradas no historico do processo (opcional).
   * Maximo 5000 caracteres.
   */
  observacao?: string;
}
