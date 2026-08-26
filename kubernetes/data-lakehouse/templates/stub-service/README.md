# stub-service template

## What this is

Every "try a chart out" app under `data-lakehouse/base/*` was meant to get its
own manifests, but 43 of the 56 leaf directories there today are byte-for-byte
copies of `kubernetes/apps/base/media/arr/fileflows/` — same `name: fileflows`,
`image: revenz/fileflows`, `namespace: media`, regardless of the directory being
named `trino`, `kafka`, `airflow`, `superset`, etc. None of them deploy the tool
they're named after.

This directory is a single, parameterized version of that same shape (one
`Deployment` + `Service` + Traefik `IngressRoute` + one `PersistentVolumeClaim`)
with the four fields that actually vary per app — **name, image, port, PVC
size** — pulled out into `CHANGEME-*` placeholders. Trying a new tool now means
writing a ~15-line `patch.yaml`, not copy-pasting five files.

This is **not** wired into any `kustomization.yaml` and won't be built by Flux
on its own — it only takes effect where a consumer explicitly references it
with a patch, as shown below. No existing directory has been changed to use it
yet; that migration is left to you, following the walkthrough in step 2.

## How it works

This repo already uses this exact pattern elsewhere — see
`kubernetes/infrastructure/overlays/staging/traefik/patch.yaml` and
`.../cloudflare-tunnel/patch.yaml`: a base is referenced from `resources:`,
and a `patches: [{path: patch.yaml}]` entry supplies a strategic-merge patch
that Kustomize matches to the base's resources by `apiVersion`/`kind`/
`metadata.name`/`metadata.namespace`. No Kustomize `replacements`, `vars`, or
`kind: Component` — those aren't used anywhere else in this repo, so this
template doesn't introduce them either.

## 1. Using it for a brand-new experimental app

Say you want to try out a tool called `example-app`, image
`ghcr.io/example/example-app:latest`, listening on port `8080`, needing a 5Gi
config volume. Create `kubernetes/data-lakehouse/base/<category>/example-app/`
with two files:

`kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: data

resources:
  - ../../../templates/stub-service

patches:
  - path: patch.yaml
```

`patch.yaml` (one strategic-merge document per resource that needs a change —
Kustomize matches each document to a base resource by kind/name/namespace):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: CHANGEME-name
  namespace: data
spec:
  selector:
    matchLabels:
      app: example-app
  template:
    metadata:
      labels:
        app: example-app
    spec:
      containers:
        - name: example-app
          image: ghcr.io/example/example-app:latest
          ports:
            - containerPort: 8080
              protocol: TCP
          startupProbe:
            httpGet:
              port: 8080
          livenessProbe:
            httpGet:
              port: 8080
          readinessProbe:
            httpGet:
              port: 8080
          volumeMounts:
            - mountPath: /config
              name: example-app-config
      volumes:
        - name: example-app-config
          persistentVolumeClaim:
            claimName: example-app-config
---
apiVersion: v1
kind: Service
metadata:
  name: CHANGEME-name
  namespace: data
spec:
  selector:
    app: example-app
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: CHANGEME-name
  namespace: data
spec:
  routes:
    - match: Host(`example-app.${cluster_domain}`)
      kind: Rule
      services:
        - name: example-app
          port: 8080
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: CHANGEME-name-config
  namespace: data
spec:
  resources:
    requests:
      storage: 5Gi
```

Note the `metadata.name` on each patch document stays `CHANGEME-name` /
`CHANGEME-name-config` — that's how Kustomize finds which base resource to
merge into, since the base's `metadata.name` is still the placeholder. The
*contents* of that resource (labels, selectors, container name, image, ports,
etc.) are what you change to the real values. Rename the actual Kubernetes
object (`metadata.name`) by adding a `nameSuffix`/`nameReplacements`-free
approach isn't worth it here — for a first try, leaving the object literally
named `CHANGEME-name` is harmless (it's a fresh object), and you can rename it
to something real once you're happy with the app and are giving it a
permanent home.

Finally wire the new directory into `data-lakehouse/overlays/production/`
(or `staging/`) the same way the existing real apps do — see
`kubernetes/data-lakehouse/overlays/production/management/bytebase/kustomization.yaml`
for the pattern (a one-line shim: `resources: [../../../../base/<category>/<app>]`)
— and add it to the parent category's `kustomization.yaml`
(e.g. `overlays/production/<category>/kustomization.yaml`).

## 2. Migrating an existing stub — worked example: `trino`

`kubernetes/data-lakehouse/base/query/trino/` today is the unmodified
fileflows copy. To move it onto this template instead:

1. Delete `deployment.yaml`, `service.yaml`, `ingress-route.yaml`,
   `pvc-config.yaml`, `secret.yaml` from `base/query/trino/`.
2. Replace `base/query/trino/kustomization.yaml` with:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   namespace: data

   resources:
     - ../../../templates/stub-service

   patches:
     - path: patch.yaml
   ```
3. Add `base/query/trino/patch.yaml`, following the 4-document shape in
   section 1 above, with `example-app` replaced by `trino`, a real Trino
   image (e.g. `trinodb/trino:latest`), Trino's default port `8080`, and
   whatever PVC size you want to try (Trino itself is largely stateless
   compute, so a small `1Gi` for `/config`-equivalent scratch space is
   reasonable — expand later if you add a catalog/config mount).
4. `trino/` isn't currently reachable from Flux (`overlays/production/`
   only wires `databases`, `management`, `orchestration`, `visualization` —
   not `query`), so wiring it up also means adding a `query` entry to
   `overlays/production/kustomization.yaml` plus a
   `overlays/production/query/kustomization.yaml` and
   `overlays/production/query/trino/kustomization.yaml` shim, mirroring the
   `management/bytebase` example referenced above.
5. Validate locally before trusting it against the live cluster:
   `kustomize build kubernetes/data-lakehouse/base/query/trino` (not run here
   — no `kustomize`/`kubectl` binary is available in this environment).

Repeat this same 3-step process (delete the 5 stub files, add the 2-file
`kustomization.yaml` + `patch.yaml` pair) for each of the other 42 stub
directories as you get around to actually trying each tool. There's no need
to do them all at once — an unmigrated stub directory that's simply never
referenced from `overlays/` costs nothing at runtime.

## Known issues found while researching this (not fixed here — out of scope)

- `base/catalog/nessie/kustomization.yaml` lists `deployment.yaml` under
  `resources:`, but no such file exists in that directory — a
  `kustomize build` on that path will fail. (`nessie` isn't currently wired
  into `overlays/production/`, which is presumably why this hasn't surfaced.)
- `kubernetes/clusters/staging/data-lakehouse.yaml` (the Flux `Kustomization`
  for the staging cluster) points `spec.path` directly at
  `./kubernetes/data-lakehouse/base`, but there is no `kustomization.yaml` at
  `base/`'s root — only per-category subfolders. If staging reconciliation
  runs this path, it will fail to build.
- `templates/spark-job/` (a sibling of this directory) is itself an untouched
  fileflows copy, not a real template — worth replacing with something
  similar to `stub-service/` once a Spark-specific shape is needed.
- `base/management/dbgate/` mixes a real `helmrelease.yaml` with orphaned,
  inconsistently-named `deployment.yaml`/`ingressroute.yaml` (no hyphen,
  unlike this repo's usual `ingress-route.yaml`) leftovers that aren't
  referenced by its `kustomization.yaml`.
- All 43 stub copies hardcode `namespace: media`, which is wrong for this
  tree (the declared namespace is `data`, see `base/namespace.yaml`) — this
  template defaults to `namespace: data` instead.
