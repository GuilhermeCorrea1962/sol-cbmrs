package br.gov.rs.cbm.sol.dto;

import br.gov.rs.cbm.sol.entity.enums.TipoUsuario;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * DTO para criacao de novo Usuario.
 * Inclui campo senha que sera enviado ao Keycloak.
 */
public record UsuarioCreateDTO(

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

        @NotBlank(message = "Senha e obrigatoria")
        @Size(min = 8, message = "Senha deve ter no minimo 8 caracteres")
        String senha,

        // Dados do RT — opcionais, obrigatorios apenas para tipoUsuario == RT
        @Size(max = 50)
        String numeroRegistro,

        @Size(max = 10)
        String tipoConselho,

        @Size(max = 200)
        String especialidade
) {}
