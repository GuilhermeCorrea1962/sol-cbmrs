package br.gov.rs.cbm.sol.service;

import br.gov.rs.cbm.sol.exception.BusinessException;
import jakarta.ws.rs.core.Response;
import org.keycloak.admin.client.Keycloak;
import org.keycloak.admin.client.resource.RealmResource;
import org.keycloak.admin.client.resource.UsersResource;
import org.keycloak.representations.idm.CredentialRepresentation;
import org.keycloak.representations.idm.RoleRepresentation;
import org.keycloak.representations.idm.UserRepresentation;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.List;

/**
 * Servico de integracao com o Keycloak Admin API.
 *
 * Responsabilidades:
 *   - Criar usuario no realm SOL (P02)
 *   - Atribuir realm role ao usuario
 *   - Resetar senha
 *   - Habilitar/desabilitar usuario
 *   - Remover usuario (rollback em caso de falha)
 *
 * Todas as operacoes usam o Keycloak Admin Client configurado em KeycloakConfig,
 * autenticado no master realm via admin-cli.
 */
@Service
public class KeycloakAdminService {

    private final Keycloak keycloak;

    @Value("${keycloak.realm}")
    private String realm;

    public KeycloakAdminService(Keycloak keycloakAdminClient) {
        this.keycloak = keycloakAdminClient;
    }

    // ---------------------------------------------------------------------------
    // Criacao de usuario
    // ---------------------------------------------------------------------------

    /**
     * Cria usuario no realm SOL e retorna o keycloakId (UUID).
     *
     * Fluxo:
     *   1. Monta UserRepresentation com username=CPF, email, firstName=nome
     *   2. Define credencial (senha nao temporaria)
     *   3. POST /admin/realms/sol/users -> espera HTTP 201
     *   4. Extrai keycloakId do header Location da resposta
     *   5. Atribui a realm role correspondente ao TipoUsuario
     *
     * @param username CPF do usuario (usado como username no Keycloak)
     * @param email    e-mail do usuario
     * @param nome     nome completo (mapeado para firstName)
     * @param senha    senha em texto claro (armazenada criptografada pelo Keycloak)
     * @param role     nome da realm role: CIDADAO, RT, ANALISTA, INSPETOR, ADMIN, CHEFE_SSEG_BBM
     * @return UUID do usuario criado no Keycloak
     */
    public String createUser(String username, String email, String nome, String senha, String role) {
        RealmResource realmResource = keycloak.realm(realm);
        UsersResource usersResource = realmResource.users();

        UserRepresentation user = new UserRepresentation();
        user.setUsername(username);
        user.setEmail(email);
        user.setFirstName(nome);
        user.setEnabled(true);
        user.setEmailVerified(true);

        CredentialRepresentation credential = new CredentialRepresentation();
        credential.setTemporary(false);
        credential.setType(CredentialRepresentation.PASSWORD);
        credential.setValue(senha);
        user.setCredentials(List.of(credential));

        try (Response response = usersResource.create(user)) {
            if (response.getStatus() != 201) {
                String body = response.readEntity(String.class);
                throw new BusinessException("KC-001",
                        "Falha ao criar usuario no Keycloak. HTTP "
                        + response.getStatus() + ": " + body);
            }

            String location = response.getHeaderString("Location");
            String keycloakId = location.substring(location.lastIndexOf('/') + 1);

            assignRealmRole(realmResource, keycloakId, role);

            return keycloakId;
        }
    }

    // ---------------------------------------------------------------------------
    // Gestao de roles
    // ---------------------------------------------------------------------------

    /**
     * Atribui uma realm role ao usuario.
     * A role deve existir previamente no realm (criada durante o setup do Keycloak).
     */
    public void assignRealmRole(RealmResource realmResource, String keycloakId, String roleName) {
        try {
            RoleRepresentation role = realmResource.roles().get(roleName).toRepresentation();
            realmResource.users().get(keycloakId).roles().realmLevel().add(List.of(role));
        } catch (Exception e) {
            throw new BusinessException("KC-003",
                    "Falha ao atribuir role '" + roleName + "' ao usuario " + keycloakId
                    + ": " + e.getMessage());
        }
    }

    // ---------------------------------------------------------------------------
    // Operacoes de manutencao
    // ---------------------------------------------------------------------------

    /**
     * Remove usuario do Keycloak.
     * Usado como compensacao (rollback) quando a criacao local falha apos
     * o usuario ja ter sido criado no Keycloak.
     */
    public void deleteUser(String keycloakId) {
        try {
            keycloak.realm(realm).users().delete(keycloakId);
        } catch (Exception e) {
            // Operacao de compensacao -- nao propaga excecao para nao mascarar o erro original
        }
    }

    /**
     * Redefine a senha do usuario no Keycloak (P02 -- esqueci minha senha).
     */
    public void resetPassword(String keycloakId, String novaSenha) {
        CredentialRepresentation credential = new CredentialRepresentation();
        credential.setTemporary(false);
        credential.setType(CredentialRepresentation.PASSWORD);
        credential.setValue(novaSenha);
        keycloak.realm(realm).users().get(keycloakId).resetPassword(credential);
    }

    /**
     * Habilita ou desabilita o usuario no Keycloak.
     * Usado em suspensao de licenciamento (P12) e extincao.
     */
    public void setEnabled(String keycloakId, boolean enabled) {
        UserRepresentation user = keycloak.realm(realm).users().get(keycloakId).toRepresentation();
        user.setEnabled(enabled);
        keycloak.realm(realm).users().get(keycloakId).update(user);
    }
}
