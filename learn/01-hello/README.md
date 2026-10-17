# Lesson 1 — Hello, Olympus

Goal: understand the core Kubernetes objects by deploying one tiny website by hand.

## The path of a request

```
Browser: http://hello.localtest.me
  │  localtest.me always resolves to 127.0.0.1 (your PC)
  ▼
Windows port 80 ──► kind node container "olympus-control-plane", port 30080   (cluster/kind-config.yaml)
  ▼
Traefik pod (ingress controller)                                            (infra/traefik-values.yaml)
  │  reads Ingress rules: host hello.localtest.me → Service "hello"
  ▼
Service "hello"  ──load-balances──►  Pod 1 (nginx) / Pod 2 (nginx)          (03-service.yaml, 02-deployment.yaml)
                                     both serve index.html from a ConfigMap  (01-configmap.yaml)
```

## The objects (read the files in order — each has a comment)

| File | Object | One-line meaning |
|---|---|---|
| `00-namespace.yaml` | Namespace | A folder that groups objects |
| `01-configmap.yaml` | ConfigMap | Config/files given to Pods (not secrets) |
| `02-deployment.yaml` | Deployment | "Keep 2 nginx Pods running, always" |
| `03-service.yaml` | Service | A stable name/IP in front of the Pods |
| `04-ingress.yaml` | Ingress | "Send this hostname from outside to that Service" |

## Commands (run from the `platform` folder)

```powershell
kubectl apply -f learn/01-hello/             # create/update everything in the folder
kubectl get all -n hello                     # see Pods, Service, Deployment, ReplicaSet
kubectl describe pod -n hello <pod-name>     # details + events (why is it failing?)
kubectl logs -n hello deploy/hello           # nginx access logs
k9s -n hello                                 # terminal UI (press ? for help, :q to quit)
```

Open http://hello.localtest.me and the Traefik dashboard at http://traefik.localtest.me/dashboard/

## Exercises (try them — breaking things is the point)

1. **Self-healing:** `kubectl delete pod -n hello <one-pod>` then `kubectl get pods -n hello -w`. A new Pod appears. Why? (The Deployment wants 2.)
2. **Scaling:** `kubectl scale deploy/hello -n hello --replicas=4`. Watch the Pods. Then set `replicas: 3` in `02-deployment.yaml` and `kubectl apply` it — the file is the "truth" (this is the idea behind GitOps later).
3. **Change config:** edit the `<h1>` in `01-configmap.yaml`, `kubectl apply -f learn/01-hello/`, then `kubectl rollout restart deploy/hello -n hello` and refresh the browser.
4. **Break it:** change the image to `nginx:does-not-exist`, apply, and run `kubectl get pods -n hello`. You'll see `ImagePullBackOff`. Use `kubectl describe pod` to find the reason. Then `kubectl rollout undo deploy/hello -n hello`.
5. **Inside the cluster:** `kubectl run tmp -n hello --rm -it --image=busybox -- wget -qO- http://hello` — Pods find Services by name (DNS).

## Clean up / start over

```powershell
kubectl delete namespace hello                         # remove the lesson only
kind delete cluster --name olympus                     # remove the whole cluster
kind create cluster --config cluster/kind-config.yaml  # recreate it (then reinstall Traefik)
helm repo add traefik https://traefik.github.io/charts
helm upgrade --install traefik traefik/traefik -n traefik --create-namespace -f infra/traefik-values.yaml
```

In Phase 2, `scripts/up.ps1` will do all of this in one command.
