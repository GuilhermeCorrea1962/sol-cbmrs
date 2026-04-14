package br.gov.rs.cbm.sol.entity;

import br.gov.rs.cbm.sol.entity.enums.TipoArquivo;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(name = "ARQUIVO_ED", schema = "SOL")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ArquivoED {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "seq_arquivo_ed")
    @SequenceGenerator(name = "seq_arquivo_ed", sequenceName = "SOL.SEQ_ARQUIVO_ED", allocationSize = 1)
    @Column(name = "ID_ARQUIVO_ED")
    private Long id;

    @Column(name = "NOME_ARQUIVO", length = 500, nullable = false)
    private String nomeArquivo;

    // Chave do objeto no MinIO (campo mantido com nome original do Alfresco por compatibilidade)
    @Column(name = "IDENTIFICADOR_ALFRESCO", length = 500, nullable = false)
    private String identificadorAlfresco;

    @Column(name = "BUCKET_MINIO", length = 100)
    private String bucketMinio;

    @Column(name = "CONTENT_TYPE", length = 200)
    private String contentType;

    @Column(name = "TAMANHO")
    private Long tamanho;

    @Enumerated(EnumType.STRING)
    @Column(name = "TIPO_ARQUIVO", length = 30, nullable = false)
    private TipoArquivo tipoArquivo;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_LICENCIAMENTO", nullable = false)
    private Licenciamento licenciamento;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "ID_USUARIO_UPLOAD")
    private Usuario usuarioUpload;

    @CreationTimestamp
    @Column(name = "DT_UPLOAD", nullable = false, updatable = false)
    private LocalDateTime dtUpload;
}
