package br.gov.rs.cbm.sol.service;

import br.gov.rs.cbm.sol.dto.EnderecoDTO;
import br.gov.rs.cbm.sol.dto.LicenciamentoCreateDTO;
import br.gov.rs.cbm.sol.dto.LicenciamentoDTO;
import br.gov.rs.cbm.sol.entity.Endereco;
import br.gov.rs.cbm.sol.entity.Licenciamento;
import br.gov.rs.cbm.sol.entity.MarcoProcesso;
import br.gov.rs.cbm.sol.entity.Usuario;
import br.gov.rs.cbm.sol.entity.enums.StatusLicenciamento;
import br.gov.rs.cbm.sol.entity.enums.TipoArquivo;
import br.gov.rs.cbm.sol.entity.enums.TipoMarco;
import br.gov.rs.cbm.sol.exception.BusinessException;
import br.gov.rs.cbm.sol.exception.ResourceNotFoundException;
import br.gov.rs.cbm.sol.repository.ArquivoEDRepository;
import br.gov.rs.cbm.sol.repository.EnderecoRepository;
import br.gov.rs.cbm.sol.repository.LicenciamentoRepository;
import br.gov.rs.cbm.sol.repository.MarcoProcessoRepository;
import br.gov.rs.cbm.sol.repository.UsuarioRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(readOnly = true)
public class LicenciamentoService {

    private final LicenciamentoRepository licenciamentoRepository;
    private final UsuarioRepository usuarioRepository;
    private final EnderecoRepository enderecoRepository;
    private final ArquivoEDRepository arquivoEDRepository;
    private final MarcoProcessoRepository marcoProcessoRepository;

    public LicenciamentoService(LicenciamentoRepository licenciamentoRepository,
                                UsuarioRepository usuarioRepository,
                                EnderecoRepository enderecoRepository,
                                ArquivoEDRepository arquivoEDRepository,
                                MarcoProcessoRepository marcoProcessoRepository) {
        this.licenciamentoRepository = licenciamentoRepository;
        this.usuarioRepository = usuarioRepository;
        this.enderecoRepository = enderecoRepository;
        this.arquivoEDRepository = arquivoEDRepository;
        this.marcoProcessoRepository = marcoProcessoRepository;
    }

    public Page<LicenciamentoDTO> findAll(Pageable pageable) {
        return licenciamentoRepository.findAll(pageable).map(this::toDTO);
    }

    public LicenciamentoDTO findById(Long id) {
        return licenciamentoRepository.findById(id)
                .map(this::toDTO)
                .orElseThrow(() -> new ResourceNotFoundException("Licenciamento", id));
    }

    public Page<LicenciamentoDTO> findByUsuario(Long usuarioId, Pageable pageable) {
        Usuario usuario = usuarioRepository.findById(usuarioId)
                .orElseThrow(() -> new ResourceNotFoundException("Usuario", usuarioId));

        // Busca licenciamentos como RT ou RU, retornando o de RT como prioritario
        Page<Licenciamento> pagina = licenciamentoRepository.findByResponsavelTecnico(usuario, pageable);
        if (pagina.isEmpty()) {
            pagina = licenciamentoRepository.findByResponsavelUso(usuario, pageable);
        }
        return pagina.map(this::toDTO);
    }

    @Transactional
    public LicenciamentoDTO create(LicenciamentoCreateDTO dto) {
        // Persiste endereco novo
        Endereco endereco = enderecoRepository.save(fromEnderecoDTO(dto.endereco()));

        Licenciamento.LicenciamentoBuilder builder = Licenciamento.builder()
                .tipo(dto.tipo())
                .status(StatusLicenciamento.RASCUNHO)
                .areaConstruida(dto.areaConstruida())
                .alturaMaxima(dto.alturaMaxima())
                .numPavimentos(dto.numPavimentos())
                .tipoOcupacao(dto.tipoOcupacao())
                .usoPredominante(dto.usoPredominante())
                .endereco(endereco)
                .ativo(true)
                .isentoTaxa(false);

        if (dto.responsavelTecnicoId() != null) {
            Usuario rt = usuarioRepository.findById(dto.responsavelTecnicoId())
                    .orElseThrow(() -> new ResourceNotFoundException("Responsavel Tecnico", dto.responsavelTecnicoId()));
            builder.responsavelTecnico(rt);
        }

        if (dto.responsavelUsoId() != null) {
            Usuario ru = usuarioRepository.findById(dto.responsavelUsoId())
                    .orElseThrow(() -> new ResourceNotFoundException("Responsavel pelo Uso", dto.responsavelUsoId()));
            builder.responsavelUso(ru);
        }

        if (dto.licenciamentoPaiId() != null) {
            Licenciamento pai = licenciamentoRepository.findById(dto.licenciamentoPaiId())
                    .orElseThrow(() -> new ResourceNotFoundException("Licenciamento pai", dto.licenciamentoPaiId()));
            builder.licenciamentoPai(pai);
        }

        return toDTO(licenciamentoRepository.save(builder.build()));
    }

