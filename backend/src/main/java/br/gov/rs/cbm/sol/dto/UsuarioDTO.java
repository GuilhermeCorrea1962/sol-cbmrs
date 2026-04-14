package br.gov.rs.cbm.sol.dto;

import br.gov.rs.cbm.sol.entity.enums.StatusCadastro;
import br.gov.rs.cbm.sol.entity.enums.TipoUsuario;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.LocalDateTime;

/**
 * DTO de leitura/atualizacao de Usuario.
 * Campos sensiveis (senha) omitidos.
 */
public record UsuarioDTO(

        Long id,

        String keycloakId,

        @NotBlank(message = "CPF e obrigatorio")
        @Size(min = 11, max = 11, message = "CPF deve ter 11 digitos")
        String cpf,

        @NotBlank(message = "Nome e obrigatorio")
        @Size(max = 200)
        String nome,

        @NotBlank(message = "E-mail e obrigatorio")
        @Email(message = "E-mail invalido")
        @Size(max = 200)
        String email,

        @Size(max = 20)
        String telefone,

        @NotNull(message = "Tipo de usuario e obrigatorio")
        TipoUsuario tipoUsuario,

        StatusCadastro statusCadastro,

        // Dados do RT
        @Size(max = 50)
        String numeroRegistro,

        @Size(max = 10)
        String tipoConselho,

        @Size(max = 200)
        String especialidade,

        Boolean ativo,

        LocalDateTime dataCriacao,

        LocalDateTime dataAtualizacao
) {}
