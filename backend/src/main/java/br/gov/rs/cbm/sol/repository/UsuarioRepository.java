package br.gov.rs.cbm.sol.repository;

import br.gov.rs.cbm.sol.entity.Usuario;
import br.gov.rs.cbm.sol.entity.enums.StatusCadastro;
import br.gov.rs.cbm.sol.entity.enums.TipoUsuario;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface UsuarioRepository extends JpaRepository<Usuario, Long> {

    Optional<Usuario> findByCpf(String cpf);

    Optional<Usuario> findByEmail(String email);

    Optional<Usuario> findByKeycloakId(String keycloakId);

    List<Usuario> findByTipoUsuario(TipoUsuario tipoUsuario);

    List<Usuario> findByStatusCadastro(StatusCadastro statusCadastro);

    List<Usuario> findByTipoUsuarioAndStatusCadastro(TipoUsuario tipoUsuario, StatusCadastro statusCadastro);

    boolean existsByCpf(String cpf);

    boolean existsByEmail(String email);

    @Query("SELECT u FROM Usuario u WHERE u.ativo = true AND u.tipoUsuario = :tipo ORDER BY u.nome")
    List<Usuario> findAtivosporTipo(@Param("tipo") TipoUsuario tipo);

    @Query("SELECT u FROM Usuario u WHERE u.ativo = true AND u.tipoUsuario = 'ANALISTA' AND u.statusCadastro = 'APROVADO'")
    List<Usuario> findAnalistasDisponiveis();

    @Query("SELECT u FROM Usuario u WHERE u.ativo = true AND u.tipoUsuario = 'INSPETOR' AND u.statusCadastro = 'APROVADO'")
    List<Usuario> findInspetoresDisponiveis();
}
