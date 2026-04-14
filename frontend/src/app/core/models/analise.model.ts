/**
 * Sprint F4 — Modelos para o modulo de Analise Tecnica (P04)
 *
 * DTOs espelham os records Java do backend:
 *   CiaCreateDTO         -> POST /api/licenciamentos/{id}/cia
 *   DeferimentoCreateDTO -> POST /api/licenciamentos/{id}/deferir
 *   IndeferimentoCreateDTO -> POST /api/licenciamentos/{id}/indeferir
 */

// ---------------------------------------------------------------------------
// CIA — Comunicado de Inconformidade na Analise
// ---------------------------------------------------------------------------

/** Um item individual de nao-conformidade dentro de um CIA */
export interface CiaItemCreateDTO {
  /**
   * Descricao objetiva da inconformidade encontrada.
   * Exemplos: "Planta sem escala definida", "Saida de emergencia bloqueada".
   * Maximo 500 caracteres.
   */
  descricao: string;
  /**
   * Referencia normativa opcional.
   * Exemplos: "RTCBMRS N.01/2024 Art. 15 §2", "NBR 9077:2001 Item 6.1".
   * Maximo 200 caracteres.
   */
  normaReferencia?: string;
}

/**
 * Payload para emissao de CIA.
 *
 * Endpoint: POST /api/licenciamentos/{id}/cia
 * Roles: ANALISTA, CHEFE_SSEG_BBM
 * Transicao: EM_ANALISE -> CIA_EMITIDO
 *
 * Apos emissao o RT recebe notificacao e tem prazoCorrecaoEmDias para
 * corrigir e reenviar o processo (que retorna a ANALISE_PENDENTE para
 * nova distribuicao — processo P05 do BPMN).
 */
export interface CiaCreateDTO {
  /** Lista de nao-conformidades identificadas na analise. Minimo 1 item. */
  itens: CiaItemCreateDTO[];
  /** Observacao geral livre do analista (opcional). */
  observacaoGeral?: string;
  /**
   * Prazo em dias corridos concedido ao RT para corrigir e reenviar.
   * Conforme RTCBMRS N.01/2024: padrao 30 dias. Minimo 1, maximo 365.
   */
  prazoCorrecaoEmDias: number;
}

// ---------------------------------------------------------------------------
// Deferimento
// ---------------------------------------------------------------------------

/**
 * Payload para deferir a analise tecnica.
 *
 * Endpoint: POST /api/licenciamentos/{id}/deferir
 * Roles: ANALISTA, CHEFE_SSEG_BBM
 * Transicao:
 *   EM_ANALISE -> VISTORIA_PENDENTE  (PPCI — exige vistoria presencial)
 *   EM_ANALISE -> DEFERIDO           (PSPCIM sem exigencia de vistoria)
 *
 * A regra de negocio de qual proximo estado aplicar e resolvida pelo backend
 * com base no TipoLicenciamento e nas configuracoes do processo.
 */
export interface DeferimentoCreateDTO {
  /** Observacao tecnica opcional registrada no historico do processo. */
  observacao?: string;
}

// ---------------------------------------------------------------------------
// Indeferimento
// ---------------------------------------------------------------------------

/**
 * Payload para indeferir a analise tecnica.
 *
 * Endpoint: POST /api/licenciamentos/{id}/indeferir
 * Roles: ANALISTA, CHEFE_SSEG_BBM
 * Transicao: EM_ANALISE -> INDEFERIDO
 *
 * O indeferimento encerra definitivamente o fluxo de analise.
 * A justificativa e registrada no processo e comunicada ao cidadao/RT.
 */
export interface IndeferimentoCreateDTO {
  /**
   * Justificativa tecnica completa do indeferimento — obrigatoria.
   * Minimo 20 caracteres, maximo 2000.
   */
  justificativa: string;
}
