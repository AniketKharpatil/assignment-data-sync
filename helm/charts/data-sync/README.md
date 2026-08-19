# data-sync Helm chart

Helm chart for `data-sync`, a Python FastAPI service that exposes a REST API on
port 8080, reads its configuration from environment variables, and uses Redis for
caching. It serves `/health` (returns `{"status": "ok"}`) and `/metrics` for
Prometheus.

Cloud target is **AWS/EKS** (the assignment permits AWS in place of GCP). Nothing
here is EKS-specific except example hostnames and the IRSA annotation hint ie the
zone spreading uses the standard `topology.kubernetes.io/zone` label.

---

## Contents

| Object | Template | Notes |
|---|---|---|
| Deployment | `templates/deployment.yaml` | Configurable replicas, resources, pull policy; probes; security context |
| Service | `templates/service.yaml` | ClusterIP, named `http` port |
| HorizontalPodAutoscaler | `templates/hpa.yaml` | `autoscaling/v2`, CPU utilization target, `behavior` tuning |
| ConfigMap | `templates/configmap.yaml` | Non-sensitive env: `APP_ENV`, `LOG_LEVEL`, `WORKERS`, `MAX_CONNECTIONS`, `REDIS_HOST`, `REDIS_PORT` |
| Secret | `templates/secret.yaml` | `REDIS_PASSWORD`; **only** rendered when `secret.existingSecret` is empty |
| PodDisruptionBudget | `templates/pdb.yaml` | `minAvailable: 1` |
| ServiceMonitor | `templates/servicemonitor.yaml` | Scrapes `/metrics` every 30s, label `release: kube-prometheus-stack` |

Pods run with `default` ServiceAccount. A dedicated SA would be the first thing
to add if we needs IRSA for AWS API access.

Values files:

| File | Purpose |
|---|---|
| `values.yaml` | Safe defaults: 1 replica, `DEBUG` logs, local Redis, HPA off, ServiceMonitor off |
| `values.staging.yaml` | 2 replicas, `INFO` logs, staging Redis host |
| `values.production.yaml` | HPA min 3 / max 20, strict resource limits, production Redis host |

The base `values.yaml` is intentionally the *cheap and harmless* configuration:
`helm install` with no `-f` produces one small pod, no autoscaler, and no
dependency on cluster add-ons that may not exist.

---

## Prerequisites

- Helm 3.8+, Kubernetes 1.25+ (tested rendering against 1.29 )
- The `redis` sub-chart is **declared but disabled**. Helm still requires it to be
  present locally before templating, so run this once after cloning:

```bash
helm dependency build helm/charts/data-sync
```

For staging and production, two things must exist in the cluster beforehand:

1. **Secret `data-sync-redis`** with key `REDIS_PASSWORD`, managed outside Helm
   (see [Secret handling](#secret-handling)).
2. For production only: the node pool, taint, and `platform-high` PriorityClass
   referenced by `values.production.yaml` (see [Production scheduling](#production-scheduling-prerequisites)).

---

## Install / upgrade

Values files are layered explicitly : the environment file is passed **after**
`values.yaml`, and later `-f` wins. Passing only the environment file also works
(Helm merges chart defaults automatically), but being explicit makes the
precedence obvious to the next person reading the command.

### Staging

```bash
helm upgrade --install data-sync helm/charts/data-sync \
  --namespace data-sync-staging --create-namespace \
  -f helm/charts/data-sync/values.yaml \
  -f helm/charts/data-sync/values.staging.yaml \
  --atomic --timeout 5m
```

### Production

```bash
helm upgrade --install data-sync helm/charts/data-sync \
  --namespace data-sync --create-namespace \
  -f helm/charts/data-sync/values.yaml \
  -f helm/charts/data-sync/values.production.yaml \
  --atomic --timeout 10m
```

`--atomic` rolls back automatically if the release fails to become ready, so a
bad deploy does not leave a half-migrated state. Pin the image per deploy with
`--set image.tag=<sha>` rather than editing the values file by hand.

### Dry run / diff before applying

```bash
# render only
helm template data-sync helm/charts/data-sync \
  -f helm/charts/data-sync/values.yaml \
  -f helm/charts/data-sync/values.production.yaml

# server-side validation against the live API (needs cluster access)
helm upgrade --install data-sync helm/charts/data-sync \
  -f helm/charts/data-sync/values.yaml \
  -f helm/charts/data-sync/values.production.yaml \
  --dry-run=server

# diff against what is live (requires the helm-diff plugin)
helm diff upgrade data-sync helm/charts/data-sync \
  -f helm/charts/data-sync/values.yaml \
  -f helm/charts/data-sync/values.production.yaml
```

### Rollback

```bash
helm history data-sync -n data-sync
helm rollback data-sync <revision> -n data-sync --wait
```

### Uninstall

```bash
helm uninstall data-sync -n data-sync
```

Note: a chart-rendered Secret carries `helm.sh/resource-policy: keep`, so it
survives uninstall and must be deleted by hand if you really want it gone.

---

## Local validation

Everything below runs without a cluster.

```bash
# raw commands, from the repo root
helm lint helm/charts/data-sync
helm template data-sync helm/charts/data-sync \
  -f helm/charts/data-sync/values.yaml \
  -f helm/charts/data-sync/values.production.yaml
kubectl kustomize standard/data-sync/production
```

Current status of this chart:

```
$ helm lint (defaults / staging / production)
1 chart(s) linted, 0 chart(s) failed        # x3, only "icon is recommended" INFO

$ helm template ... | kubeconform -strict -kubernetes-version 1.29.0
staging     Valid: 6, Invalid: 0, Errors: 0
production  Valid: 7, Invalid: 0, Errors: 0

$ kubectl kustomize standard/data-sync/production | kubeconform -strict
Valid: 7, Invalid: 0, Errors: 0
```

`kubeconform` is given the [datree CRDs-catalog](https://github.com/datreeio/CRDs-catalog)
as a second schema source, because the default store has no schema for
`ServiceMonitor`. Without it, that resource is skipped rather than validated.

### Smoke test on kind

```bash
kind create cluster --name data-sync
helm install data-sync helm/charts/data-sync \
  --set redis.deployLocal=true \
  --set secret.password=localdev
kubectl rollout status deploy/data-sync --timeout=120s
kubectl port-forward svc/data-sync 8080:80
curl -fsS localhost:8080/health   # {"status":"ok"}
```

`redis.deployLocal=true` brings up the Bitnami Redis sub-chart so there is
something to connect to. The default `values.yaml` points at
`redis-master.data-sync.svc.cluster.local`, which is the sub-chart's service name.
