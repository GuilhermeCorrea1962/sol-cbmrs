package br.gov.rs.cbm.sol.dto;

/**
 * DTO de entrada para acoes de decisao na analise tecnica (P04).
 *
 * Usado nos endpoints:
 *   POST /licenciamentos/{id}/emitir-cia   (observacao obrigatoria)
 *   POST /licenciamentos/{id}/deferir      (observacao opcional)
 *   POST /licenciamentos/{id}/indeferir    (observacao obrigatoria)
 */
public record AnaliseDecisaoDTO(String observacao) {}
