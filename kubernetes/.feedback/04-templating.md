# Killing the copy-paste

Three specific duplications are costing you real time.

---

## 1. The \*arr stack: 9 files, ~90 lines each, ~6 lines of actual difference

`sonarr`, `radarr`, `lidarr`, `prowlarr`, `bazarr`, `autobrr`, `sabnzbd`, `qui`,
`seerr` all use the same bjw-s `app-template` HelmRelease. Compare Sonarr and Radarr
— they differ in:

- `metadata.name`
- `image.repository` / `image.tag`
- the env-var prefix (`SONARR__` vs `RADARR__`)
- the hostname
- the PVC name

Everything else — probes, `securityContext`, `resources`, `defaultPodOptions`,
persistence layout, ingress block, the `&port 80` anchor trick — is identical, 80
lines at a time. When you want to change the readiness probe timeout or add a
`nodeSelector`, that's nine edits and one of them will get missed. (It already has:
Sonarr says `${apps_db_host}`, everyone else says `${apps_pg_host}`.)

### Fix: a Kustomize Component

```yaml
# components/arr-app/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

resources:
  - helm-release.yaml
  - pvc-config.yaml
```

```yaml
# components/arr-app/helm-release.yaml  — the shared 80 lines, once
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: PLACEHOLDER
spec:
  chartRef:
    kind: OCIRepository
    name: bjw-s-labs
    namespace: flux-system
  interval: 1h
  values:
    controllers:
      PLACEHOLDER:
        annotations:
          reloader.stakater.com/auto: "true"
        containers:
          app:
            env:
              TZ: ${timezone}
              LOG_LEVEL: info
              PORT: &port 80
            probes:
              liveness: { enabled: true, spec: { periodSeconds: 30, timeoutSeconds: 5, failureThreshold: 5 } }
              readiness:
                enabled: true
                custom: true
                spec:
                  httpGet: { path: /ping, port: *port }
                  periodSeconds: 10
                  timeoutSeconds: 5
                  failureThreshold: 5
              startup: { enabled: true, spec: { failureThreshold: 30, periodSeconds: 10 } }
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities: { drop: ["ALL"] }
            resources:
              requests: { cpu: 10m, memory: 256Mi }
              limits: { memory: 2Gi }
    defaultPodOptions:
      securityContext:
        runAsNonRoot: true
        runAsUser: ${media_puid}
        runAsGroup: ${media_pgid}
        fsGroup: ${media_pgid}
        fsGroupChangePolicy: OnRootMismatch
    service:
      app:
        ports:
          http: { port: *port }
    ingress:
      app:
        className: traefik
        hosts:
          - host: PLACEHOLDER.${cluster_domain}
            paths:
              - path: /
                service: { identifier: app, port: http }
    persistence:
      media:
        existingClaim: media
        globalMounts: [{ path: /media }]
      tmp:
        type: emptyDir
```

```yaml
# apps/media/sonarr/kustomization.yaml — the whole per-app file
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: media

components:
  - ../../../components/arr-app

patches:
  - target: { kind: HelmRelease, name: PLACEHOLDER }
    patch: |
      - op: replace
        path: /metadata/name
        value: sonarr
      - op: replace
        path: /spec/values/controllers/PLACEHOLDER
        value: sonarr
  - path: values.yaml
    target: { kind: HelmRelease }
```

```yaml
# apps/media/sonarr/values.yaml — the ~15 lines that are actually Sonarr
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: sonarr
spec:
  values:
    controllers:
      sonarr:
        containers:
          app:
            image:
              repository: ghcr.io/home-operations/sonarr
              tag: 4.0.17.2969@sha256:6806001ccc2ec95d941c9c0de012dbcb59c6a33932cfc17f71e300bdd48cabfe
            envFrom:
              - secretRef: { name: sonarr-secret }
            env:
              SONARR__POSTGRES__HOST: ${apps_pg_host}
              SONARR__APP__INSTANCENAME: Sonarr
              SONARR__AUTH__METHOD: External
    persistence:
      config:
        existingClaim: sonarr-config
        globalMounts: [{ path: /config }]
```

**Honest caveat:** Kustomize patching into nested Helm `values` is workable but
gets ugly fast, because the controller key is dynamic. Two alternatives worth
considering, in order of how much I'd recommend them:

**(a) Just use one HelmRelease with multiple controllers.** bjw-s `app-template`
supports several controllers in a single release. All the \*arr apps in one
`media-arr` HelmRelease means one file, shared defaults via YAML anchors, and one
`flux reconcile`. Downside: one bad value breaks all of them, and Renovate updates
become a single busier PR. For a homelab this is usually the right trade.

**(b) Write your own thin Helm chart.** You already did this once
(`apps/base/generate/chart/`) and it worked. A `charts/arr/` with a
`values.yaml` listing nine apps is arguably the simplest thing that could work:

```yaml
# charts/arr/values.yaml
apps:
  sonarr:
    image: ghcr.io/home-operations/sonarr
    tag: 4.0.17.2969
    envPrefix: SONARR
  radarr:
    image: ghcr.io/home-operations/radarr
    tag: 6.2.1.10461
    envPrefix: RADARR
```

