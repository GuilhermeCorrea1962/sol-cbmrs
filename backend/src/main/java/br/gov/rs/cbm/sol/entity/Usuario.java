package br.gov.rs.cbm.sol.entity;

import br.gov.rs.cbm.sol.entity.converter.SimNaoBooleanConverter;
import br.gov.rs.cbm.sol.entity.enums.StatusCadastro;
import br.gov.rs.cbm.sol.entity.enums.TipoUsuario;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(name = "USUARIO", schema = "SOL",
        uniqueConstraints = {
                @UniqueConstraint(name = "UK_USUARIO_CPF", columnNames = "CPF"),
                @UniqueConstraint(name = "UK_USUARIO_EMAIL", columnNames = "EMAIL"),
                @UniqueConstraint(name = "UK_USUARIO_KEYCLOAK", columnNames = "ID_KEYCLOAK")
        })
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Usuario {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_usuario")
    @SequenceGenerator(name = "seq_usuario", sequenceName = "SOL.SEQ_USUARIO", allocationSize = 1)
    @Column(name = "ID_USUARIO")
    private Long id;

    @Column(name = "ID_KEYCLOAK", length = 36)
    private String keycloakId;

    @Column(name = "CPF", length = 11, nullable = false)
    private String cpf;

    @Column(name = "NOME", length = 200, nullable = false)
    private String nome;

    @Column(name = "EMAIL", length = 200, nullable = false)
    private String email;

    @Column(name = "TELEFONE", length = 20)
    private String telefone;

    @Enumerated(EnumType.STRING)
    @Column(name = "TIPO_USUARIO", length = 20, nullable = false)
    private TipoUsuario tipoUsuario;

    @Enumerated(EnumType.STRING)
    @Column(name = "STATUS_CADASTRO", length = 20, nullable = false)
    @Builder.Default
    private StatusCadastro statusCadastro = StatusCadastro.INCOMPLETO;

    // Dados do Responsavel Tecnico (RT)
    @Column(name = "NUMERO_REGISTRO", length = 50)
    private String numeroRegistro;

    @Column(name = "TIPO_CONSELHO", length = 10)
    private String tipoConselho; // CREA ou CAU

    @Column(name = "ESPECIALIDADE", length = 200)
    private String especialidade;

    @Convert(converter = SimNaoBooleanConverter.class)
    @Column(name = "ATIVO", length = 1, nullable = false)
    @Builder.Default
    private Boolean ativo = true;

    @CreationTimestamp
    @Column(name = "DT_CRIACAO", nullable = false, updatable = false)
    private LocalDateTime dataCriacao;

    @UpdateTimestamp
    @Column(name = "DT_ATUALIZACAO")
    private LocalDateTime dataAtualizacao;
}
