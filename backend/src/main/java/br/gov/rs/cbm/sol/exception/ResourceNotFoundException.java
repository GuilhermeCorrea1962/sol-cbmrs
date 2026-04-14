package br.gov.rs.cbm.sol.exception;

/**
 * Lancada quando um recurso solicitado nao e encontrado no banco de dados.
 * Mapeada para HTTP 404 pelo GlobalExceptionHandler.
 */
public class ResourceNotFoundException extends RuntimeException {

    public ResourceNotFoundException(String message) {
        super(message);
    }

    public ResourceNotFoundException(String resourceName, Long id) {
        super(resourceName + " nao encontrado com id: " + id);
    }

    public ResourceNotFoundException(String resourceName, String fieldName, Object fieldValue) {
        super(resourceName + " nao encontrado com " + fieldName + ": " + fieldValue);
    }
}