Nine apps become nine YAML blocks of four lines. Renovate can still update the tags
if you annotate them. This is my actual recommendation — it's less clever than
Kustomize components and much easier to debug at 11pm.

Whichever you pick, the goal is the same: **changing a probe should be one edit.**

---

## 2. Seventy-one HelmRepository files

```bash
grep -rl "kind: HelmRepository" --include='*.yaml' kubernetes/ | wc -l   # 71
```

Ten of them are in `namespace: data`, four in `monitoring`, and there are duplicate
definitions of the same upstream repo (`cloudnative-pg`, `metallb`, `traefik`,
`cert-manager`, `prometheus-community` each appear 2–3 times in different
namespaces).

Flux resolves `sourceRef` across namespaces. **Put every `HelmRepository` and
`OCIRepository` in `flux-system`, in one directory, in one file per repo:**

```
platform/flux/repositories/
├── kustomization.yaml
├── bjw-s-labs.yaml        # OCIRepository, you already have this
├── cloudnative-pg.yaml
├── traefik.yaml
├── jetstack.yaml
├── metallb.yaml
├── prometheus-community.yaml
└── ...
```

and reference them uniformly:

```yaml
  chart:
    spec:
      chart: traefik
      version: 39.0.8
      sourceRef:
        kind: HelmRepository
        name: traefik
        namespace: flux-system      # <- always be explicit
```

You already do exactly this for `bjw-s-labs` and `external-secrets`. Extending it
gets you from 71 files to about 25, and — more usefully — gives you **one place to
see every upstream you depend on**, which is what you want when a chart repo goes
down or when you're auditing supply chain.

While you're there: prefer `OCIRepository` over `HelmRepository` where upstream
publishes OCI (jetstack, renovate, bjw-s already are). OCI pulls are faster and
don't require an index refresh.

---

## 3. Ingress: three patterns for one job

| Pattern | Count |
| --- | --- |
| Traefik `IngressRoute` CRD in its own file | 97 |
| Helm chart's native `ingress:` values block | 14 |
| Plain `networking.k8s.io/v1 Ingress` | 6 |

All three work. Having all three means that when a URL 404s, you don't know which
file to open. And the `IngressRoute` files are 100% boilerplate:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: audiobookshelf
  namespace: media
spec:
  entryPoints: [web]
  routes:
    - match: Host(`audiobookshelf.${cluster_domain}`)
      kind: Rule
      services:
        - name: audiobookshelf
          port: 19200
```

Ninety-three of your ninety-seven use `entryPoints: [web]` and a single
`Host()` match. That is a plain `Ingress` with extra steps.

**Recommendation: standardize on the Kubernetes `Ingress` object** with
`ingressClassName: traefik`. Reasons:

- bjw-s `app-template` generates it for you from the `ingress:` block — for every
  \*arr app the ingress file disappears entirely (you're already doing this for
  sonarr/radarr/lidarr; finish it)
- it's portable if you ever swap Traefik for something else
- Homepage, Gateway API, and most tooling discovers `Ingress`, not `IngressRoute`

Keep `IngressRoute` only where you genuinely need Traefik-specific features:
middlewares (Authentik forward-auth), `HostSNI`/TCP routing (Teleport), or complex
matchers. That's maybe five routes, and having them be the exception makes them
*visible*.

A component for the common case:

```yaml
# components/http-route/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  ingressClassName: traefik
  rules:
    - host: app.${cluster_domain}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app
                port: { name: http }
```

with a `nameSuffix`/`namePrefix` and a one-line patch per app.

**Also worth noting:** 93 of your routes are on `entryPoints: [web]` (HTTP :80),
only 2 on `websecure`. Since you terminate TLS at Cloudflare Tunnel that's
defensible, but it means anything reaching Traefik directly on the LAN/WireGuard
side is plaintext. See [05-access.md](05-access.md).

---

## 4. Two more small ones

**`default_values.yaml` files.** These are `helm show values` dumps kept for
reference. They're useful — don't delete them — but they're indistinguishable from
real config in a file listing, and Longhorn's is 300+ lines. Rename to
`chart-values.reference.yaml` and add them to `.rgignore`.

**Filler `secret.yaml` files.** Several kustomizations reference secrets they
comment out (`data-lakehouse/base/query/trino/kustomization.yaml` has
`#- secret.yaml`). If it's commented, delete the file. A commented-out resource plus
an orphaned SOPS-encrypted file is the worst of both worlds — it looks meaningful
and isn't.

---

## What "good" looks like after this

Adding a new \*arr app becomes:

```yaml
# charts/arr/values.yaml
  readarr:
    image: ghcr.io/home-operations/readarr
    tag: 0.4.18
    envPrefix: READARR
```

plus a `Database` entry in the CNPG cluster and a 1Password item. Three edits,
no new directory, no copied 90-line file. That's the difference between "I'll add
Readarr this weekend" and "I'll add Readarr eventually".
