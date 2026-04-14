package br.gov.rs.cbm.sol.repository;

import br.gov.rs.cbm.sol.entity.RotinaExecucao;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

/**
 * Repositorio da entidade RotinaExecucao.
 *
 * Usado pelo AlvaraVencimentoService (P13) para:
 *   - Registrar o inicio/fim de cada execucao da rotina diaria de alvaras.
 *   - Consultar a data de ultima execucao concluida (baseline temporal para
 *     calcular as janelas de notificacao de vencimento — RN-140).
 */
@Repository
public interface RotinaExecucaoRepository extends JpaRepository<RotinaExecucao, Long> {

    /**
     * Retorna a ultima rotina concluida de um determinado tipo,
     * ordenada pela data de fim de execucao decrescente.
     *
     * Usada como baseline temporal (RN-140): se nao houver nenhuma rotina
     * concluida, o AlvaraVencimentoService usa ontem como fallback.
     *
     * @param tipoRotina nome da rotina (ex.: "GERAR_NOTIFICACAO_ALVARA_VENCIDO")
     * @param situacao   situacao desejada (ex.: "CONCLUIDA")
     * @return Optional com a ultima rotina concluida, ou empty se nenhuma existir
     */
    Optional<RotinaExecucao> findTopByTipoRotinaAndSituacaoOrderByDataFimExecucaoDesc(
            String tipoRotina, String situacao);
}
