package br.gov.rs.cbm.sol.service;

import br.gov.rs.cbm.sol.dto.UsuarioCreateDTO;
import br.gov.rs.cbm.sol.dto.UsuarioDTO;
import br.gov.rs.cbm.sol.entity.Usuario;
import br.gov.rs.cbm.sol.entity.enums.StatusCadastro;
import br.gov.rs.cbm.sol.exception.BusinessException;
import br.gov.rs.cbm.sol.exception.ResourceNotFoundException;
import br.gov.rs.cbm.sol.repository.UsuarioRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional(readOnly = true)
public class UsuarioService {

    private final UsuarioRepository usuarioRepository;

    public UsuarioService(UsuarioRepository usuarioRepository) {
        this.usuarioRepository = usuarioRepository;
    }

    public List<UsuarioDTO> findAll() {
        return usuarioRepository.findAll().stream()
                .map(this::toDTO)
                .toList();
    }

    public UsuarioDTO findById(Long id) {
        return usuarioRepository.findById(id)
                .map(this::toDTO)
                .orElseThrow(() -> new ResourceNotFoundException("Usuario", id));
    }

    public UsuarioDTO findByCpf(String cpf) {
        return usuarioRepository.findByCpf(cpf)
                .map(this::toDTO)
                .orElseThrow(() -> new ResourceNotFoundException("Usuario", "cpf", cpf));
    }

    @Transactional
    public UsuarioDTO create(UsuarioCreateDTO dto) {
        if (usuarioRepository.existsByCpf(dto.cpf())) {
            throw new BusinessException("RN-002", "CPF ja cadastrado no sistema: " + dto.cpf());
        }
        if (usuarioRepository.existsByEmail(dto.email())) {
            throw new BusinessException("RN-002", "E-mail ja cadastrado no sistema: " + dto.email());
        }

        Usuario usuario = Usuario.builder()
                .cpf(dto.cpf())
                .nome(dto.nome())
                .email(dto.email())
                .telefone(dto.telefone())
                .tipoUsuario(dto.tipoUsuario())
                .statusCadastro(StatusCadastro.INCOMPLETO)
                .numeroRegistro(dto.numeroRegistro())
                .tipoConselho(dto.tipoConselho())
                .especialidade(dto.especialidade())
                .ativo(true)
                .build();

        // Nota: a senha (dto.senha()) deve ser enviada ao Keycloak pelo servico de integracao.
        // Este servico apenas persiste o usuario local. O keycloakId sera atualizado apos
        // confirmacao do IdP.

        return toDTO(usuarioRepository.save(usuario));
    }

    @Transactional
    public UsuarioDTO update(Long id, UsuarioDTO dto) {
        Usuario usuario = usuarioRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Usuario", id));

        usuario.setNome(dto.nome());
        usuario.setEmail(dto.email());
        usuario.setTelefone(dto.telefone());
        usuario.setTipoUsuario(dto.tipoUsuario());
        usuario.setNumeroRegistro(dto.numeroRegistro());
        usuario.setTipoConselho(dto.tipoConselho());
        usuario.setEspecialidade(dto.especialidade());

        if (dto.statusCadastro() != null) {
            usuario.setStatusCadastro(dto.statusCadastro());
        }

        return toDTO(usuarioRepository.save(usuario));
    }

    @Transactional
    public void deactivate(Long id) {
        Usuario usuario = usuarioRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Usuario", id));
        usuario.setAtivo(false);
        usuarioRepository.save(usuario);
    }

    // ---------------------------------------------------------------------------
    // Mapeamento manual Entity -> DTO
    // ---------------------------------------------------------------------------

    public UsuarioDTO toDTO(Usuario u) {
        return new UsuarioDTO(
                u.getId(),
                u.getKeycloakId(),
                u.getCpf(),
                u.getNome(),
                u.getEmail(),
                u.getTelefone(),
                u.getTipoUsuario(),
                u.getStatusCadastro(),
                u.getNumeroRegistro(),
                u.getTipoConselho(),
                u.getEspecialidade(),
                u.getAtivo(),
                u.getDataCriacao(),
                u.getDataAtualizacao()
        );
    }
}
