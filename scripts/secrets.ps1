# Creates/updates Kubernetes Secrets from the .env file in the platform folder.
# First run: copies .env.example to .env and replaces every "change-me" with a random password.
# Safe to run again any time (kubectl apply = create or update).
#
# Usage:  powershell -ExecutionPolicy Bypass -File scripts\secrets.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$envFile = Join-Path $root '.env'

function New-Password {
    $chars = [char[]]'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    -join (1..20 | ForEach-Object { $chars | Get-Random })
}

if (-not (Test-Path $envFile)) {
    Write-Host "No .env found - creating one with random passwords"
    $lines = Get-Content (Join-Path $root '.env.example') | ForEach-Object {
        if ($_ -match '=change-me$') { $_ -replace 'change-me$', (New-Password) } else { $_ }
    }
    [IO.File]::WriteAllLines($envFile, [string[]]$lines)
}

# Keys added to .env.example later (e.g. a new app) are appended to .env with random values.
$existing = Get-Content $envFile | Where-Object { $_ -match '^\s*[A-Z0-9_]+=' } | ForEach-Object { ($_ -split '=', 2)[0].Trim() }
$missing = Get-Content (Join-Path $root '.env.example') | Where-Object { $_ -match '^\s*[A-Z0-9_]+=' } | Where-Object { ($_ -split '=', 2)[0].Trim() -notin $existing }
if ($missing) {
    $added = $missing | ForEach-Object { if ($_ -match '=change-me$') { $_ -replace 'change-me$', (New-Password) } else { $_ } }
    Add-Content -Path $envFile -Value $added
    Write-Host "Added new keys to .env: $(($added | ForEach-Object { ($_ -split '=', 2)[0] }) -join ', ')"
}

# Read KEY=VALUE pairs (ignore comments and blank lines)
$cfg = @{}
Get-Content $envFile | Where-Object { $_ -match '^\s*[A-Z0-9_]+=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2
    $cfg[$k.Trim()] = $v.Trim()
}

function Set-Secret([string]$Namespace, [string]$Name, [hashtable]$Data, [string]$Type = 'Opaque') {
    # @() keeps this an array even with one entry (splatting a lone string would split it into characters)
    $literals = @($Data.GetEnumerator() | ForEach-Object { "--from-literal=$($_.Key)=$($_.Value)" })
    kubectl create secret generic $Name -n $Namespace --type $Type @literals --dry-run=client -o yaml | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { throw "Failed to apply secret $Namespace/$Name" }
}

# data namespace - the databases
Set-Secret data pg-app @{ username = $cfg.POSTGRES_USER; password = $cfg.POSTGRES_PASSWORD } 'kubernetes.io/basic-auth'
Set-Secret data mongo-root @{ username = $cfg.MONGO_ROOT_USER; password = $cfg.MONGO_ROOT_PASSWORD }
Set-Secret data redis-auth @{ password = $cfg.REDIS_PASSWORD }
Set-Secret data rustfs @{ 'access-key' = $cfg.S3_ACCESS_KEY; 'secret-key' = $cfg.S3_SECRET_KEY }

# One block per app: its database login (data) + everything the app reads as env vars (apps)

# hermes-audiobooks-api
Set-Secret data hermes-db @{ username = 'hermes'; password = $cfg.HERMES_DB_PASSWORD } 'kubernetes.io/basic-auth'
Set-Secret apps hermes-audiobooks-api @{
    SPRING_DATASOURCE_URL      = 'jdbc:postgresql://pg-rw.data.svc:5432/hermes'
    SPRING_DATASOURCE_USERNAME = 'hermes'
    SPRING_DATASOURCE_PASSWORD = $cfg.HERMES_DB_PASSWORD
    S3_ENDPOINT                = 'http://rustfs.data.svc:9000'
    S3_BUCKET                  = 'hermes-audio'
    S3_ACCESS_KEY              = $cfg.S3_ACCESS_KEY
    S3_SECRET_KEY              = $cfg.S3_SECRET_KEY
}

# tools namespace - the admin UIs
Set-Secret tools pgadmin @{ email = $cfg.PGADMIN_EMAIL; password = $cfg.PGADMIN_PASSWORD }
Set-Secret tools mongo-express @{
    username = $cfg.MONGO_EXPRESS_USER
    password = $cfg.MONGO_EXPRESS_PASSWORD
    url      = "mongodb://$($cfg.MONGO_ROOT_USER):$($cfg.MONGO_ROOT_PASSWORD)@mongo.data.svc:27017/?authSource=admin"
}
Set-Secret tools redisinsight @{ 'redis-password' = $cfg.REDIS_PASSWORD }

Write-Host "Secrets applied. Your passwords are in $envFile"
