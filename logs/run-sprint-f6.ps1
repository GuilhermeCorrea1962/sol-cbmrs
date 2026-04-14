# run-sprint-f6.ps1
# Launcher para a Sprint F6 - Emissao de APPCI (P08)
# Executa o script principal e captura todo o output em arquivo de log.
#
# Saidas:
#   C:\SOL\logs\sprint-f6-run-output.txt   - log completo da execucao
#   C:\SOL\logs\sprint-f6-run-exitcode.txt - exit code (0 = sucesso)

$out = "C:\SOL\logs\sprint-f6-run-output.txt"
& "C:\SOL\infra\scripts\sprint-f6-deploy.ps1" *>&1 | Tee-Object -FilePath $out
$LASTEXITCODE | Out-File "C:\SOL\logs\sprint-f6-run-exitcode.txt" -Encoding UTF8
