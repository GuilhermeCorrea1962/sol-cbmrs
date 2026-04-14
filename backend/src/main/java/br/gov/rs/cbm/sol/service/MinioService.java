package br.gov.rs.cbm.sol.service;

import io.minio.*;
import io.minio.http.Method;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.io.InputStream;
import java.util.concurrent.TimeUnit;

/**
 * Servico de acesso ao MinIO.
 *
 * Encapsula todas as operacoes de storage de objetos (upload, download, delete,
 * URL pre-assinada, verificacao de existencia). Nao conhece regras de negocio;
 * apenas traduz excecoes do SDK para RuntimeException.
 *
 * O MinioClient e injetado a partir do bean definido em MinioConfig.
 */
@Service
public class MinioService {

    private static final Logger log = LoggerFactory.getLogger(MinioService.class);

    private final MinioClient minioClient;

    public MinioService(MinioClient minioClient) {
        this.minioClient = minioClient;
    }

    /**
     * Faz upload de um objeto para o bucket indicado.
     *
     * @param bucket     nome do bucket (ex: "sol-arquivos")
     * @param objectKey  chave do objeto no bucket (ex: "licenciamentos/1/PPCI/uuid_nome.pdf")
     * @param stream     stream de bytes do conteudo
     * @param contentType MIME type (ex: "application/pdf")
     * @param size       tamanho em bytes; -1 se desconhecido (usa multipart interno do SDK)
     */
    public void upload(String bucket, String objectKey, InputStream stream,
                       String contentType, long size) {
        try {
            minioClient.putObject(
                PutObjectArgs.builder()
                    .bucket(bucket)
                    .object(objectKey)
                    .stream(stream, size, 10 * 1024 * 1024) // part size 10 MB
                    .contentType(contentType)
                    .build()
            );
            log.debug("MinIO upload OK  bucket={} key={} size={}", bucket, objectKey, size);
        } catch (Exception ex) {
            throw new RuntimeException(
                "Falha ao fazer upload para MinIO [bucket=" + bucket + " key=" + objectKey + "]: "
                    + ex.getMessage(), ex);
        }
    }

    /**
     * Retorna um InputStream para leitura do objeto. O chamador e responsavel
     * por fechar o stream apos o uso.
     */
    public InputStream download(String bucket, String objectKey) {
        try {
            return minioClient.getObject(
                GetObjectArgs.builder()
                    .bucket(bucket)
                    .object(objectKey)
                    .build()
            );
        } catch (Exception ex) {
            throw new RuntimeException(
                "Falha ao baixar objeto do MinIO [bucket=" + bucket + " key=" + objectKey + "]: "
                    + ex.getMessage(), ex);
        }
    }

    /**
     * Remove um objeto do bucket. Ignora erro se o objeto nao existir.
     */
    public void delete(String bucket, String objectKey) {
        try {
            minioClient.removeObject(
                RemoveObjectArgs.builder()
                    .bucket(bucket)
                    .object(objectKey)
                    .build()
            );
            log.debug("MinIO delete OK  bucket={} key={}", bucket, objectKey);
        } catch (Exception ex) {
            log.warn("Falha ao remover objeto do MinIO [bucket={} key={}]: {}",
                bucket, objectKey, ex.getMessage());
            throw new RuntimeException(
                "Falha ao remover objeto do MinIO: " + ex.getMessage(), ex);
        }
    }

    /**
     * Gera uma URL pre-assinada GET valida pelo tempo indicado.
     *
     * @param expirySeconds tempo de validade em segundos (max 604800 = 7 dias para MinIO)
     */
    public String getPresignedUrl(String bucket, String objectKey, int expirySeconds) {
        try {
            return minioClient.getPresignedObjectUrl(
                GetPresignedObjectUrlArgs.builder()
                    .method(Method.GET)
                    .bucket(bucket)
                    .object(objectKey)
                    .expiry(expirySeconds, TimeUnit.SECONDS)
                    .build()
            );
        } catch (Exception ex) {
            throw new RuntimeException(
                "Falha ao gerar URL pre-assinada [bucket=" + bucket + " key=" + objectKey + "]: "
                    + ex.getMessage(), ex);
        }
    }

    /**
     * Verifica se um objeto existe no bucket (usa StatObject).
     */
    public boolean objectExists(String bucket, String objectKey) {
        try {
            minioClient.statObject(
                StatObjectArgs.builder()
                    .bucket(bucket)
                    .object(objectKey)
                    .build()
            );
            return true;
        } catch (Exception ex) {
            return false;
        }
    }
}
