package br.gov.rs.cbm.sol.entity;

import br.gov.rs.cbm.sol.entity.enums.TipoMarco;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(name = "MARCO_PROCESSO", schema = "SOL")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class MarcoProcesso {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_marco_processo")
    @SequenceGenerator(name = "seq_marco_processo", sequenceName = "SOL.SEQ_MARCO_PROCESSO", allocationSize = 1)
    @Column(name = "ID_MARCO_PROCESSO")
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(name = "TIPO_MARCO", length = 40, nullable = false)
    private TipoMarco tipoMarco;

    @Lob
    @Column(name = "OBSERVACAO")
    private String observacao;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_LICENCIAMENTO", nullable = false)
    private Licenciamento licenciamento;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_USUARIO")
    private Usuario usuario;

    @CreationTimestamp
    @Column(name = "DT_MARCO", nullable = false, updatable = false)
    private LocalDateTime dtMarco;
}
