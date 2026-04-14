package br.gov.rs.cbm.sol.entity;

import br.gov.rs.cbm.sol.entity.enums.StatusBoleto;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "BOLETO", schema = "SOL")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Boleto {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_boleto")
    @SequenceGenerator(name = "seq_boleto", sequenceName = "SOL.SEQ_BOLETO", allocationSize = 1)
    @Column(name = "ID_BOLETO")
    private Long id;

    @Column(name = "NOSSO_NUMERO", length = 20)
    private String nossoNumero;

    @Column(name = "CODIGO_BARRAS", length = 60)
    private String codigoBarras;

    @Column(name = "LINHA_DIGITAVEL", length = 60)
    private String linhaDigitavel;

    @Column(name = "VALOR", precision = 10, scale = 2, nullable = false)
    private BigDecimal valor;

    @Column(name = "DT_EMISSAO", nullable = false)
    private LocalDate dtEmissao;

    @Column(name = "DT_VENCIMENTO", nullable = false)
    private LocalDate dtVencimento;

    @Column(name = "DT_PAGAMENTO")
    private LocalDateTime dtPagamento;

    @Enumerated(EnumType.STRING)
    @Column(name = "STATUS", length = 15, nullable = false)
    @Builder.Default
    private StatusBoleto status = StatusBoleto.PENDENTE;

    // Caminho do PDF da guia de recolhimento no MinIO
    @Column(name = "CAMINHO_PDF", length = 500)
    private String caminhoPdf;

    @Column(name = "OBS_PAGAMENTO", length = 500)
    private String obsPagamento;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_LICENCIAMENTO", nullable = false)
    private Licenciamento licenciamento;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_USUARIO_CONFIRMACAO")
    private Usuario usuarioConfirmacao;

    @CreationTimestamp
    @Column(name = "DT_CRIACAO", nullable = false, updatable = false)
    private LocalDateTime dtCriacao;

    @UpdateTimestamp
    @Column(name = "DT_ATUALIZACAO")
    private LocalDateTime dtAtualizacao;
}
