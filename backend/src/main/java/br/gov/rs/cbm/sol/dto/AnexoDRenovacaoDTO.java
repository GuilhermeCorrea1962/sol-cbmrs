package br.gov.rs.cbm.sol.dto;

/**
 * DTO de resposta para leitura e aceite do Anexo D de Renovacao (P14 -- Fase 2).
 *
 * Retornado pelos endpoints:
 *   GET /licenciamentos/{id}/renovacao/anexo-d  -- leitura do termo
 *   PUT /licenciamentos/{id}/renovacao/aceitar-anexo-d  -- aceite
 *   DELETE /licenciamentos/{id}/renovacao/aceitar-anexo-d  -- remocao do aceite
 *
 * Referencia: TermoLicenciamentoRN.retornoCienciaETermoRenovacao() + AppciRenovacaoDTO
 * na especificacao Java EE (Requisitos_P14 secao 5.1 e 5.2).
 *
 * @param idLicenciamento   ID do licenciamento em renovacao
 * @param numeroPpci        Numero formatado do PPCI (ex: A 00000361 AA 001)
 * @param statusAtual       Situacao corrente do licenciamento (enum como String)
 * @param aceiteRegistrado  true se o usuario autenticado ja aceitou o Anexo D
 * @param dtValidadeAppci   Data de validade do APPCI vigente (formato ISO: yyyy-MM-dd)
 * @param textoTermos       Texto completo do Anexo D de Renovacao para exibicao no portal
 */
public record AnexoDRenovacaoDTO(
    Long    idLicenciamento,
    String  numeroPpci,
    String  statusAtual,
    Boolean aceiteRegistrado,
    String  dtValidadeAppci,
    String  textoTermos
) {}
