package br.gov.rs.cbm.sol.service;

import br.gov.rs.cbm.sol.dto.ArquivoEDDTO;
import br.gov.rs.cbm.sol.entity.ArquivoED;
import br.gov.rs.cbm.sol.entity.Licenciamento;
import br.gov.rs.cbm.sol.entity.Usuario;
import br.gov.rs.cbm.sol.entity.enums.TipoArquivo;
import br.gov.rs.cbm.sol.exception.BusinessException;
import br.gov.rs.cbm.sol.exception.ResourceNotFoundException;
import br.gov.rs.cbm.sol.repository.ArquivoEDRepository;
import br.gov.rs.cbm.sol.repository.LicenciamentoRepository;
import br.gov.rs.cbm.sol.repository.UsuarioRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Servico de gestao de arquivos digitais (ArquivoED) do sistema SOL.
 *
 * Responsabilidades:
 *  - Validar tipo MIME e tamanho do upload (RN-ARQ-001 a 003)
 *  - Gerar chave unica no MinIO  (padrao: licenciamentos/{id}/{tipo}/{uuid}_{nome})
 *  - Persistir metadados em SOL.ARQUIVO_ED
 *  - Fornecer download (stream) e URL pre-assinada
 *  - Excluir do MinIO + banco de forma atomica
 *
 * Bucket usado: minio.buckets.arquivos (sol-arquivos)
 * Tamanho maximo: 50 MB (espelhado em application.yml multipart)
 */
@Service
@Transactional(readOnly = true)
public class ArquivoService {

    private static final Logger log = LoggerFactory.getLogger(ArquivoService.class);

    private static final long MAX_TAMANHO_BYTES = 50L * 1024 * 1024; // 50 MB

    // Tipos MIME aceitos (RN-ARQ-003)
    private static final List<String> MIME_PERMITIDOS = List.of(
        "application/pdf",
        "image/jpeg",
        "image/png",
        "image/tiff",
        "application/zip",
        "application/x-zip-compressed",
        "application/vnd.dwg",
        "application/octet-stream"
    );

    // Presigned URL valida por 1 hora por padrao
    private static final int PRESIGNED_EXPIRY_SEGUNDOS = 3600;

    @Value("${minio.buckets.arquivos}")
    private String bucketArquivos;

    private final MinioService minioService;
    private final ArquivoEDRepository arquivoEDRepository;
    private final LicenciamentoRepository licenciamentoRepository;
    private final UsuarioRepository usuarioRepository;

    public ArquivoService(MinioService minioService,
                          ArquivoEDRepository arquivoEDRepository,
                          LicenciamentoRepository licenciamentoRepository,
                          UsuarioRepository usuarioRepository) {
        this.minioService = minioService;
        this.arquivoEDRepository = arquivoEDRepository;
        this.licenciamentoRepository = licenciamentoRepository;
        this.usuarioRepository = usuarioRepository;
    }

    // ---------------------------------------------------------------------------
    // Upload
    // ---------------------------------------------------------------------------

    /**
     * Faz upload de um arquivo para o licenciamento indicado.
     *
     * @param file           arquivo enviado via multipart
     * @param licenciamentoId ID do licenciamento ao qual o arquivo pertence
     * @param tipoArquivo    tipo logico do documento (PPCI, ART_RRT, etc.)
     * @param keycloakId     sub do JWT do usuario que esta fazendo upload
     * @return DTO com metadados do arquivo persistido
     */
    @Transactional
    public ArquivoEDDTO upload(MultipartFile file,
                               Long licenciamentoId,
                               TipoArquivo tipoArquivo,
                               String keycloakId) {
        // RN-ARQ-001: arquivo nao pode ser vazio
        if (file == null || file.isEmpty()) {
            throw new BusinessException("RN-ARQ-001", "Arquivo nao pode ser vazio");
        }

        // RN-ARQ-002: tamanho maximo 50 MB
        if (file.getSize() > MAX_TAMANHO_BYTES) {
            throw new BusinessException("RN-ARQ-002",
                "Arquivo excede o tamanho maximo permitido de 50 MB");
        }

        // RN-ARQ-003: validar tipo MIME
        String contentType = file.getContentType();
        if (contentType == null || contentType.isBlank()) {
            contentType = "application/octet-stream";
        }
        String nomeOriginal = file.getOriginalFilename() != null
            ? file.getOriginalFilename() : "arquivo";
        if (!MIME_PERMITIDOS.contains(contentType)) {
            // Aceita arquivos com extensao .pdf mesmo com MIME generico
            if (!nomeOriginal.toLowerCase().endsWith(".pdf")) {
                throw new BusinessException("RN-ARQ-003",
                    "Tipo de arquivo nao permitido: " + contentType
                    + ". Tipos aceitos: PDF, JPEG, PNG, TIFF, ZIP, DWG");
            }
            contentType = "application/pdf";
        }

        // Carrega licenciamento
        Licenciamento licenciamento = licenciamentoRepository.findById(licenciamentoId)
            .orElseThrow(() -> new ResourceNotFoundException("Licenciamento", licenciamentoId));

        // Busca usuario autenticado (pode ser null se nao encontrado localmente)
        Usuario usuarioUpload = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);

