# tsb-gitops

Single source of truth for TSB, managed by Argo CD:

1. **Config and apps**: TSB objects (Tenant, Workspace, Groups), gateways, routes and sample apps.
2. **Upgrades**: phased TSB management plane, control plane and data plane upgrades.

Argo CD only talks to the Kubernetes API. TSB objects are applied as Kubernetes CRs, and the
TSB GitOps webhook and operator push them into TSB.

## Planned layout

```
tsb-gitops/
├── bootstrap/            # Argo CD AppProject, ApplicationSets (the entry point)
├── config/               # TSB config and apps
│   ├── base/             # shared: namespaces, gateway install, Tenant, Workspace, Group
│   └── routes/<name>/    # per-instance Istio Gateway + VirtualService
├── upgrade/
│   ├── clusters/<name>/  # version.yaml pinned per cluster
│   ├── phase0-preflight/ # PreSync Jobs: backups, baseline checks
│   ├── phase1-mp-cp/     # MP and CP upgrade, no maintenance window
│   ├── phase2-dp/        # enable revision, gateway and sidecar restarts (manual sync)
│   └── checks/           # PostSync Jobs: chainsaw, route checker
└── docs/                 # runbooks, rollback
```

Today the repo has no folders yet. The httpbin demo manifests are still to be added under `config/`.

## Upgrade model

| Phase | What | Window | Argo CD |
|---|---|---|---|
| 0 | Pre-checks, backups | None | PreSync hooks |
| 1 | MP then CP upgrade | No traffic failover (to be verified) | Sync-waves, PostSync checks |
| 2 | Enable revision, DP restarts | Maintenance window | Separate Application, manual sync |

- A version bump is a PR that edits `upgrade/clusters/<name>/version.yaml`.
- A failed check stops the sync, so later waves and clusters don't run.
- Rollback is a Git revert plus the manual DB restore (CP clusters first, MP last).

## Prerequisites

- TSB GitOps enabled in the ManagementPlane and ControlPlane CRs
- `tctl x gitops grant <cluster>` run for each target cluster
- Argo CD installed (see `ArgoCD-setup.md`)

## Rules

- Never commit plain secrets. Use Sealed Secrets, SOPS or External Secrets.
- Keep `prune: false` until deletion behaviour is proven.
- Add `ignoreDifferences` for `gitops.tsb.tetrate.io/*` annotations on TSB objects.
- Don't point one Application at a parent folder that holds duplicate resources.
