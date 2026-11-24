# argocd-config

The Argo CD bootstrap layer: the AppProject plus the top-level Application and ApplicationSets for config.
No Argo CD Application watches this folder. A named person applies changes by hand after a reviewed PR.

| File | What it is |
|---|---|
| `appproject-tsb.yaml` | AppProject `tsb`: allowed repo, destinations (by URL and by cluster name), cluster-scoped kinds |
| `tsb-base-application.yaml` | Application for `config/base` |
| `tsb-routes-applicationset.yaml` | One Application per `config/routes/*` folder |

Preflight Applications and ApplicationSets live in `preflight/steps/argocd-config/`.

Apply (AppProject first):

    kubectl -n argocd apply -f argocd-config/appproject-tsb.yaml
    kubectl -n argocd apply -f argocd-config/tsb-base-application.yaml
    kubectl -n argocd apply -f argocd-config/tsb-routes-applicationset.yaml

Never put secrets here (repo credentials, cluster secrets from `argocd cluster add`).
