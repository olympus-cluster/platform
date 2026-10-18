# Builds (or repairs) the whole olympus platform. Safe to run again: every step skips
# or updates what already exists.
#
# Usage:  powershell -ExecutionPolicy Bypass -File scripts\up.ps1
#
# Order: registry -> kind cluster -> registry wiring -> Traefik -> CloudNativePG operator
#        -> metrics-server -> namespaces + secrets -> databases -> Headlamp + admin UIs

$ErrorActionPreference = 'Continue'   # native tools write progress to stderr; we check exit codes instead
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$Cluster      = 'olympus'
$RegistryName = 'kind-registry'
$RegistryPort = 5001

# Pinned versions - bump deliberately, one at a time.
$TraefikChart       = '42.0.0'
$CnpgChart          = '0.29.1'
$MetricsServerChart = '3.14.0'
$HeadlampChart      = '0.46.0'
$RegistryImage      = 'registry:3.1'

function Step([string]$Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }

# Runs a native command and stops the script if it fails.
function Exec {
    $exe = $args[0]
    $rest = @($args | Select-Object -Skip 1)
    & $exe @rest
    if ($LASTEXITCODE -ne 0) { Write-Host "FAILED: $($args -join ' ')" -ForegroundColor Red; exit 1 }
}

docker info --format '{{.ServerVersion}}' *> $null
if ($LASTEXITCODE -ne 0) { Write-Host 'Docker is not running - start Docker Desktop first.' -ForegroundColor Red; exit 1 }

Step "Local image registry ($RegistryName on localhost:$RegistryPort)"
$state = docker ps -a --filter "name=^$RegistryName$" --format '{{.State}}'
if (-not $state) {
    Exec docker run -d --restart=always -p "127.0.0.1:${RegistryPort}:5000" --network bridge --name $RegistryName $RegistryImage
} elseif ($state -ne 'running') {
    Exec docker start $RegistryName
} else { Write-Host 'already running' }

Step "kind cluster '$Cluster'"
if ((kind get clusters 2>$null) -contains $Cluster) {
    Write-Host 'already exists'
} else {
    Exec kind create cluster --config cluster/kind-config.yaml --wait 180s
}
Exec kubectl config use-context "kind-$Cluster"

Step 'Wire the registry into the cluster'
$certsDir = "/etc/containerd/certs.d/localhost:$RegistryPort"
foreach ($node in (kind get nodes --name $Cluster)) {
    Exec docker exec $node mkdir -p $certsDir
    Exec docker cp cluster/registry-hosts.toml "${node}:$certsDir/hosts.toml"
}
$onKindNet = docker network inspect kind --format '{{range .Containers}}{{.Name}} {{end}}'
if (($onKindNet -split ' ') -notcontains $RegistryName) { Exec docker network connect kind $RegistryName }
Exec kubectl apply -f cluster/registry-hosting.yaml

Step 'Helm repositories'
Exec helm repo add traefik https://traefik.github.io/charts --force-update
Exec helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update
Exec helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
Exec helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/ --force-update
Exec helm repo update

Step 'Traefik ingress controller'
Exec helm upgrade --install traefik traefik/traefik --version $TraefikChart -n traefik --create-namespace -f infra/traefik-values.yaml --wait --timeout 5m

Step 'CloudNativePG operator (manages PostgreSQL)'
Exec helm upgrade --install cnpg cnpg/cloudnative-pg --version $CnpgChart -n cnpg-system --create-namespace --wait --timeout 5m

Step 'metrics-server (kubectl top)'
Exec helm upgrade --install metrics-server metrics-server/metrics-server --version $MetricsServerChart -n kube-system -f infra/metrics-server-values.yaml --wait --timeout 5m

Step 'Namespaces and secrets'
Exec kubectl apply -f cluster/namespaces.yaml
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'secrets.ps1')
if ($LASTEXITCODE -ne 0) { exit 1 }

Step 'Databases: PostgreSQL, MongoDB, Redis'
# The CNPG webhook can need a few seconds after install, so retry.
for ($i = 1; $i -le 10; $i++) {
    kubectl apply -k data
    if ($LASTEXITCODE -eq 0) { break }
    Write-Host "retrying in 6s ($i/10)..."; Start-Sleep 6
}
if ($LASTEXITCODE -ne 0) { Write-Host 'FAILED: kubectl apply -k data' -ForegroundColor Red; exit 1 }
Exec kubectl -n data rollout status statefulset/mongo --timeout 5m
Exec kubectl -n data rollout status statefulset/redis --timeout 5m
Write-Host 'waiting for PostgreSQL cluster pg to be ready (first time pulls the image, ~1-2 min)...'
Exec kubectl -n data wait --for=condition=Ready cluster/pg --timeout 8m

Step 'Admin UIs: Headlamp, pgAdmin, mongo-express, RedisInsight'
Exec helm upgrade --install headlamp headlamp/headlamp --version $HeadlampChart -n tools -f infra/headlamp-values.yaml --wait --timeout 5m
Exec kubectl apply -k tools
foreach ($d in 'pgadmin', 'mongo-express', 'redisinsight') {
    Exec kubectl -n tools rollout status "deployment/$d" --timeout 5m
}

Write-Host "`nOlympus is up." -ForegroundColor Green
Write-Host @"
  Traefik     http://traefik.localtest.me/dashboard/
  Headlamp    http://headlamp.localtest.me   (token: kubectl create token headlamp -n tools --duration 24h)
  pgAdmin     http://pgadmin.localtest.me
  Mongo UI    http://mongo.localtest.me
  Redis UI    http://redis.localtest.me
  Registry    localhost:$RegistryPort
  Passwords   $root\.env
Run scripts\verify.ps1 to check everything.
"@
