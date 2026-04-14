package br.gov.rs.cbm.sol.dto;

import br.gov.rs.cbm.sol.entity.enums.TipoLicenciamento;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;

/**
 * DTO para criacao de novo Licenciamento (P03 — Wizard de Submissao).
 */
public record LicenciamentoCreateDTO(

        @NotNull(message = "Tipo de licenciamento e obrigatorio")
        TipoLicenciamento tipo,

        @DecimalMin(value = "0.01", message = "Area construida deve ser positiva")
        BigDecimal areaConstruida,

        @DecimalMin(value = "0.01", message = "Altura maxima deve ser positiva")
        BigDecimal alturaMaxima,

        @Positive(message = "Numero de pavimentos deve ser positivo")
        Integer numPavimentos,

        @Size(max = 200)
        String tipoOcupacao,

        @Size(max = 200)
        String usoPredominante,

        @NotNull(message = "Endereco e obrigatorio")
        @Valid
        EnderecoDTO endereco,

        // ID do RT declarado no wizard — opcional (pode ser preenchido depois)
        Long responsavelTecnicoId,

        // ID do RU (Responsavel pelo Uso)
        Long responsavelUsoId,

        // Licenciamento de origem em caso de renovacao
        Long licenciamentoPaiId
) {}
