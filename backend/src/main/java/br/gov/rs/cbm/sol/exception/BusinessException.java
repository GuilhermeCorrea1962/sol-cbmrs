package br.gov.rs.cbm.sol.exception;

/**
 * Lancada quando uma regra de negocio e violada.
 * Mapeada para HTTP 422 (Unprocessable Entity) pelo GlobalExceptionHandler.
 */
public class BusinessException extends RuntimeException {

    private final String codigoRegra;

    public BusinessException(String message) {
        super(message);
        this.codigoRegra = null;
    }

    /**
     * @param codigoRegra codigo da regra de negocio violada (ex: "RN-042")
     * @param message     descricao legivel da violacao
     */
    public BusinessException(String codigoRegra, String message) {
        super(message);
        this.codigoRegra = codigoRegra;
    }

    public String getCodigoRegra() {
        return codigoRegra;
    }
}
