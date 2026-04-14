# Testar endpoints
Write-Host "=== Testando endpoints ==="

# MinIO
Write-Host "`n--- MinIO ---"
$urls = @(
    "http://localhost:9000/minio/health/live",
    "http://localhost:9000/health/live",
    "http://localhost:9000/"
)
foreach ($url in $urls) {
    try {
        $r = Invoke-WebRequest -Uri $url -TimeoutSec 5 -ErrorAction Stop
        Write-Host "OK [$($r.StatusCode)] $url"
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code) {
            Write-Host "HTTP $code $url"
        } else {
            Write-Host "ERRO $url - $($_.Exception.Message)"
        }
    }
}

# Nginx
Write-Host "`n--- Nginx ---"
try {
    $r = Invoke-WebRequest -Uri "http://localhost:80" -TimeoutSec 5 -MaximumRedirection 0 -ErrorAction Stop
    Write-Host "OK [$($r.StatusCode)] http://localhost:80"
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code) {
        Write-Host "HTTP $code http://localhost:80"
    } else {
        Write-Host "ERRO http://localhost:80 - $($_.Exception.Message)"
    }
}

# MinIO Console
Write-Host "`n--- MinIO Console ---"
try {
    $r = Invoke-WebRequest -Uri "http://localhost:9001" -TimeoutSec 5 -MaximumRedirection 0 -ErrorAction Stop
    Write-Host "OK [$($r.StatusCode)] http://localhost:9001"
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code) {
        Write-Host "HTTP $code http://localhost:9001"
    } else {
        Write-Host "ERRO http://localhost:9001 - $($_.Exception.Message)"
    }
}
