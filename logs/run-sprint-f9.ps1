# run-sprint-f9.ps1
# Launcher para a Sprint F9 - Relatorios (P-REL)
# Executa o script principal e captura todo o output em arquivo de log.
#
# Saidas:
#   C:\SOL\logs\sprint-f9-run-output.txt   - log completo da execucao
#   C:\SOL\logs\sprint-f9-run-exitcode.txt - exit code (0 = sucesso)

$out = "C:\SOL\logs\sprint-f9-run-output.txt"
& "C:\SOL\infra\scripts\sprint-f9-deploy.ps1" *>&1 | Tee-Object -FilePath $out
$LASTEXITCODE | Out-File "C:\SOL\logs\sprint-f9-run-exitcode.txt" -Encoding UTF8
