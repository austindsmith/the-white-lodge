# Repo structure

## The core problem: `base/overlays` is costing you and paying nothing

You have five top-level domains (`apps`, `core`, `infrastructure`, `monitoring`,
`data-lakehouse`), each with `base/` + `overlays/production/` + `overlays/staging/`.
That's the canonical Kustomize layout and it's the right call **when you have two
real clusters that differ**. You don't:

- `clusters/staging/` has no `core.yaml` and no `external-secrets.yaml`, and points
  at `data-lakehouse` and `monitoring` overlays that are empty `.gitkeep` dirs.
  It cannot deploy.
- `apps/overlays/staging/` = two `.gitkeep` files.
- `monitoring/overlays/staging/` = one `.gitkeep`.
- `data-lakehouse/overlays/staging/` = a `.gitkeep` and one stray `calibre/chart.yaml`.

So `overlays/production/` is 100% pass-through. Look at what it actually contains:

```yaml
# apps/overlays/production/media/kustomization.yaml — the entire file
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../base/media
```

Twelve of these exist under `apps/overlays/production/` alone. Every app you add
costs you a second directory and a `../../../` you have to count. Every app you
debug costs you two file-opens to find the real manifest. That is the "clunky"
feeling you described, and it is entirely self-inflicted overhead.

### What to do instead

**Delete the `base/overlays` split and put the environment selection in
`clusters/`, which is where it already effectively lives.**

Your `clusters/production/apps.yaml` already does the real work — it names a path,
injects variables, wires `dependsOn`. That is your overlay. The variables that
*would* differ between prod and staging (`cluster_domain`, PUIDs, LB IPs) are
already in `cluster-vars`, per cluster. You're 90% of the way to a
one-tree-many-clusters model; the `overlays/` dirs are vestigial.

If and when you build a real staging cluster, the difference will be expressed as:

```yaml
# clusters/staging/apps.yaml
  path: ./kubernetes/apps          # same tree
  postBuild:
    substituteFrom:
      - kind: ConfigMap
        name: cluster-vars          # different values
  patches:                          # the handful of genuine differences
    - patch: |
        - op: replace
          path: /spec/values/resources/requests/memory
          value: 128Mi
      target:
        kind: HelmRelease
```

Flux Kustomizations support `patches` natively. You do not need a filesystem
overlay for this.

---

## Proposed layout

```
kubernetes/
├── clusters/
│   ├── production/          # unchanged — this layer is good
│   │   ├── kustomization.yaml
│   │   ├── cluster-vars.yaml
│   │   ├── cluster-secrets.yaml
│   │   └── ks/              # one Flux Kustomization per file
│   │       ├── 00-external-secrets.yaml
│   │       ├── 10-platform.yaml
│   │       ├── 20-storage.yaml
│   │       ├── 30-networking.yaml
│   │       ├── 40-databases.yaml
│   │       ├── 50-apps.yaml
│   │       └── 60-data.yaml
│   └── staging/             # delete until it's real, or make it real
│
├── platform/                # was: core/ + parts of infrastructure/
│   ├── cert-manager/
│   ├── external-secrets/
│   ├── flux/                # HelmRepositories + OCIRepositories, ALL of them
│   ├── metallb/
│   ├── traefik/
│   ├── longhorn/
│   ├── synology-csi/
│   ├── teleport/
│   ├── cloudflare-tunnel/
│   ├── cloudflare-ddns/
│   ├── metrics-server/
│   └── renovate/
│
├── databases/               # was: infrastructure/base/cloudnative-pg + data-lakehouse/base/databases
│   ├── cnpg-operator/
│   ├── apps-cluster/
│   ├── data-cluster/
│   └── clickhouse/
│
├── apps/                    # one dir per app, flat-ish, no base/overlay
│   ├── media/               # namespace-level grouping is fine and useful
│   │   ├── namespace.yaml
│   │   ├── storage/
│   │   ├── sonarr/
│   │   ├── radarr/
│   │   └── ...
│   ├── authentik/
│   ├── homepage/
│   └── ...
│
├── data/                    # was: data-lakehouse/, minus the filler
│   ├── namespace.yaml
│   ├── airbyte/
│   ├── dagster/
│   ├── dbgate/
│   ├── pgadmin4/
│   └── clickstack/
│
├── components/              # reusable kustomize Components — see 04-templating.md
│   ├── arr-app/
│   ├── traefik-route/
│   └── cnpg-database/
│
├── README.md                # cheatsheet only
└── ROADMAP.md               # every checklist, in one place
```

