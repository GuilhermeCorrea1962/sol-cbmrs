package br.gov.rs.cbm.sol.dto;

import br.gov.rs.cbm.sol.entity.enums.TipoMarco;

import java.time.LocalDateTime;

/**
 * DTO de leitura de MarcoProcesso (linha do tempo de evento do licenciamento).
 */
public record MarcoProcessoDTO(

        Long id,

        TipoMarco tipoMarco,

        String observacao,

        Long licenciamentoId,

        Long usuarioId,

        String usuarioNome,

        LocalDateTime dtMarco
) {}
