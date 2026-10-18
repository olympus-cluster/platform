# Checks that every part of the olympus platform works. Prints PASS/FAIL per check.
#
# Usage:  powershell -ExecutionPolicy Bypass -File scripts\verify.ps1

$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
$script:failed = 0

function Check([string]$Name, [scriptblock]$Test) {
    $ok = $false
    try { $ok = [bool](& $Test) } catch { $ok = $false }
    if ($ok) { Write-Host "PASS  $Name" -ForegroundColor Green }
    else { Write-Host "FAIL  $Name" -ForegroundColor Red; $script:failed++ }
}

function HttpCode([string]$Url) { curl.exe -s -o NUL -w '%{http_code}' --max-time 10 $Url }

$cfg = @{}
Get-Content (Join-Path $root '.env') | Where-Object { $_ -match '^\s*[A-Z_]+=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2; $cfg[$k.Trim()] = $v.Trim()
}

Write-Host "`n-- Cluster"
Check '2 nodes Ready' { (kubectl get nodes --no-headers | Select-String ' Ready ').Count -eq 2 }
Check 'all Pods Running/Completed' {
    $bad = kubectl get pods -A --no-headers | Where-Object { $_ -notmatch '\s(Running|Completed)\s' }
    if ($bad) { $bad | ForEach-Object { Write-Host "      $_" } }
    -not $bad
}
Check 'metrics-server (kubectl top nodes)' { kubectl top nodes --no-headers 2>$null | Out-Null; $LASTEXITCODE -eq 0 }
Check 'local registry localhost:5001' { (HttpCode 'http://localhost:5001/v2/') -eq '200' }

Write-Host "`n-- Databases"
Check 'PostgreSQL cluster healthy' { (kubectl -n data get cluster pg -o jsonpath='{.status.phase}') -eq 'Cluster in healthy state' }
Check 'PostgreSQL query (select 1)' {
    (kubectl -n data exec pg-1 -c postgres -- psql -d app -tAc 'select 1') -eq '1'
}
Check 'MongoDB ping' {
    (kubectl -n data exec mongo-0 -- mongosh --quiet -u $cfg.MONGO_ROOT_USER -p $cfg.MONGO_ROOT_PASSWORD --authenticationDatabase admin --eval 'db.runCommand({ping:1}).ok') -eq '1'
}
Check 'Redis ping' {
    (kubectl -n data exec redis-0 -- redis-cli -a $cfg.REDIS_PASSWORD --no-auth-warning ping) -eq 'PONG'
}

Write-Host "`n-- Web UIs (through Traefik)"
Check 'hello.localtest.me (lesson 1, optional)' { (HttpCode 'http://hello.localtest.me') -in '200', '404' }
Check 'traefik.localtest.me/dashboard/' { (HttpCode 'http://traefik.localtest.me/dashboard/') -eq '200' }
Check 'headlamp.localtest.me' { (HttpCode 'http://headlamp.localtest.me') -eq '200' }
Check 'pgadmin.localtest.me' { (HttpCode 'http://pgadmin.localtest.me/misc/ping') -eq '200' }
Check 'mongo.localtest.me (asks for login)' { (HttpCode 'http://mongo.localtest.me') -eq '401' }
Check 'redis.localtest.me' { (HttpCode 'http://redis.localtest.me') -eq '200' }

if ($script:failed -eq 0) { Write-Host "`nAll checks passed." -ForegroundColor Green; exit 0 }
Write-Host "`n$($script:failed) check(s) failed. Try: kubectl get pods -A, then kubectl describe / logs on the failing Pod." -ForegroundColor Yellow
exit 1