    @Transactional
    public LicenciamentoDTO updateStatus(Long id, StatusLicenciamento novoStatus) {
        Licenciamento licenciamento = licenciamentoRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Licenciamento", id));

        validarTransicaoStatus(licenciamento.getStatus(), novoStatus);
        licenciamento.setStatus(novoStatus);
        return toDTO(licenciamentoRepository.save(licenciamento));
    }

    /**
     * Submete o licenciamento para analise (P03 - ultimo passo do wizard).
     *
     * RN-P03-001: somente licenciamentos em RASCUNHO podem ser submetidos.
     * RN-P03-002: obrigatorio ter pelo menos um arquivo do tipo PPCI anexado.
     *
     * Transicao: RASCUNHO -> ANALISE_PENDENTE
     * Marco registrado: TipoMarco.SUBMISSAO
     *
     * @param id         ID do licenciamento
     * @param keycloakId sub do JWT do usuario que esta submetendo
     */
    @Transactional
    public LicenciamentoDTO submeter(Long id, String keycloakId) {
        Licenciamento licenciamento = licenciamentoRepository.findById(id)
            .orElseThrow(() -> new ResourceNotFoundException("Licenciamento", id));

        // RN-P03-001: apenas RASCUNHO pode ser submetido
        if (licenciamento.getStatus() != StatusLicenciamento.RASCUNHO) {
            throw new BusinessException("RN-P03-001",
                "Somente licenciamentos em RASCUNHO podem ser submetidos. "
                + "Status atual: " + licenciamento.getStatus());
        }

        // RN-P03-002: exige pelo menos um PPCI anexado
        int qtdPpci = arquivoEDRepository
            .findByLicenciamentoIdAndTipoArquivo(id, TipoArquivo.PPCI).size();
        if (qtdPpci == 0) {
            throw new BusinessException("RN-P03-002",
                "E obrigatorio anexar pelo menos um arquivo do tipo PPCI antes de submeter o licenciamento");
        }

        // Transicao de status
        licenciamento.setStatus(StatusLicenciamento.ANALISE_PENDENTE);
        licenciamentoRepository.save(licenciamento);

        // Registra marco de submissao
        Usuario usuario = usuarioRepository.findByKeycloakId(keycloakId).orElse(null);
        MarcoProcesso marco = MarcoProcesso.builder()
            .tipoMarco(TipoMarco.SUBMISSAO)
            .licenciamento(licenciamento)
            .usuario(usuario)
            .observacao("Licenciamento submetido para analise via P03. Arquivos PPCI: " + qtdPpci)
            .build();
        marcoProcessoRepository.save(marco);

        return toDTO(licenciamento);
    }

    @Transactional
    public void delete(Long id) {
        Licenciamento licenciamento = licenciamentoRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Licenciamento", id));

        if (licenciamento.getStatus() != StatusLicenciamento.RASCUNHO) {
            throw new BusinessException("RN-012",
                    "Apenas licenciamentos em RASCUNHO podem ser excluidos. Status atual: "
                    + licenciamento.getStatus());
        }
        licenciamento.setAtivo(false);
        licenciamentoRepository.save(licenciamento);
    }

    // ---------------------------------------------------------------------------
    // Validacao de maquina de estados
    // ---------------------------------------------------------------------------

