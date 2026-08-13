# Reliability, updates, and debugging

## The `wait: true` trap you're currently in

`clusters/production/` defines six Flux Kustomizations in a chain:

```
external-secrets-operator
  └─ external-secrets-config
       └─ core                (wait: true)
            ├─ infrastructure (wait: true)
            │    └─ apps      (wait: true)
            └─ data-lakehouse (wait: true)
```

`wait: true` means Flux blocks until **every resource in that Kustomization reports
healthy** before marking it Ready. Combined with `dependsOn`, one sick pod anywhere
in `infrastructure` stops `apps` from reconciling at all — including apps that have
nothing to do with the broken thing.

This is almost certainly a chunk of the debugging pain you described. You change
Sonarr's image tag, push, and nothing happens, because RustFS has been
`CrashLoopBackOff` for two days over an unrelated credential.

You can see it right now with:

```bash
flux get kustomizations -A
flux get helmreleases -A --status-selector ready=false
```

### Fix: narrow the blast radius

**Split by failure domain, not by folder.** The things that genuinely must be
healthy before anything else are: external-secrets, cert-manager, MetalLB/Traefik,
storage (Longhorn/synology-csi), and the CNPG operator. Everything else can fail
independently.

```
clusters/production/ks/
  00-external-secrets.yaml   wait: true    # nothing works without this
  10-platform.yaml           wait: true    dependsOn: external-secrets
  20-storage.yaml            wait: true    dependsOn: platform
  30-networking.yaml         wait: true    dependsOn: platform
  40-databases.yaml          wait: true    dependsOn: storage
  50-apps.yaml               wait: FALSE   dependsOn: networking, databases
  60-data.yaml               wait: FALSE   dependsOn: databases
```

`wait: false` on the leaf layers means a broken Mealie doesn't block a Sonarr
update. You lose the guarantee that "apps is Ready implies everything works" — but
you were never getting that guarantee in practice, you were getting a stall.

**Even better: one Flux Kustomization per app.** This is what the flux-community
"cluster-template" repos do, and it's the single biggest reliability upgrade
available to you. You already have the pattern in two places
(`apps/base/media/arr/brrpolice/ks.yaml`,
`infrastructure/overlays/production/teleport/flux-kustomizations.yaml`) — you just
haven't generalized it.

```yaml
# apps/media/sonarr/ks.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: sonarr
  namespace: flux-system
spec:
  interval: 30m
  path: ./kubernetes/apps/media/sonarr
  prune: true
  wait: false
  timeout: 5m
  sourceRef: { kind: GitRepository, name: flux-system }
  dependsOn:
    - name: cnpg-apps-cluster
  postBuild:
    substituteFrom:
      - { kind: ConfigMap, name: cluster-vars }
      - { kind: Secret, name: cluster-secrets }
```

Then `flux get ks -A` becomes a live status board of every app, and
`flux reconcile ks sonarr --with-source` fixes one app in three seconds instead of
reconciling 400 files. **This is the thing that will most change your day-to-day.**

The cost is one extra ~20-line file per app. Generate it from a template; it's
identical except `name` and `path`.

---

## Add CI. You have none.

There is no `.github/` directory in this repo. Every syntax error, missing variable,
and invalid CRD field is discovered by Flux, in production, at reconcile time. For a
repo where you said debugging is the bottleneck, this is the highest-leverage
missing piece after the `wait: true` change.

Minimum viable pipeline:

```yaml
# .github/workflows/validate.yaml
name: validate
on: [pull_request, push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: fluxcd/flux2/action@main
      - name: Build every kustomization
        run: |
          for d in kubernetes/clusters/production; do
            kustomize build "$d" --enable-helm --enable-alpha-plugins > /tmp/out.yaml
          done
      - name: Fail on unsubstituted variables
        run: |
          if grep -nE '\$\{[a-zA-Z_][a-zA-Z0-9_]*\}' /tmp/out.yaml; then
            echo "::error::unsubstituted variable in built output"; exit 1
          fi
      - name: Validate against cluster schemas
        run: |
          kubeconform -strict -ignore-missing-schemas \
            -schema-location default \
            -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
            /tmp/out.yaml
```

