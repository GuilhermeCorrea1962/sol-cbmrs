package br.gov.rs.cbm.sol.repository;

import br.gov.rs.cbm.sol.entity.ArquivoED;
import br.gov.rs.cbm.sol.entity.Licenciamento;
import br.gov.rs.cbm.sol.entity.enums.TipoArquivo;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface ArquivoEDRepository extends JpaRepository<ArquivoED, Long> {

    List<ArquivoED> findByLicenciamento(Licenciamento licenciamento);

    List<ArquivoED> findByLicenciamentoAndTipoArquivo(Licenciamento licenciamento, TipoArquivo tipoArquivo);

    Optional<ArquivoED> findByIdentificadorAlfresco(String identificadorAlfresco);

    List<ArquivoED> findByLicenciamentoId(Long licenciamentoId);

    List<ArquivoED> findByLicenciamentoIdAndTipoArquivo(Long licenciamentoId, TipoArquivo tipoArquivo);

    Optional<ArquivoED> findFirstByLicenciamentoIdAndTipoArquivoOrderByDtUploadDesc(Long licenciamentoId, TipoArquivo tipoArquivo);

    void deleteByLicenciamentoId(Long licenciamentoId);
}
