package br.gov.rs.cbm.sol.dto;

/**
 * DTO de entrada para operacoes de troca de envolvidos (P09).
 *
 * Usado nos endpoints:
 *   POST /licenciamentos/{id}/solicitar-troca-rt  (motivo obrigatorio)
 *   POST /licenciamentos/{id}/autorizar-troca-rt  (motivo opcional)
 *   POST /licenciamentos/{id}/efetivar-troca-rt   (novoResponsavelId obrigatorio)
 *   POST /licenciamentos/{id}/efetivar-troca-ru   (novoResponsavelId obrigatorio)
 */
public record TrocaEnvolvidoDTO(Long novoResponsavelId, String motivo) {}
