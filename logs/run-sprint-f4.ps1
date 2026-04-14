# run-sprint-f4.ps1
# Launcher para a Sprint F4 -Analise Tecnica (P04)
# Executa o script principal e captura todo o output em arquivo de log.
#
# Saidas:
#   C:\SOL\logs\sprint-f4-run-output.txt   -log completo da execucao
#   C:\SOL\logs\sprint-f4-run-exitcode.txt -exit code (0 = sucesso)

$out = "C:\SOL\logs\sprint-f4-run-output.txt"
& "C:\SOL\infra\scripts\sprint-f4-deploy.ps1" *>&1 | Tee-Object -FilePath $out
$LASTEXITCODE | Out-File "C:\SOL\logs\sprint-f4-run-exitcode.txt" -Encoding UTF8
