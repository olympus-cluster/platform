# Deletes the olympus kind cluster (all Pods, databases and their data).
# The local registry container is kept so images survive; add -Purge to remove it too.
# Your .env (passwords) is kept, so the next up.ps1 reuses the same passwords.
#
# Usage:  powershell -ExecutionPolicy Bypass -File scripts\down.ps1 [-Purge]

param([switch]$Purge)

$ErrorActionPreference = 'Continue'
$Cluster = 'olympus'
$RegistryName = 'kind-registry'

if ((kind get clusters 2>$null) -contains $Cluster) {
    kind delete cluster --name $Cluster
} else {
    Write-Host "Cluster '$Cluster' does not exist."
}

if ($Purge) {
    if (docker ps -a --filter "name=^$RegistryName$" --format '{{.Names}}') {
        docker rm -f $RegistryName | Out-Null
        Write-Host "Removed registry container $RegistryName."
    }
}
