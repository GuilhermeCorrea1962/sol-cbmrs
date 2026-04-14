package br.gov.rs.cbm.sol.dto;

/**
 * DTO de solicitacao/efetivacao de extincao de licenciamento (P12).
 *
 * @param motivo justificativa da extincao (obrigatorio em ambas as operacoes)
 */
public record ExtincaoDTO(String motivo) {}
