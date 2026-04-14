package br.gov.rs.cbm.sol.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * DTO de leitura e escrita para Endereco.
 * Campos id e dataCriacao omitidos — gerados pelo servidor.
 */
public record EnderecoDTO(

        @NotBlank(message = "CEP e obrigatorio")
        @Pattern(regexp = "\\d{8}", message = "CEP deve conter 8 digitos numericos")
        String cep,

        @NotBlank(message = "Logradouro e obrigatorio")
        @Size(max = 200)
        String logradouro,

        @Size(max = 20)
        String numero,

        @Size(max = 100)
        String complemento,

        @NotBlank(message = "Bairro e obrigatorio")
        @Size(max = 100)
        String bairro,

        @NotBlank(message = "Municipio e obrigatorio")
        @Size(max = 100)
        String municipio,

        @NotBlank(message = "UF e obrigatoria")
        @Size(min = 2, max = 2, message = "UF deve ter 2 caracteres")
        String uf,

        BigDecimal latitude,

        BigDecimal longitude,

        LocalDateTime dataAtualizacao
) {}
