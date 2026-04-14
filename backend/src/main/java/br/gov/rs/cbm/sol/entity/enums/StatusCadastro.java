package br.gov.rs.cbm.sol.entity.enums;

public enum StatusCadastro {
    INCOMPLETO(0),
    ANALISE_PENDENTE(1),
    EM_ANALISE(2),
    APROVADO(3),
    REPROVADO(4);

    private final int codigo;

    StatusCadastro(int codigo) {
        this.codigo = codigo;
    }

    public int getCodigo() {
        return codigo;
    }

    public static StatusCadastro fromCodigo(int codigo) {
        for (StatusCadastro s : values()) {
            if (s.codigo == codigo) return s;
        }
        throw new IllegalArgumentException("StatusCadastro desconhecido: " + codigo);
    }
}
