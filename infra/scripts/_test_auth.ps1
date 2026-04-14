#Requires -Version 5.1
$ErrorActionPreference = 'Continue'

function Test-Login {
    param([string]$user, [string]$pass)
    try {
        $r = Invoke-RestMethod -Method Post 'http://localhost:8080/api/auth/login' `
            -ContentType 'application/json' `
            -Body "{`"username`":`"$user`",`"password`":`"$pass`"}"
        Write-Host "${user}: LOGIN OK (scope=$($r.scope))"
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            $s = [System.IO.StreamReader]::new($resp.GetResponseStream())
            Write-Host "$user : FALHA - $($s.ReadToEnd())"
        } else {
            Write-Host "$user : ERRO - $($_.Exception.Message)"
        }
    }
}

Test-Login "sol-admin"  "Admin@SOL2026"
Test-Login "analista1"  "Analista@123"
