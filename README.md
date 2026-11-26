# tsb-gitops

Single source of truth for TSB, managed by Argo CD:

1. **Config and apps**: TSB objects (Tenant, Workspace, Groups), gateways, routes and sample apps.
2. **Upgrades**: phased TSB management plane, control plane and data plane upgrades.

Argo CD only talks to the Kubernetes API. TSB objects are applied as Kubernetes CRs, and the
TSB GitOps webhook and operator push them into TSB.

## Layout today

```
tsb-gitops/
├── argocd-config/        # Argo CD bootstrap, applied by hand once: AppProject, config Application and ApplicationSet
├── config/               # TSB config and apps
│   ├── base/             # shared: namespaces, gateway install, Tenant, Workspace, Group
│   └── routes/<name>/    # per-instance Istio Gateway + VirtualService
└── preflight/            # phase 0, built and running (see below)
    ├── set-run-id.sh     # one command sets the same RUN_ID in every step
    ├── common/backup-storage/   # the 250Mi backup PVC, one per cluster
    └── steps/
        ├── image-sync, version-skew, cluster-health, content-hash,
        │   backup-postgres, backup-k8s-objects, route-baseline,
        │   cert-and-capacity, chainsaw-pre      # one folder per step, one folder per cluster inside
        └── argocd-config/                       # the Application / ApplicationSet of each step
```

Not built yet: the phase 1 to 3 upgrade folders (`upgrade/...`), the rollback runbook and Jobs, `backup-verify`, `route-compare` and `chainsaw-post`.
The design is in `TSB-Upgrade-Design.md`.

## Preflight (phase 0)

Every step is a Job run by Argo CD in each cluster. It writes `success` or `failed` into the ConfigMap `preflight-<RUN_ID>` of its own cluster
(read it there: `kubectl --context <cluster> -n preflight get cm preflight-<RUN_ID> -o yaml`). A step has one `shared/config.yaml` (the `RUN_ID` trigger and settings for all clusters) and one folder per cluster.

| Step | Doc |
|---|---|
| `image-sync` | `ImageSync-Setup.md` |
| `version-skew` | `VersionSkew-Setup.md` |
| `cluster-health` | `ClusterHealth-Setup.md` |
| `content-hash` | `ContentHash-Setup.md` |
| backup volume (PVC) | `BackupStorage-Setup.md` |
| `backup-postgres` | `BackupPostgres-Setup.md` |
| `backup-k8s-objects` | `BackupK8sObjects-Setup.md` |
| `route-baseline` | `RouteBaseline-Setup.md` |
| `cert-and-capacity` | `CertCapacity-Setup.md` |
| `chainsaw-pre` | `ChainsawPre-Setup.md` |

To run everything:

1. Apply the AppProject, then each `preflight/steps/argocd-config/*.yaml` once (the backup storage first, then the steps).
2. `preflight/set-run-id.sh run-NNN`, commit and push. All steps start in every cluster.
3. Read each cluster's result: `kubectl --context <cluster> -n preflight get cm preflight-<RUN_ID> -o yaml`.

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
