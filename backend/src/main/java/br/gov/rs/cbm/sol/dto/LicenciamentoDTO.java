package br.gov.rs.cbm.sol.dto;

import br.gov.rs.cbm.sol.entity.enums.StatusLicenciamento;
import br.gov.rs.cbm.sol.entity.enums.TipoLicenciamento;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * DTO de leitura de Licenciamento.
 * EnderecoDTO embutido; usuarios representados por id e nome apenas.
 */
public record LicenciamentoDTO(

        Long id,

        String numeroPpci,

        TipoLicenciamento tipo,

        StatusLicenciamento status,

        BigDecimal areaConstruida,

        BigDecimal alturaMaxima,

        Integer numPavimentos,

        String numLote,

        Integer numVersao,

        String tipoOcupacao,

        String usoPredominante,

        LocalDate dtValidadeAppci,

        LocalDate dtVencimentoPrpci,

        EnderecoDTO endereco,

        // Referencias simplificadas de usuarios
        Long responsavelTecnicoId,
        String responsavelTecnicoNome,

        Long responsavelUsoId,
        String responsavelUsoNome,

        Long analistaId,
        String analistaNome,

        Long inspetorId,
        String inspetorNome,

        Long licenciamentoPaiId,

        Boolean ativo,

        Boolean isentoTaxa,

        String obsIsencao,

        LocalDateTime dataCriacao,

        LocalDateTime dataAtualizacao
) {}