That one grep would have caught `${apps_db_host}` in Sonarr. `kubeconform` catches
misspelled CRD fields, which is the other half of your Flux errors.

Add `flux-local` (a Python tool that renders HelmReleases offline and diffs them
between branches) once the basics work — it turns "what will this PR actually
change in the cluster" into a PR comment.

---

## Renovate is scaffolded but not running

`infrastructure/base/renovate/` contains a `Namespace` and an `OCIRepository` — but
**no `HelmRelease`**, and `renovate` is not in
`infrastructure/overlays/production/kustomization.yaml`. There's also no
`renovate.json` anywhere in the repo.

Same for `metrics-server`: base exists, not in the overlay. (Which means
`kubectl top` doesn't work, which means you can't see what's eating your single
node's RAM — worth fixing on its own.)

Getting Renovate running matters more than usual for you because of the image
pinning style you use:

```yaml
tag: 4.0.17.2969@sha256:6806001ccc2ec95d941c9c0de012dbcb59c6a33932cfc17f71e300bdd48cabfe
```

Digest-pinned tags are excellent practice and completely unmaintainable by hand.
A minimal `renovate.json`:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended", "helpers:pinGitHubActionDigests"],
  "flux": { "managerFilePatterns": ["/kubernetes/.+\\.ya?ml$/"] },
  "kubernetes": { "managerFilePatterns": ["/kubernetes/.+\\.ya?ml$/"] },
  "packageRules": [
    {
      "description": "Group the arr stack",
      "matchPackageNames": ["**/sonarr", "**/radarr", "**/lidarr", "**/prowlarr", "**/bazarr"],
      "groupName": "arr stack"
    },
    {
      "description": "Auto-merge patch updates for stateless apps",
      "matchUpdateTypes": ["patch"],
      "matchFilePatterns": ["kubernetes/apps/**"],
      "automerge": true
    },
    {
      "description": "Never auto-merge storage or database",
      "matchPackageNames": ["**longhorn**", "**cloudnative-pg**", "**clickhouse**", "**rook**"],
      "automerge": false,
      "minimumReleaseAge": "7 days"
    }
  ]
}
```

Run it as a `CronJob` in-cluster (the chart supports it) so it doesn't need GitHub
Actions minutes, and point it at your Gitea mirror if you'd rather keep it local.

---

## Single-node realities to design around

You have one k3s server and zero agents. Some consequences worth encoding:

**Every `PodDisruptionBudget` and anti-affinity rule is a footgun.** If a chart ships
`replicas: 2` with `requiredDuringScheduling` anti-affinity, one pod pends forever.
Check for this whenever something is stuck `Pending`.

**Set resource requests everywhere, and keep them honest.** Right now you have
`audiobookshelf` requesting `cpu: 4000m, memory: 2Gi` with a `10 CPU` limit — on a
single VPS that one request may be a large fraction of your allocatable CPU, and
the scheduler will refuse to place other pods. Meanwhile the \*arr apps request
`10m`. Audit with:

```bash
kubectl get pods -A -o custom-columns=\
'NS:.metadata.namespace,NAME:.metadata.name,CPU:.spec.containers[*].resources.requests.cpu,MEM:.spec.containers[*].resources.requests.memory' \
  | sort -k3 -h -r | head -20
