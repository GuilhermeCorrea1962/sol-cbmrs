package br.gov.rs.cbm.sol.repository;

import br.gov.rs.cbm.sol.entity.Licenciamento;
import br.gov.rs.cbm.sol.entity.Usuario;
import br.gov.rs.cbm.sol.entity.enums.StatusLicenciamento;
import br.gov.rs.cbm.sol.entity.enums.TipoLicenciamento;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface LicenciamentoRepository extends JpaRepository<Licenciamento, Long> {

    Optional<Licenciamento> findByNumeroPpci(String numeroPpci);

    Page<Licenciamento> findByResponsavelTecnico(Usuario rt, Pageable pageable);

    Page<Licenciamento> findByResponsavelUso(Usuario ru, Pageable pageable);

    Page<Licenciamento> findByStatus(StatusLicenciamento status, Pageable pageable);

    Page<Licenciamento> findByAnalista(Usuario analista, Pageable pageable);

    Page<Licenciamento> findByInspetor(Usuario inspetor, Pageable pageable);

    List<Licenciamento> findByStatusIn(List<StatusLicenciamento> statuses);

    List<Licenciamento> findByAtivoTrue();

    // Para distribuicao FIFO: pega o mais antigo com status ANALISE_PENDENTE
    @Query("SELECT l FROM Licenciamento l WHERE l.status = 'ANALISE_PENDENTE' AND l.analista IS NULL ORDER BY l.dataCriacao ASC")
    List<Licenciamento> findParaDistribuicaoFIFO(Pageable pageable);

    // Licenciamentos com APPCI proximos do vencimento (para job de suspensao)
    @Query("SELECT l FROM Licenciamento l WHERE l.status = 'APPCI_EMITIDO' AND l.dtValidadeAppci <= :dataLimite AND l.ativo = true")
    List<Licenciamento> findAppciVencidos(@Param("dataLimite") java.time.LocalDate dataLimite);

    // P13-A: IDs de licenciamentos APPCI_EMITIDO com alvara vencido (dtValidadeAppci <= hoje)
    @Query("SELECT l.id FROM Licenciamento l WHERE l.status = 'APPCI_EMITIDO' AND l.dtValidadeAppci <= :hoje AND l.ativo = true")
    List<Long> findAppciVencidosIds(@Param("hoje") java.time.LocalDate hoje);

    // P13-B: IDs de licenciamentos APPCI_EMITIDO com alvara a vencer na data exata (para notificacoes 90/59/29 dias)
    @Query("SELECT l.id FROM Licenciamento l WHERE l.status = 'APPCI_EMITIDO' AND l.dtValidadeAppci = :dataAlvo AND l.ativo = true")
    List<Long> findAppciAVencerIds(@Param("dataAlvo") java.time.LocalDate dataAlvo);

    // P13-C: IDs de licenciamentos ALVARA_VENCIDO com dtValidadeAppci no intervalo (para notificacao pos-vencimento)
    @Query("SELECT l.id FROM Licenciamento l WHERE l.status = 'ALVARA_VENCIDO' AND l.dtValidadeAppci >= :dataInicio AND l.dtValidadeAppci < :dataFim AND l.ativo = true")
    List<Long> findAlvaresVencidosParaNotificacaoIds(@Param("dataInicio") java.time.LocalDate dataInicio, @Param("dataFim") java.time.LocalDate dataFim);

    // Licenciamentos suspensos por CIA ha mais de 6 meses (para job de cancelamento)
    @Query("SELECT l FROM Licenciamento l WHERE l.status = 'SUSPENSO' AND l.dataAtualizacao <= :dataLimite AND l.ativo = true")
    List<Licenciamento> findSuspensosSemMovimento(@Param("dataLimite") LocalDateTime dataLimite);

    @Query("SELECT COUNT(l) FROM Licenciamento l WHERE l.status = :status")
    long countByStatus(@Param("status") StatusLicenciamento status);

    boolean existsByNumeroPpci(String numeroPpci);

    // P14: Licenciamentos elegiveis para inicio de renovacao pelo RT/RU autenticado
    @Query("SELECT l FROM Licenciamento l WHERE l.status IN ('APPCI_EMITIDO','ALVARA_VENCIDO') " +
           "AND (l.responsavelTecnico.id = :userId OR l.responsavelUso.id = :userId) " +
           "AND l.ativo = true ORDER BY l.dataCriacao DESC")
    List<Licenciamento> findElegiveisParaRenovacao(@Param("userId") Long userId);

    // P14: Licenciamentos de renovacao em andamento do usuario (todas as fases ativas)
    @Query("SELECT l FROM Licenciamento l WHERE l.status IN (" +
           "'AGUARDANDO_ACEITE_RENOVACAO','AGUARDANDO_PAGAMENTO_RENOVACAO'," +
           "'AGUARDANDO_DISTRIBUICAO_RENOV','EM_VISTORIA_RENOVACAO','CIV_EMITIDO') " +
           "AND (l.responsavelTecnico.id = :userId OR l.responsavelUso.id = :userId) " +
           "AND l.ativo = true ORDER BY l.dataAtualizacao DESC")
    List<Licenciamento> findRenovacoesEmAndamento(@Param("userId") Long userId);
}
