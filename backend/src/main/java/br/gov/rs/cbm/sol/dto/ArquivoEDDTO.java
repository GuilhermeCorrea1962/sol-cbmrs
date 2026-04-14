package br.gov.rs.cbm.sol.dto;

import br.gov.rs.cbm.sol.entity.enums.TipoArquivo;

import java.time.LocalDateTime;

/**
 * DTO de leitura de ArquivoED (documento eletronico do licenciamento).
 */
public record ArquivoEDDTO(

        Long id,

        String nomeArquivo,

        String identificadorAlfresco,

        String bucketMinio,

        String contentType,

        Long tamanho,

        TipoArquivo tipoArquivo,

        Long licenciamentoId,

        Long usuarioUploadId,

        String usuarioUploadNome,

        LocalDateTime dtUpload
) {}
