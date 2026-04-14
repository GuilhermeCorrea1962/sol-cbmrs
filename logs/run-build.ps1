$out = "C:\SOL\logs\build-output.txt"
Set-Location "C:\SOL\frontend"
$result = & npm run build:prod 2>&1
$result | Out-File $out -Encoding UTF8
$LASTEXITCODE | Out-File "C:\SOL\logs\build-exitcode.txt" -Encoding UTF8
