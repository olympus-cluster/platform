# olympus-cluster / platform

The local Kubernetes platform for the **olympus-cluster** learning lab: a disposable
[kind](https://kind.sigs.k8s.io/) cluster on Windows (WSL2 + Docker Desktop) that runs
databases, Spring Boot / FastAPI APIs and Angular SSR portals.

| Folder | What's inside |
|---|---|
| `cluster/` | `kind-config.yaml` (1 control-plane + 1 worker, ports 80/443), namespaces, local-registry wiring |
| `infra/` | Helm values for shared components: Traefik, metrics-server, Headlamp |
| `data/` | PostgreSQL (CloudNativePG), MongoDB, Redis — `kubectl apply -k data` |
| `tools/` | pgAdmin, mongo-express, RedisInsight — `kubectl apply -k tools` |
| `scripts/` | `up.ps1` · `down.ps1` · `verify.ps1` · `secrets.ps1` |
| `learn/` | Step-by-step lessons: [01 hello](learn/01-hello/README.md) · [02 data](learn/02-data/README.md) |

## Quick start

Requires Docker Desktop (WSL2), kind, kubectl and helm.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\up.ps1      # build everything (~8 min from scratch)
powershell -ExecutionPolicy Bypass -File scripts\verify.ps1  # check everything
```

| URL | What |
|---|---|
| http://headlamp.localtest.me | Cluster dashboard (`kubectl create token headlamp -n tools`) |
| http://pgadmin.localtest.me | PostgreSQL UI |
| http://mongo.localtest.me | MongoDB UI |
| http://redis.localtest.me | Redis UI |
| http://traefik.localtest.me/dashboard/ | Ingress dashboard |

Passwords are generated into `.env` (gitignored) on the first run. Template: [`.env.example`](.env.example).
