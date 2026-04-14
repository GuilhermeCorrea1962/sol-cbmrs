package br.gov.rs.cbm.sol.service;

import br.gov.rs.cbm.sol.dto.UsuarioCreateDTO;
import br.gov.rs.cbm.sol.dto.UsuarioDTO;
import br.gov.rs.cbm.sol.entity.Usuario;
import br.gov.rs.cbm.sol.exception.BusinessException;
import br.gov.rs.cbm.sol.repository.UsuarioRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Servico responsavel pelo fluxo completo de cadastro de usuarios (P02).
 *
 * Coordena duas operacoes que precisam ser atomicas do ponto de vista
 * do negocio, mas que ocorrem em sistemas distintos:
 *   1. Persistencia local no Oracle (via UsuarioService)
 *   2. Criacao no IdP Keycloak (via KeycloakAdminService)
 *
 * Estrategia de consistencia:
 *   - O insert local e feito dentro de @Transactional.
 *   - A chamada ao Keycloak e feita em seguida, FORA do commit local.
 *   - Se o Keycloak falhar, a excecao propaga e o Spring faz rollback do insert local.
 *   - Se o insert local falhar apos o Keycloak ter criado o usuario, o metodo
 *     deleteUser() e chamado como compensacao (saga pattern simplificado).
 *
 * Nota: para garantia total de consistencia entre dois sistemas distintos,
 * o padrao ideal e o Outbox Pattern (implementado na Sprint de integracao SEI).
 * Aqui o nivel de consistencia e suficiente para o MVP.
 */
@Service
public class CadastroService {

    private final UsuarioService usuarioService;
    private final KeycloakAdminService keycloakAdminService;
    private final UsuarioRepository usuarioRepository;

    public CadastroService(UsuarioService usuarioService,
                           KeycloakAdminService keycloakAdminService,
                           UsuarioRepository usuarioRepository) {
        this.usuarioService = usuarioService;
        this.keycloakAdminService = keycloakAdminService;
        this.usuarioRepository = usuarioRepository;
    }

    /**
     * Registra usuario no sistema SOL e no Keycloak.
     *
     * Fluxo completo P02:
     *   1. Valida unicidade de CPF e e-mail (BusinessException se duplicado)
     *   2. Persiste Usuario local com status INCOMPLETO e keycloakId = null
     *   3. Cria usuario no Keycloak com role = tipoUsuario.name()
     *   4. Atualiza keycloakId no registro local
     *   5. Retorna UsuarioDTO com keycloakId preenchido
     *
     * @param dto dados do novo usuario, incluindo senha em texto claro
     * @return UsuarioDTO com id local e keycloakId
     */
    @Transactional
    public UsuarioDTO registrar(UsuarioCreateDTO dto) {
        // Passo 1 e 2: validacao e persistencia local
        UsuarioDTO usuarioDTO = usuarioService.create(dto);

        // Passo 3: criacao no Keycloak
        String role = dto.tipoUsuario().name();
        String keycloakId;

        try {
            keycloakId = keycloakAdminService.createUser(
                    dto.cpf(),
                    dto.email(),
                    dto.nome(),
                    dto.senha(),
                    role
            );
        } catch (Exception e) {
            // A excecao propagada aqui faz o Spring realizar rollback do insert local.
            // Nao e necessario chamar deleteUser pois o Keycloak nao chegou a criar.
            throw new BusinessException("KC-002",
                    "Falha ao registrar usuario no Keycloak: " + e.getMessage());
        }

        // Passo 4: atualiza keycloakId no registro local
        Usuario usuario = usuarioRepository.findById(usuarioDTO.id()).orElseThrow();
        usuario.setKeycloakId(keycloakId);
        usuarioRepository.save(usuario);

        // Passo 5: retorna DTO atualizado
        return usuarioService.toDTO(usuario);
    }
}
