package br.gov.rs.cbm.sol.repository;

import br.gov.rs.cbm.sol.entity.MarcoProcesso;
import br.gov.rs.cbm.sol.entity.enums.TipoMarco;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface MarcoProcessoRepository extends JpaRepository<MarcoProcesso, Long> {

    List<MarcoProcesso> findByLicenciamentoIdOrderByDtMarcoAsc(Long licenciamentoId);

    List<MarcoProcesso> findByLicenciamentoIdOrderByDtMarcoDesc(Long licenciamentoId);

    List<MarcoProcesso> findByLicenciamentoIdAndTipoMarco(Long licenciamentoId, TipoMarco tipoMarco);

    Optional<MarcoProcesso> findFirstByLicenciamentoIdAndTipoMarcoOrderByDtMarcoDesc(Long licenciamentoId, TipoMarco tipoMarco);

    boolean existsByLicenciamentoIdAndTipoMarco(Long licenciamentoId, TipoMarco tipoMarco);

    @Query("SELECT m FROM MarcoProcesso m WHERE m.licenciamento.id = :licenciamentoId ORDER BY m.dtMarco DESC")
    List<MarcoProcesso> findHistoricoCompleto(@Param("licenciamentoId") Long licenciamentoId);
}
