# olympus-cluster / platform

The local Kubernetes platform for the **olympus-cluster** learning lab: a disposable
[kind](https://kind.sigs.k8s.io/) cluster on Windows (WSL2 + Docker Desktop) that runs
databases, Spring Boot / FastAPI APIs and Angular SSR portals.

| Folder | What's inside |
|---|---|
| `cluster/` | `kind-config.yaml` — the cluster definition (1 control-plane + 1 worker, ports 80/443) |
| `infra/` | Helm values for shared components (Traefik ingress, …) |
| `learn/` | Step-by-step lessons — start with [`learn/01-hello`](learn/01-hello/README.md) |

## Quick start

```powershell
kind create cluster --config cluster/kind-config.yaml
helm repo add traefik https://traefik.github.io/charts
helm upgrade --install traefik traefik/traefik -n traefik --create-namespace -f infra/traefik-values.yaml
kubectl apply -f learn/01-hello/
# open http://hello.localtest.me
```

Coming next: a local image registry, `scripts/up.ps1`, and PostgreSQL / MongoDB / Redis.
