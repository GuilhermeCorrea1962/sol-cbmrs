$out = "C:\SOL\logs\sprint-f1-run-output.txt"
& "C:\SOL\infra\scripts\sprint-f1-deploy.ps1" *>&1 | Tee-Object -FilePath $out
$LASTEXITCODE | Out-File "C:\SOL\logs\sprint-f1-run-exitcode.txt" -Encoding UTF8