        // Gera chave unica no MinIO
        String uuid = UUID.randomUUID().toString();
        String nomeSeguro = sanitizarNome(nomeOriginal);
        String objectKey = String.format("licenciamentos/%d/%s/%s_%s",
            licenciamentoId, tipoArquivo.name(), uuid, nomeSeguro);

        // Envia para o MinIO
        try (InputStream is = file.getInputStream()) {
            minioService.upload(bucketArquivos, objectKey, is, contentType, file.getSize());
        } catch (IOException ioEx) {
            throw new BusinessException("RN-ARQ-004",
                "Erro ao ler o arquivo enviado: " + ioEx.getMessage());
        } catch (RuntimeException ex) {
            throw new BusinessException("RN-ARQ-004",
                "Falha ao armazenar arquivo no MinIO: " + ex.getMessage());
        }

        // Persiste metadados
        ArquivoED arquivo = ArquivoED.builder()
            .nomeArquivo(nomeOriginal)
            .identificadorAlfresco(objectKey)   // campo mantido com nome legado
            .bucketMinio(bucketArquivos)
            .contentType(contentType)
            .tamanho(file.getSize())
            .tipoArquivo(tipoArquivo)
            .licenciamento(licenciamento)
            .usuarioUpload(usuarioUpload)
            .build();

        ArquivoED salvo = arquivoEDRepository.save(arquivo);
        log.info("Arquivo salvo: id={} licenciamento={} tipo={} key={}",
            salvo.getId(), licenciamentoId, tipoArquivo, objectKey);

        return toDTO(salvo);
    }

    // ---------------------------------------------------------------------------
    // Download
    // ---------------------------------------------------------------------------

    /**
     * Retorna um InputStream para download direto do arquivo.
     * O chamador (controller) e responsavel por fechar o stream.
     */
    public InputStream download(Long arquivoId) {
        ArquivoED arquivo = buscarPorId(arquivoId);
        return minioService.download(arquivo.getBucketMinio(), arquivo.getIdentificadorAlfresco());
    }

    /**
     * Gera URL pre-assinada para download direto pelo browser (valida 1 hora).
     */
    public String getPresignedUrl(Long arquivoId) {
        ArquivoED arquivo = buscarPorId(arquivoId);
        return minioService.getPresignedUrl(
            arquivo.getBucketMinio(),
            arquivo.getIdentificadorAlfresco(),
            PRESIGNED_EXPIRY_SEGUNDOS
        );
    }

    // ---------------------------------------------------------------------------
    // Consultas
    // ---------------------------------------------------------------------------

    public ArquivoEDDTO findById(Long arquivoId) {
        return toDTO(buscarPorId(arquivoId));
    }

    public List<ArquivoEDDTO> findByLicenciamento(Long licenciamentoId) {
        return arquivoEDRepository.findByLicenciamentoId(licenciamentoId)
            .stream()
            .map(this::toDTO)
            .collect(Collectors.toList());
    }

    public List<ArquivoEDDTO> findByLicenciamentoETipo(Long licenciamentoId, TipoArquivo tipo) {
        return arquivoEDRepository.findByLicenciamentoIdAndTipoArquivo(licenciamentoId, tipo)
            .stream()
            .map(this::toDTO)
            .collect(Collectors.toList());
    }

    // ---------------------------------------------------------------------------
    // Exclusao
    // ---------------------------------------------------------------------------

    /**
     * Remove o arquivo do MinIO e do banco (exclusao fisica).
     * Falha no MinIO e logada como aviso mas nao impede a remocao do banco.
     */
    @Transactional
    public void delete(Long arquivoId) {
        ArquivoED arquivo = buscarPorId(arquivoId);

        try {
            minioService.delete(arquivo.getBucketMinio(), arquivo.getIdentificadorAlfresco());
        } catch (RuntimeException ex) {
            log.warn("Nao foi possivel remover do MinIO (id={}): {}", arquivoId, ex.getMessage());
        }

        arquivoEDRepository.delete(arquivo);
        log.info("Arquivo excluido: id={} key={}", arquivoId, arquivo.getIdentificadorAlfresco());
    }

    // ---------------------------------------------------------------------------
    // Helpers internos
    // ---------------------------------------------------------------------------

    private ArquivoED buscarPorId(Long arquivoId) {
        return arquivoEDRepository.findById(arquivoId)
            .orElseThrow(() -> new ResourceNotFoundException("ArquivoED", arquivoId));
    }

    public ArquivoEDDTO toDTO(ArquivoED a) {
        return new ArquivoEDDTO(
            a.getId(),
            a.getNomeArquivo(),
            a.getIdentificadorAlfresco(),
            a.getBucketMinio(),
            a.getContentType(),
            a.getTamanho(),
            a.getTipoArquivo(),
            a.getLicenciamento() != null ? a.getLicenciamento().getId() : null,
            a.getUsuarioUpload() != null ? a.getUsuarioUpload().getId() : null,
            a.getUsuarioUpload() != null ? a.getUsuarioUpload().getNome() : null,
            a.getDtUpload()
        );
    }

    /** Remove caracteres especiais do nome do arquivo para uso seguro como chave. */
    private String sanitizarNome(String nome) {
        if (nome == null || nome.isBlank()) return "arquivo";
        return nome.replaceAll("[^a-zA-Z0-9._\\-]", "_");
    }
}