Why this shape:

- **`core` vs `infrastructure` was never a real distinction.** You have MetalLB and
  CloudNativePG defined in *both* (`core/base/metallb` + `infrastructure/base/metallb`,
  `core/base/cloudnative-pg` + `infrastructure/base/cloudnative-pg`) with the
  operator in one and the CRs in the other. That split is the single most confusing
  thing in the tree. Name the layers by *what they do* (`platform` = cluster
  services, `databases` = data stores, `apps` = things with a URL), and put the
  operator and its CRs together with a `dependsOn` annotation, which you already
  know how to use:

  ```yaml
  # you already do this correctly in infrastructure/base/cloudnative-pg/cluster.yaml
  annotations:
    kustomize.toolkit.fluxcd.io/depends-on: helm.toolkit.fluxcd.io/namespaces/cnpg-apps/cloudnative-pg
  ```

- **`monitoring/` disappears.** It's 11 files, 3 of them `.gitkeep`, commented out
  of the production kustomization. `kube-prometheus-stack` belongs in `platform/`.

- **Depth drops from 5 to 3.** `kubernetes/apps/base/media/arr/sonarr/helm-release.yaml`
  becomes `kubernetes/apps/media/sonarr/helm-release.yaml`. The `arr/` level buys
  nothing — everything under `apps/base/media/` except `immich` and `storage` is
  already in `arr/`.

---

## File naming: pick one convention and enforce it

Right now the same resource kind has different filenames in different folders:

| Resource | Names in use |
| --- | --- |
| HelmRelease | `helm-release.yaml`, `helmrelease.yaml`, `chart.yaml` |
| HelmRepository | `helm-repository.yaml`, `helmrepository.yaml` |
| IngressRoute | `ingress-route.yaml`, `ingressroute.yaml`, `ingress.yaml` |
| Values reference | `default_values.yaml`, `default_variables.yaml`, `values.yaml` |

This actively breaks muscle memory and glob patterns. Pick kebab-case
(`helm-release.yaml`, `ingress-route.yaml`, `external-secret.yaml`) since that's
your majority, and rename the stragglers:

```bash
# survey the damage
find . -name 'helmrelease.yaml' -o -name 'helmrepository.yaml' -o -name 'ingressroute.yaml' -o -name 'default_variables.yaml'
```

**One rule that pays for itself:** the filename should be the *kind*, not the app.
`sonarr/helm-release.yaml`, never `sonarr/sonarr.yaml`. That way
`find apps -name external-secret.yaml` gives you every app's secrets in one shot.

---

## Add schema annotations

You already do this on exactly one file
(`infrastructure/base/renovate/oci-repository.yaml`):

```yaml
# yaml-language-server: $schema=https://k8s-schemas.home-operations.com/source.toolkit.fluxcd.io/ocirepository_v1.json
```

Do it everywhere, or better, configure it once in Neovim so you don't have to:

```lua
-- yamlls settings
settings = {
  yaml = {
    schemas = {
      ["https://k8s-schemas.home-operations.com/all.json"] = "kubernetes/**/*.yaml",
    },
    schemaStore = { enable = false },
  },
}
```

This turns "Flux rejected my HelmRelease and I don't know why" into a red squiggle
before you commit. Given that you said debugging is eating your time, this is
probably the single highest-value editor change available to you.

---

## Migration order (so you don't break prod)

Do this on a branch, with Flux still pointed at `main`:

1. Delete the filler ([01-quick-wins.md](01-quick-wins.md) §1). Merge. Verify Flux
   is still green.
2. Flatten `overlays/production/X/kustomization.yaml` → change
   `clusters/production/*.yaml` `path:` to point directly at `<domain>/base`, then
   `git rm -r <domain>/overlays`. Do **one domain at a time**, merge, verify.
3. Rename `<domain>/base/` → `<domain>/`. Update the `path:` in `clusters/`.
4. Merge `core/` into `platform/`, resolving the MetalLB and CNPG duplicates.
5. Rename files to the convention.

At every step: `kustomize build clusters/production --enable-helm | kubectl diff -f -`
before you push. Your `justfile` already has most of this — see
[06-reliability.md](06-reliability.md) for a hardened version.
