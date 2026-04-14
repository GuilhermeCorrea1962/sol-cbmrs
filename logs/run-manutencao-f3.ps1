# run-manutencao-f3.ps1
# Launcher para a Manutencao F3 - Correcao CSS budget licenciamento-novo
# Executa o script principal e captura todo o output em arquivo de log.
#
# Saidas:
#   C:\SOL\logs\manutencao-f3-run-output.txt   - log completo da execucao
#   C:\SOL\logs\manutencao-f3-run-exitcode.txt - exit code (0 = sucesso)

$out = "C:\SOL\logs\manutencao-f3-run-output.txt"
& "C:\SOL\infra\scripts\manutencao-f3-deploy.ps1" *>&1 | Tee-Object -FilePath $out
$LASTEXITCODE | Out-File "C:\SOL\logs\manutencao-f3-run-exitcode.txt" -Encoding UTF8
