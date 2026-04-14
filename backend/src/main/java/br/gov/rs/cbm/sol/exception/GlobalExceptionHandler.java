package br.gov.rs.cbm.sol.exception;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.net.URI;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Tratamento centralizado de excecoes seguindo RFC 7807 (ProblemDetail — Spring 6).
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);
    private static final String PROBLEM_BASE_URI = "https://sol.cbm.rs.gov.br/erros/";

    @ExceptionHandler(ResourceNotFoundException.class)
    public ProblemDetail handleResourceNotFound(ResourceNotFoundException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
        problem.setTitle("Recurso nao encontrado");
        problem.setType(URI.create(PROBLEM_BASE_URI + "recurso-nao-encontrado"));
        return problem;
    }

    @ExceptionHandler(BusinessException.class)
    public ProblemDetail handleBusinessException(BusinessException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.UNPROCESSABLE_ENTITY, ex.getMessage());
        problem.setTitle("Violacao de regra de negocio");
        problem.setType(URI.create(PROBLEM_BASE_URI + "regra-negocio"));
        if (ex.getCodigoRegra() != null) {
            problem.setProperty("codigoRegra", ex.getCodigoRegra());
        }
        return problem;
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ProblemDetail handleValidation(MethodArgumentNotValidException ex) {
        Map<String, String> erros = new LinkedHashMap<>();
        for (FieldError fieldError : ex.getBindingResult().getFieldErrors()) {
            erros.put(fieldError.getField(), fieldError.getDefaultMessage());
        }

        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.BAD_REQUEST, "Um ou mais campos falharam na validacao");
        problem.setTitle("Dados invalidos");
        problem.setType(URI.create(PROBLEM_BASE_URI + "dados-invalidos"));
        problem.setProperty("erros", erros);
        return problem;
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ProblemDetail handleAccessDenied(AccessDeniedException ex) {
        log.warn("Acesso negado: {}", ex.getMessage());
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.FORBIDDEN, "Voce nao tem permissao para realizar esta operacao");
        problem.setTitle("Acesso negado");
        problem.setType(URI.create(PROBLEM_BASE_URI + "acesso-negado"));
        return problem;
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ProblemDetail handleMessageNotReadable(HttpMessageNotReadableException ex) {
        log.warn("Corpo da requisicao invalido: {}", ex.getMessage());
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.BAD_REQUEST, "Corpo da requisicao invalido ou ausente");
        problem.setTitle("Requisicao invalida");
        problem.setType(URI.create(PROBLEM_BASE_URI + "requisicao-invalida"));
        return problem;
    }

    @ExceptionHandler(Exception.class)
    public ProblemDetail handleGeneric(Exception ex) {
        log.error("Erro interno nao tratado: {} -- {}", ex.getClass().getName(), ex.getMessage(), ex);
        String detalhe = ex.getClass().getName() + ": " + ex.getMessage();
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
                HttpStatus.INTERNAL_SERVER_ERROR, detalhe);
        problem.setTitle("Erro interno");
        problem.setType(URI.create(PROBLEM_BASE_URI + "erro-interno"));
        problem.setProperty("causa", ex.getClass().getSimpleName());
        return problem;
    }
}
