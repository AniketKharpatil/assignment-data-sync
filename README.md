# data-sync

Platform assignment: deploying the `data-sync` FastAPI service (REST API on 8080,
Redis-backed, `/health` + `/metrics`) to Kubernetes and to VMs. Cloud target is
AWS/EKS - the assignment permits AWS in place of GCP.

## Part 1 - Helm chart + Kustomize overlay

- [`helm/charts/data-sync/`](helm/charts/data-sync/) - Deployment, Service (ClusterIP),
  HPA on CPU, ConfigMap, Secret, PDB, ServiceMonitor
- Three values files: defaults (local), staging (2 replicas, INFO), production
  (HPA 3–20, strict limits)
- [`standard/data-sync/production/`](standard/data-sync/production/) - Kustomize overlay
  adding AZ spread and the `SECRET_CHECKSUM` patch on the rendered chart output
- Details → [helm/charts/data-sync/README.md](helm/charts/data-sync/README.md)

## Part 2 - Ansible role `be-data-sync`

- [`ansible/`](ansible/) - installs Python 3.9, clones the repo to `/srv/data-sync`,
  builds a venv, manages a systemd unit
- Gated to hosts where `be_role == 'service'`; `install` and `deploy` tags
- Details → [ansible/README.md](ansible/README.md)

## Part 3 - Design answers

- [DESIGN.md](DESIGN.md) - cutting scale-out lag from 90s to under 20s, isolating from
  noisy neighbours, zero-downtime `REDIS_PASSWORD` rotation

## Testing

- Verified with `helm lint`, `kubeconform`, `kubectl kustomize`, `ansible-lint`
  (production profile)
 