package br.gov.rs.cbm.sol.dto;

import br.gov.rs.cbm.sol.entity.enums.StatusBoleto;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * DTO de leitura de Boleto (guia de recolhimento).
 */
public record BoletoDTO(

        Long id,

        String nossoNumero,

        String codigoBarras,

        String linhaDigitavel,

        BigDecimal valor,

        LocalDate dtEmissao,

        LocalDate dtVencimento,

        LocalDateTime dtPagamento,

        StatusBoleto status,

        String caminhoPdf,

        String obsPagamento,

        Long licenciamentoId,

        String numeroPpci,

        Long usuarioConfirmacaoId,

        String usuarioConfirmacaoNome,

        LocalDateTime dtCriacao,

        LocalDateTime dtAtualizacao
) {}
