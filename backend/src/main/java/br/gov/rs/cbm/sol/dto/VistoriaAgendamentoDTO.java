package br.gov.rs.cbm.sol.dto;

import java.time.LocalDate;

/**
 * DTO de agendamento de vistoria presencial (P07).
 *
 * dataVistoria -- data prevista para a realizacao da vistoria.
 *                 Campo obrigatorio (RN-P07-002). Deve ser informada pelo
 *                 analista ou ADMIN ao agendar a vistoria.
 *
 * observacao   -- informacoes complementares sobre o agendamento (opcional).
 *                 Pode descrever restricoes de acesso, contatos ou
 *                 instrucoes especificas para o inspetor.
 */
public record VistoriaAgendamentoDTO(LocalDate dataVistoria, String observacao) {}
