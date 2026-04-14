package br.gov.rs.cbm.sol.dto;

/**
 * DTO de entrada para operacoes de isencao de taxa (P06).
 *
 * Usado nos endpoints:
 *   POST /licenciamentos/{id}/solicitar-isencao  (motivo obrigatorio)
 *   POST /licenciamentos/{id}/deferir-isencao    (observacao opcional)
 *   POST /licenciamentos/{id}/indeferir-isencao  (motivo obrigatorio)
 */
public record IsencaoRequestDTO(String motivo) {}
