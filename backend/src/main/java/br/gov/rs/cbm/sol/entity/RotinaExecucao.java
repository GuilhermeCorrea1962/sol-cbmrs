package br.gov.rs.cbm.sol.entity;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;

/**
 * Entidade de rastreabilidade de execucao dos Jobs automaticos (P13).
 *
 * Cada execucao da rotina diaria de alvaras registra um linha nesta tabela.
 * O campo dataFimExecucao da ultima rotina CONCLUIDA e usado como baseline
 * temporal para calcular as janelas de notificacao (RN-140).
 *
 * Tabela Oracle: SOL.ROTINA_EXECUCAO
 * Sequence:      SOL.SEQ_ROTINA_EXECUCAO (criada via DDL no deploy)
 */
@Entity
@Table(name = "ROTINA_EXECUCAO", schema = "SOL")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class RotinaExecucao {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_rotina_execucao")
    @SequenceGenerator(name = "seq_rotina_execucao", sequenceName = "SOL.SEQ_ROTINA_EXECUCAO", allocationSize = 1)
    @Column(name = "ID_ROTINA_EXECUCAO")
    private Long id;

    @Column(name = "TIPO_ROTINA", length = 60, nullable = false)
    private String tipoRotina;

    @CreationTimestamp
    @Column(name = "DTH_CRIACAO", nullable = false, updatable = false)
    private LocalDateTime dataHoraCriacao;

    @Column(name = "DTH_INICIO_EXECUCAO")
    private LocalDateTime dataInicioExecucao;

    @Column(name = "DTH_FIM_EXECUCAO")
    private LocalDateTime dataFimExecucao;

    // Valores: EM_EXECUCAO / CONCLUIDA / ERRO
    @Column(name = "DSC_SITUACAO", length = 15)
    private String situacao;

    @Column(name = "NR_PROCESSADOS")
    private Integer numProcessados;

    @Column(name = "NR_ERROS")
    private Integer numErros;

    @Column(name = "DSC_MENSAGEM_ERRO", length = 2000)
    private String mensagemErro;
}
