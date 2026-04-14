package br.gov.rs.cbm.sol.repository;

import br.gov.rs.cbm.sol.entity.Boleto;
import br.gov.rs.cbm.sol.entity.enums.StatusBoleto;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

@Repository
public interface BoletoRepository extends JpaRepository<Boleto, Long> {

    List<Boleto> findByLicenciamentoId(Long licenciamentoId);

    List<Boleto> findByLicenciamentoIdAndStatus(Long licenciamentoId, StatusBoleto status);

    Optional<Boleto> findByNossoNumero(String nossoNumero);

    // Para o job de vencimento de boletos (P11-B)
    @Query("SELECT b FROM Boleto b WHERE b.status = 'PENDENTE' AND b.dtVencimento < :hoje")
    List<Boleto> findBoletosVencidos(@Param("hoje") LocalDate hoje);

    // Boleto ativo (PENDENTE) de um licenciamento
    Optional<Boleto> findFirstByLicenciamentoIdAndStatusOrderByDtCriacaoDesc(Long licenciamentoId, StatusBoleto status);

    boolean existsByLicenciamentoIdAndStatus(Long licenciamentoId, StatusBoleto status);
}
