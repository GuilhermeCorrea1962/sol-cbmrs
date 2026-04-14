package br.gov.rs.cbm.sol.entity;

import br.gov.rs.cbm.sol.entity.converter.SimNaoBooleanConverter;
import br.gov.rs.cbm.sol.entity.enums.StatusLicenciamento;
import br.gov.rs.cbm.sol.entity.enums.TipoLicenciamento;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "LICENCIAMENTO", schema = "SOL")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Licenciamento {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_licenciamento")
    @SequenceGenerator(name = "seq_licenciamento", sequenceName = "SOL.SEQ_LICENCIAMENTO", allocationSize = 1)
    @Column(name = "ID_LICENCIAMENTO")
    private Long id;

    // Numero formatado: [Tipo][Seq 8d][Lote 2L][Versao 3d] ex: A 00000361 AA 001
    @Column(name = "NUMERO_PPCI", length = 20, unique = true)
    private String numeroPpci;

    @Enumerated(EnumType.STRING)
    @Column(name = "TIPO", length = 10, nullable = false)
    @Builder.Default
    private TipoLicenciamento tipo = TipoLicenciamento.PPCI;

    @Enumerated(EnumType.STRING)
    @Column(name = "STATUS", length = 30, nullable = false)
    @Builder.Default
    private StatusLicenciamento status = StatusLicenciamento.RASCUNHO;

    // Dados da edificacao
    @Column(name = "AREA_CONSTRUIDA", precision = 10, scale = 2)
    private BigDecimal areaConstruida;

    @Column(name = "ALTURA_MAXIMA", precision = 6, scale = 2)
    private BigDecimal alturaMaxima;

    @Column(name = "NUM_PAVIMENTOS")
    private Integer numPavimentos;

    @Column(name = "NUM_LOTE", length = 2)
    private String numLote;

    @Column(name = "NUM_VERSAO")
    private Integer numVersao;

    @Column(name = "TIPO_OCUPACAO", length = 200)
    private String tipoOcupacao;

    @Column(name = "USO_PREDOMINANTE", length = 200)
    private String usoPredominante;

    // Datas de validade
    @Column(name = "DT_VALIDADE_APPCI")
    private LocalDate dtValidadeAppci;

    @Column(name = "DT_VENCIMENTO_PRPCI")
    private LocalDate dtVencimentoPrpci;

    // Relacionamentos
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_ENDERECO", nullable = false)
    private Endereco endereco;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_RESPONSAVEL_TECNICO")
    private Usuario responsavelTecnico;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_RESPONSAVEL_USO")
    private Usuario responsavelUso;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_ANALISTA")
    private Usuario analista;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_INSPETOR")
    private Usuario inspetor;

    // Licenciamento pai (para renovacoes e recursos)
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_LICENCIAMENTO_PAI")
    private Licenciamento licenciamentoPai;

    @Convert(converter = SimNaoBooleanConverter.class)
    @Column(name = "ATIVO", length = 1, nullable = false)
    @Builder.Default
    private Boolean ativo = true;

    @Convert(converter = SimNaoBooleanConverter.class)
    @Column(name = "ISENTO_TAXA", length = 1)
    @Builder.Default
    private Boolean isentoTaxa = false;

    @Column(name = "OBS_ISENCAO", length = 1000)
    private String obsIsencao;

    // P14 - Renovacao: isenção específica da taxa de vistoria de renovação (RN-147)
    @Convert(converter = SimNaoBooleanConverter.class)
    @Column(name = "ISENTO_TAXA_RENOVACAO", length = 1)
    @Builder.Default
    private Boolean isentoTaxaRenovacao = false;

    @CreationTimestamp
    @Column(name = "DT_CRIACAO", nullable = false, updatable = false)
    private LocalDateTime dataCriacao;

    @UpdateTimestamp
    @Column(name = "DT_ATUALIZACAO")
    private LocalDateTime dataAtualizacao;

    @OneToMany(mappedBy = "licenciamento", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @Builder.Default
    private List<ArquivoED> arquivos = new ArrayList<>();

    @OneToMany(mappedBy = "licenciamento", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @Builder.Default
    private List<MarcoProcesso> marcos = new ArrayList<>();

    @OneToMany(mappedBy = "licenciamento", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @Builder.Default
    private List<Boleto> boletos = new ArrayList<>();
}
