package br.gov.rs.cbm.sol.dto;

/**
 * DTO de entrada para operacoes de recurso CIA/CIV (P10).
 *
 * Usado nos endpoints:
 *   POST /licenciamentos/{id}/interpor-recurso  (motivo obrigatorio - RN-P10-002)
 *   POST /licenciamentos/{id}/iniciar-recurso   (motivo opcional)
 *   POST /licenciamentos/{id}/deferir-recurso   (motivo opcional)
 *   POST /licenciamentos/{id}/indeferir-recurso (motivo obrigatorio - RN-P10-005)
 */
public record RecursoDTO(String motivo) {}