```

**Node pressure is your most likely outage cause.** Add these alerts before you add
any more apps: node memory > 85%, node disk > 80%, any pod `OOMKilled`, any
PVC > 85% full. You have `kube-prometheus-stack` in `core/` — but `monitoring` is
commented out of `clusters/production/kustomization.yaml`, so you have CRDs and no
alerts. Turning that on is cheap and directly reduces "why did everything break."

**Backups matter more than replicas.** With one node, `instances: 3` buys nothing
(see [01-quick-wins.md](01-quick-wins.md) §5) but a CNPG object-store backup buys
everything:

```yaml
spec:
  backup:
    retentionPolicy: 30d
    barmanObjectStore:
      destinationPath: s3://cnpg-backups/apps-cluster
      endpointURL: http://rustfs.rustfs.svc.cluster.local:9000
      s3Credentials:
        accessKeyId:     { name: rustfs-credentials, key: access_key }
        secretAccessKey: { name: rustfs-credentials, key: secret_key }
      wal: { compression: gzip }
      data: { compression: gzip, jobs: 2 }
---
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: apps-cluster-daily
spec:
  schedule: "0 0 3 * * *"
  backupOwnerReference: self
  cluster: { name: apps-cluster }
```

RustFS is on the same node, so also replicate offsite — you already have a
`terraform/offsite-backups/` directory, so wire Longhorn's backup target and CNPG's
to that instead of, or in addition to, RustFS.

---

## A debugging playbook

Put this in `kubernetes/README.md` and delete the to-do lists. When something is
broken, in order:

```bash
# 1. Is Flux even applying?
flux get kustomizations -A
flux get helmreleases -A

# 2. What's actually failing?
flux get all -A --status-selector ready=false

# 3. Why?
flux logs --level=error --all-namespaces --since=30m

# 4. Secrets synced?
kubectl get externalsecret -A -o json | jq -r '
  .items[] | select(.status.conditions[0].status != "True")
  | "\(.metadata.namespace)/\(.metadata.name): \(.status.conditions[0].message)"'

# 5. Pods unhappy?
kubectl get pods -A --field-selector=status.phase!=Running | grep -v Completed

# 6. Recent cluster events, most recent last
kubectl get events -A --sort-by=.lastTimestamp | tail -40

# 7. Force one thing to retry
flux reconcile kustomization <name> --with-source
flux reconcile helmrelease <name> -n <ns>

# 8. What did Flux actually build?
kustomize build kubernetes/clusters/production --enable-helm | yq 'select(.metadata.name == "sonarr")'
```

### Improve the justfile

Your current `justfile` is a good start but `just server apply` renders the whole
`clusters/staging` tree and applies it with `kubectl` — which fights Flux. Suggested
additions:

```make
# What would change if I pushed this?
diff:
    kustomize build clusters/production --enable-helm --enable-alpha-plugins \
      | kubectl diff -f - || true

# Catch unsubstituted variables before Flux does
lint:
    kustomize build clusters/production --enable-helm --enable-alpha-plugins > /tmp/build.yaml
    @grep -nE '\$\{[a-zA-Z_][a-zA-Z0-9_]*\}' /tmp/build.yaml && echo "UNSUBSTITUTED VARS" && exit 1 || echo "vars ok"
    kubeconform -strict -ignore-missing-schemas /tmp/build.yaml

# Status board
status:
    flux get kustomizations -A
    flux get helmreleases -A
    kubectl get externalsecret -A

# Everything that is currently broken, and why
broken:
    flux get all -A --status-selector ready=false
    kubectl get pods -A --field-selector=status.phase!=Running | grep -v Completed || true

# Reconcile one app right now
sync app:
    flux reconcile kustomization {{ app }} --with-source
```

`just lint` before every push, `just broken` when something's wrong. Two commands
to remember instead of twenty.

---

## Priority order

1. `wait: false` on `apps` and `data-lakehouse` — five minutes, immediate relief.
2. `just lint` + the unsubstituted-variable grep — thirty minutes.
3. Turn on `monitoring` with node/disk/OOM alerts — an hour.
4. CNPG scheduled backups — an hour, and it's the one that saves you from disaster.
5. Per-app Flux Kustomizations — a weekend, but it changes how the whole repo feels.
6. Renovate + GitHub Actions validation — a weekend.
