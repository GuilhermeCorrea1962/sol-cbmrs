package br.gov.rs.cbm.sol.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.Map;

/**
 * Endpoint de health check — verificado pelo script 08-verify-all.ps1
 * e pelo monitoramento de disponibilidade.
 *
 * GET /api/health → {"status":"UP","timestamp":"...","version":"1.0.0"}
 */
@RestController
@RequestMapping("/health")
public class HealthController {

    @GetMapping
    public ResponseEntity<Map<String, Object>> health() {
        return ResponseEntity.ok(Map.of(
            "status", "UP",
            "timestamp", LocalDateTime.now().toString(),
            "version", "1.0.0",
            "system", "SOL CBM-RS Autônomo"
        ));
    }
}