    private void validarTransicaoStatus(StatusLicenciamento atual, StatusLicenciamento novo) {
        boolean transicaoValida = switch (atual) {
            case RASCUNHO            -> novo == StatusLicenciamento.ANALISE_PENDENTE;
            case ANALISE_PENDENTE    -> novo == StatusLicenciamento.EM_ANALISE
                                        || novo == StatusLicenciamento.EXTINTO;
            case EM_ANALISE          -> novo == StatusLicenciamento.CIA_EMITIDO
                                        || novo == StatusLicenciamento.DEFERIDO
                                        || novo == StatusLicenciamento.INDEFERIDO;
            case CIA_EMITIDO         -> novo == StatusLicenciamento.CIA_CIENCIA
                                        || novo == StatusLicenciamento.SUSPENSO;
            case CIA_CIENCIA         -> novo == StatusLicenciamento.EM_ANALISE
                                        || novo == StatusLicenciamento.RECURSO_PENDENTE;
            case DEFERIDO            -> novo == StatusLicenciamento.VISTORIA_PENDENTE
                                        || novo == StatusLicenciamento.PRPCI_EMITIDO;
            case VISTORIA_PENDENTE   -> novo == StatusLicenciamento.EM_VISTORIA;
            case EM_VISTORIA         -> novo == StatusLicenciamento.CIV_EMITIDO
                                        || novo == StatusLicenciamento.PRPCI_EMITIDO;
            case CIV_EMITIDO         -> novo == StatusLicenciamento.CIV_CIENCIA
                                        || novo == StatusLicenciamento.SUSPENSO;
            case CIV_CIENCIA         -> novo == StatusLicenciamento.EM_VISTORIA
                                        || novo == StatusLicenciamento.RECURSO_PENDENTE;
            case PRPCI_EMITIDO       -> novo == StatusLicenciamento.APPCI_EMITIDO;
            case APPCI_EMITIDO       -> novo == StatusLicenciamento.SUSPENSO
                                        || novo == StatusLicenciamento.RENOVADO
                                        || novo == StatusLicenciamento.EXTINTO;
            case RECURSO_PENDENTE    -> novo == StatusLicenciamento.EM_RECURSO;
            case EM_RECURSO          -> novo == StatusLicenciamento.DEFERIDO
                                        || novo == StatusLicenciamento.INDEFERIDO;
            case SUSPENSO            -> novo == StatusLicenciamento.EXTINTO;
            case EXTINTO, INDEFERIDO, RENOVADO -> false;
            // P14: transicoes gerenciadas exclusivamente pelo RenovacaoService
            case ALVARA_VENCIDO,
                 AGUARDANDO_ACEITE_RENOVACAO,
                 AGUARDANDO_PAGAMENTO_RENOVACAO,
                 AGUARDANDO_DISTRIBUICAO_RENOV,
                 EM_VISTORIA_RENOVACAO -> false;
        };

        if (!transicaoValida) {
            throw new BusinessException("RN-STATUS",
                    "Transicao de status invalida: " + atual + " -> " + novo);
        }
    }

    // ---------------------------------------------------------------------------
    // Mapeamento manual Entity -> DTO
    // ---------------------------------------------------------------------------

    public LicenciamentoDTO toDTO(Licenciamento l) {
        EnderecoDTO enderecoDTO = null;
        if (l.getEndereco() != null) {
            Endereco e = l.getEndereco();
            enderecoDTO = new EnderecoDTO(
                    e.getCep(), e.getLogradouro(), e.getNumero(), e.getComplemento(),
                    e.getBairro(), e.getMunicipio(), e.getUf(),
                    e.getLatitude(), e.getLongitude(), e.getDataAtualizacao()
            );
        }

        return new LicenciamentoDTO(
                l.getId(),
                l.getNumeroPpci(),
                l.getTipo(),
                l.getStatus(),
                l.getAreaConstruida(),
                l.getAlturaMaxima(),
                l.getNumPavimentos(),
                l.getNumLote(),
                l.getNumVersao(),
                l.getTipoOcupacao(),
                l.getUsoPredominante(),
                l.getDtValidadeAppci(),
                l.getDtVencimentoPrpci(),
                enderecoDTO,
                l.getResponsavelTecnico() != null ? l.getResponsavelTecnico().getId() : null,
                l.getResponsavelTecnico() != null ? l.getResponsavelTecnico().getNome() : null,
                l.getResponsavelUso() != null ? l.getResponsavelUso().getId() : null,
                l.getResponsavelUso() != null ? l.getResponsavelUso().getNome() : null,
                l.getAnalista() != null ? l.getAnalista().getId() : null,
                l.getAnalista() != null ? l.getAnalista().getNome() : null,
                l.getInspetor() != null ? l.getInspetor().getId() : null,
                l.getInspetor() != null ? l.getInspetor().getNome() : null,
                l.getLicenciamentoPai() != null ? l.getLicenciamentoPai().getId() : null,
                l.getAtivo(),
                l.getIsentoTaxa(),
                l.getObsIsencao(),
                l.getDataCriacao(),
                l.getDataAtualizacao()
        );
    }

    private Endereco fromEnderecoDTO(EnderecoDTO dto) {
        return Endereco.builder()
                .cep(dto.cep())
                .logradouro(dto.logradouro())
                .numero(dto.numero())
                .complemento(dto.complemento())
                .bairro(dto.bairro())
                .municipio(dto.municipio())
                .uf(dto.uf())
                .latitude(dto.latitude())
                .longitude(dto.longitude())
                .build();
    }
}
