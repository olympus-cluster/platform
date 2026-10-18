# Lesson 2 — The data layer and one-command platform

Goal: run PostgreSQL, MongoDB and Redis with persistent storage and admin UIs, and rebuild
the whole platform with one script.

## One command

```powershell
cd D:\dev\olympus-cluster\platform
powershell -ExecutionPolicy Bypass -File scripts\up.ps1      # build or repair everything
powershell -ExecutionPolicy Bypass -File scripts\verify.ps1  # PASS/FAIL for every part
powershell -ExecutionPolicy Bypass -File scripts\down.ps1    # delete the cluster (data too!)
```

`up.ps1` is **idempotent**: running it twice changes nothing the second time. That property is
what makes automation safe — the same idea as `kubectl apply`.

## What's running now

```
namespace      what                                   reach it
-----------    -------------------------------------  ------------------------------------------
data           pg-1        PostgreSQL (CloudNativePG)  pg-rw.data.svc:5432        (inside cluster)
               mongo-0     MongoDB 8                   mongo.data.svc:27017
               redis-0     Redis 8                     redis.data.svc:6379
tools          pgadmin     PostgreSQL UI               http://pgadmin.localtest.me
               mongo-express  MongoDB UI               http://mongo.localtest.me
               redisinsight   Redis UI                 http://redis.localtest.me
               headlamp    whole-cluster dashboard     http://headlamp.localtest.me
traefik        traefik     ingress (front door)        http://traefik.localtest.me/dashboard/
cnpg-system    operator    manages PostgreSQL
kube-system    metrics-server  CPU/RAM numbers         kubectl top pods -A
(Docker)       kind-registry   your image registry     localhost:5001
apps           (empty)     your APIs/portals — Phase 3
```

All passwords are in `platform\.env` (gitignored, created with random values on the first run).

## New concepts

| Concept | Where | Meaning |
|---|---|---|
| **Secret** | `scripts/secrets.ps1` | Like a ConfigMap, for passwords. Pods read them as env vars (`secretKeyRef`). Created from `.env`, never committed. |
| **StatefulSet** | `data/mongo.yaml`, `data/redis.yaml` | A Deployment for stateful apps: stable Pod names (`mongo-0`) and one disk per Pod. |
| **PVC / PV** | `volumeClaimTemplates` | PersistentVolumeClaim = "I need 5Gi of disk". kind's `local-path` provisioner creates the PersistentVolume. Data survives Pod restarts. |
| **Headless Service** | `clusterIP: None` in mongo | DNS points directly at the Pod(s) — needed when clients must talk to a specific DB instance. |
| **Operator + CRD** | `data/postgres.yaml` | CloudNativePG adds a new object type, `Cluster`. You declare "a Postgres with 1 instance and 5Gi"; the operator creates Pods, PVCs, Services (`pg-rw`, `pg-ro`), users, and handles failover. |
| **Kustomize** | `data/kustomization.yaml` | Lists files and sets their namespace. `kubectl apply -k data` applies the folder. |
| **Helm chart** | `infra/*-values.yaml` | A packaged app (Traefik, CNPG, Headlamp…) you configure with a values file. |
| **Local registry** | `kind-registry` | Where you push your own images so the cluster nodes can pull them (Phase 3 & Tilt). |
| **Resource limits** | every container | `requests` = reserved, `limits` = max. Keeps the whole lab inside the 16 GB WSL budget. |

## Try it

1. **Log in to every UI.** Passwords are in `.env`.
   - pgAdmin: open server *olympus → olympus pg*, password = `POSTGRES_PASSWORD`. Create a table, insert a row.
   - mongo-express: create database `catalog`, collection `products`, add a document.
   - RedisInsight: open *olympus redis*, add a key `greeting = hello`.
   - Headlamp: get a token with `kubectl create token headlamp -n tools --duration 24h` and paste it.
2. **Prove persistence.** After adding data, delete the database Pods:
   ```powershell
   kubectl -n data delete pod pg-1 mongo-0 redis-0
   kubectl -n data get pods -w      # watch them come back (Ctrl+C to stop)
   ```
   Refresh the UIs — your rows, documents and keys are still there, because they live on the PVCs:
   ```powershell
   kubectl -n data get pvc
   ```
3. **Talk to a database from the command line** (how the apps will do it):
   ```powershell
   kubectl -n data exec -it pg-1 -c postgres -- psql -d app
   kubectl -n data exec -it redis-0 -- redis-cli -a <REDIS_PASSWORD>
   ```
4. **Look at the operator's work:** `kubectl -n data get cluster,pods,svc,pvc,secrets` — you wrote
   one `Cluster` object; CNPG created everything else.
5. **Watch resources:** `kubectl top pods -A --sort-by=memory`, or press `:pods` then `Shift+M` in `k9s`.
6. **Break and rebuild:** `down.ps1` then `up.ps1` (~8 min). Everything comes back — but the
   **data is gone**, because PVCs live inside the cluster. Treat the cluster as disposable; we'll add
   seed scripts for test data with the apps.

## Connecting from your PC (IntelliJ, DBeaver, Compass…)

Databases are not exposed through Traefik (it's HTTP only). Use a port-forward while you need it:

```powershell
kubectl -n data port-forward svc/pg-rw 5432:5432        # Postgres  -> localhost:5432
kubectl -n data port-forward svc/mongo 27017:27017      # Mongo     -> localhost:27017
kubectl -n data port-forward svc/redis 6379:6379        # Redis     -> localhost:6379
```
