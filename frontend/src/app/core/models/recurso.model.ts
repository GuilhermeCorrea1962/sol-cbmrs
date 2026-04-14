/**
 * recurso.model.ts
 * DTOs para o modulo de Recurso CIA/CIV (P10 — Sprint F7).
 *
 * Fluxo de status:
 *   CIA_EMITIDO / CIV_EMITIDO
 *     -> (RT submete)      -> RECURSO_SUBMETIDO
 *     -> (Admin aceita)    -> RECURSO_EM_ANALISE
 *     -> (Comissao vota)   -> RECURSO_EM_ANALISE (incremental)
 *     -> (Admin decide)    -> RECURSO_DEFERIDO | RECURSO_INDEFERIDO
 *
 *   Alternativa:
 *     RECURSO_SUBMETIDO -> (Admin recusa) -> CIA_EMITIDO | CIV_EMITIDO (retorna)
 */

/**
 * Enviado pelo RT ao contestar um CIA ou CIV.
 * Endpoint: POST /api/licenciamentos/{id}/submeter-recurso
 * Roles: qualquer usuario autenticado que seja RT do licenciamento
 */
export interface RecursoSubmeterDTO {
  /** Justificativa da contestacao. Minimo de 50 caracteres. */
  justificativa: string;
}

/**
 * Enviado pelo ADMIN ao recusar o recurso na triagem.
 * Endpoint: POST /api/licenciamentos/{id}/recusar-recurso
 * Roles: ADMIN, CHEFE_SSEG_BBM
 * Transicao: RECURSO_SUBMETIDO -> CIA_EMITIDO | CIV_EMITIDO
 */
export interface RecursoRecusarDTO {
  /** Motivo da recusa na triagem. Obrigatorio. */
  motivo: string;
}

/**
 * Enviado por cada membro da comissao ao votar no recurso.
 * Endpoint: POST /api/licenciamentos/{id}/votar-recurso
 * Roles: ANALISTA, CHEFE_SSEG_BBM
 * Transicao: incrementa contagem de votos em RECURSO_EM_ANALISE
 */
export interface RecursoVotoDTO {
  /** Voto do membro: DEFERIDO ou INDEFERIDO. */
  decisao: 'DEFERIDO' | 'INDEFERIDO';
  /** Fundamentacao tecnica do voto. Obrigatoria. */
  justificativa: string;
}

/**
 * Enviado pelo ADMIN ao registrar a decisao final do recurso.
 * Endpoint: POST /api/licenciamentos/{id}/decidir-recurso
 * Roles: ADMIN, CHEFE_SSEG_BBM
 * Transicao: RECURSO_EM_ANALISE -> RECURSO_DEFERIDO | RECURSO_INDEFERIDO
 */
export interface RecursoDecisaoDTO {
  /** Decisao final: DEFERIDO ou INDEFERIDO. */
  decisao: 'DEFERIDO' | 'INDEFERIDO';
  /** Fundamentacao da decisao final. Obrigatoria. */
  fundamentacao: string;
}
