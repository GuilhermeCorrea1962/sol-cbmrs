package br.gov.rs.cbm.sol.dto;

/**
 * DTO de requisicao para operacoes do processo de Renovacao de Licenciamento (P14).
 *
 * O mesmo DTO e reutilizado em varios endpoints com campos opcionais distintos:
 *
 *   POST /renovacao/iniciar          -- apenas motivo (opcional)
 *   POST /renovacao/confirmar        -- apenas motivo (opcional)
 *   POST /renovacao/recusar          -- motivo (opcional)
 *   POST /renovacao/analisar-isencao -- deferida (obrigatorio)
 *   POST /renovacao/distribuir       -- inspetorId (obrigatorio)
 *   POST /renovacao/registrar-vistoria -- vistoriaAprovada (obrigatorio)
 *   POST /renovacao/homologar-vistoria -- deferida (obrigatorio)
 *
 * @param motivo           justificativa textual (opcional na maioria dos endpoints)
 * @param deferida         resultado da analise de isencao ou homologacao (ADMIN)
 * @param vistoriaAprovada resultado da vistoria realizada pelo Inspetor
 * @param inspetorId       ID do Usuario inspetor para distribuicao da vistoria
 */
public record RenovacaoRequestDTO(
    String  motivo,
    Boolean deferida,
    Boolean vistoriaAprovada,
    Long    inspetorId
) {}
