package br.gov.rs.cbm.sol.repository;

import br.gov.rs.cbm.sol.entity.Endereco;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface EnderecoRepository extends JpaRepository<Endereco, Long> {

    List<Endereco> findByCep(String cep);

    List<Endereco> findByMunicipio(String municipio);

    List<Endereco> findByUf(String uf);
}
