package br.gov.rs.cbm.sol.config;

import io.minio.MinioClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Configuracao do cliente MinIO.
 *
 * Parametros lidos do application.yml: minio.url, minio.access-key, minio.secret-key.
 *
 * PRE-REQUISITO: o usuario MinIO utilizado (sol-app) deve ter a permissao
 * s3:GetBucketLocation na sua policy, pois o Java SDK chama esse endpoint
 * antes de qualquer PUT para determinar a regiao do bucket. O Go SDK (mc.exe)
 * tolera a ausencia dessa permissao silenciosamente, mas o Java SDK aborta
 * com "Access Denied" se receber 403 nessa chamada.
 *
 * A policy correta esta em: C:\SOL\infra\minio\sol-app-policy.json
 * Para reaplicar: mc admin policy create sol-minio sol-app-policy sol-app-policy.json
 */
@Configuration
public class MinioConfig {

    @Value("${minio.url}")
    private String minioUrl;

    @Value("${minio.access-key}")
    private String accessKey;

    @Value("${minio.secret-key}")
    private String secretKey;

    @Bean
    public MinioClient minioClient() {
        return MinioClient.builder()
            .endpoint(minioUrl)
            .credentials(accessKey, secretKey)
            .build();
    }
}
