# Quick wins

Ordered by (impact ÷ effort). The first three are the ones that will make the repo
feel different.

---

## 1. Delete the lakehouse filler — ~250 files, 30 minutes

44 files under `data-lakehouse/base/` named `deployment.yaml` are byte-identical
copies of `apps/base/media/arr/fileflows/deployment.yaml` — same `namespace: media`,
same `image: revenz/fileflows`, same PUID 1037. Verify for yourself:

```bash
cd kubernetes
md5sum data-lakehouse/base/*/*/deployment.yaml | awk '{print $1}' | sort | uniq -c
#  44 e6181f7a7b45731f8be4a12bcb00fad6   <- the fileflows copy
#   1 c34c1d0fb7b251708b426432cb7962b5
#   1 b45be5a71a45869279434778b9c98ec4
```

Every one of those directories also carries a `service.yaml`, `ingress-route.yaml`,
`pvc-config.yaml`, `secret.yaml` (SOPS-encrypted!), and `kustomization.yaml` in the
same state. `data-lakehouse/overlays/production/kustomization.yaml` only references
`databases`, `management`, and `orchestration` — so **none of this is deployed and
none of it is reachable from Flux.** It exists purely to be found by your grep.

Replace it with a checklist. In `data-lakehouse/CANDIDATES.md`:

```markdown
# Tools I want to evaluate
- [ ] Trino — federated SQL over Iceberg/Postgres. Needs ~4Gi. Blocked on RAM.
- [ ] LakeFS — git-for-data over S3. Try after Iceberg is working.
- [ ] Marquez — OpenLineage collector. Only worth it once >5 pipelines exist.
```

Then:

```bash
# preview
git rm -r --dry-run data-lakehouse/base/{quality,query,semantic,visualization,ingestion,machine-learning,catalog,storage/{lakefs,rook-ceph,seaweedfs}}
```

Keep `databases/`, `management/`, `orchestration/`, `observability/clickstack`,
`storage/pv-data.yaml`, `storage/pvc-data.yaml`, and `namespace.yaml`. Re-add
directories one at a time, *when you deploy them*.

Same treatment for the empty scaffolding elsewhere:

- `apps/templates/{api,cronjob,postgres-app,stateful-app,worker}/` — all `.gitkeep`
- `data-lakehouse/templates/*` — all `.gitkeep` except one filler `spark-job`
- `infrastructure/base/{crowdsec,rook-ceph}/` — `.gitkeep`
- `monitoring/base/{grafana,loki,prometheus}/` — `.gitkeep`, and `monitoring` is
  commented out of `clusters/production/kustomization.yaml` anyway

**Result: `kubernetes/` drops from 985 files to roughly 700, and `data-lakehouse/`
from 384 to about 60.**

---

## 2. Make your editor stop drowning — 5 minutes

Even after the cleanup, add a `.rgignore` at the repo root so ripgrep, Telescope,
and `fzf` skip the noise that isn't yours:

```gitignore
# .rgignore
**/default_values.yaml
**/authentik_export/
terraform/**/.terraform/
.tfstate/
ansible/collections/
ansible/.ansible/
```

`default_values.yaml` files are vendored `helm show values` dumps — Longhorn's
alone is 300+ lines and it pollutes every search for a value key. They're useful as
reference but should never appear in a fuzzy-find. Consider renaming them
`chart-values.reference.yaml` so it's obvious they are documentation, not config.

For Neovim specifically: the repo has **3,832 YAML files** total (most in
`terraform/` and `ansible/`). Point your project pickers at `kubernetes/` directly
rather than the repo root, and if you use `yamlls`, restrict its
`schemas`/`fileMatch` to `kubernetes/**` — otherwise it tries to index Ansible
collections and stalls.

---

## 3. Fix the substitution variables — 15 minutes

`postBuild.substituteFrom` failures are silent-ish and cause exactly the kind of
debugging you're describing. Current state:

| Variable | Defined? | Notes |
| --- | --- | --- |
| `${cluster_domain}` | ✅ ConfigMap | used 127× |
| `${media_puid}` / `${media_pgid}` | ✅ ConfigMap | used 30× |
| `${apps_pg_host}` / `${apps_pg_port}` | ✅ ConfigMap | |
| `${timezone}` | ✅ ConfigMap | used 8× |
| `${personal_domain}` / `${hidden_domain}` | ✅ Secret | |
| **`${apps_db_host}`** | ❌ **undefined** | `apps/base/media/arr/sonarr/helm-release.yaml` |
| `${cluster_lb_ip}` | ⚠️ defined, never used | value `192.168.100.200` doesn't match your MetalLB pool `10.10.10.0/28` |

`${apps_db_host}` is a typo for `apps_pg_host`. Sonarr is pointing at a Postgres
host that resolves to a literal empty string or the unsubstituted token depending
on your Flux settings.

Delete `cluster_lb_ip` from `clusters/production/cluster-vars.yaml` — it's a stale
value from a different network and will mislead you (or me, next time) into
thinking your LB range is 192.168.x.

**Guard against the next one.** Add to your Flux Kustomizations:

```yaml
  postBuild:
    substitute: {}
    substituteFrom:
      - kind: ConfigMap
        name: cluster-vars
      - kind: Secret
        name: cluster-vars-secret
```

and add a CI check (see [06-reliability.md](06-reliability.md)) that greps the built
output for a leftover `${`.

---

## 4. Stop hardcoding the domain — 20 minutes

You have `${cluster_domain}` used 127 times, which is great, but these slipped
through with `theblacklodge.dev` baked in:

- `infrastructure/base/traefik/*` — `traefik.theblacklodge.dev` in the dashboard
  `matchRule` (this one is inside `helm-release.yaml` values and *is* templated;
  double check which of the two you're seeing)
- `apps/base/media/arr/radarr/*` — `radarr.theblacklodge.dev`
- `apps/base/media/arr/prowlarr/*` — `prowlarr.theblacklodge.dev`
- `apps/base/generate/ingressroute.yaml` — `generate.austinsmith.org` (this one may
  be intentional; if so use `${personal_domain}`)

Also, several manifests hardcode `TZ: America/Denver` and `PUID/PGID 1037/100`
while `${timezone}`, `${media_puid}`, `${media_pgid}` exist. `sonarr`, `radarr`,
`lidarr`, and `audiobookshelf` all do this inconsistently — some use the variable
for `securityContext` and the literal for `TZ` **in the same file**.

```bash
# find them all
grep -rn "theblacklodge\|America/Denver\|\"1037\"\|\"100\"" --include='*.yaml' apps/ infrastructure/ data-lakehouse/
```

---

## 5. Right-size Postgres for a single node — 10 minutes

You are running **one k3s server node and zero agents** (`ansible/inventories/k3s_cluster.yml`).
But:

- `infrastructure/base/cloudnative-pg/cluster.yaml` → `instances: 3`
- `data-lakehouse/base/databases/cloudnative-pg/cluster.yaml` → `instances: 3`

That's six Postgres pods on one machine. They cannot provide HA (one node = one
failure domain), they each hold a full 15Gi Longhorn volume, and CNPG will burn CPU
on streaming replication between processes on the same disk. Your Longhorn
`numberOfReplicas` is already correctly set to `1` for the same reason — apply the
same logic here:

```yaml
spec:
  instances: 1   # single-node cluster; revisit when you add an agent node
```

Then invest the freed RAM in `postgresql.parameters.shared_buffers` and in actually
having backups (`spec.backup.barmanObjectStore` pointed at RustFS or Backblaze),
which protects you far better than same-node replicas do.

Same question for `data-lakehouse/base/databases/clickhouse/` — a ClickHouse Keeper
cluster plus a ClickHouse cluster on one node is fine at `replicas: 1, shards: 1`
(which is what you have — good), but keep it that way.

---

## 6. Move the misplaced ExternalSecrets — 10 minutes

`infrastructure/base/cloudnative-pg/external-secret.yaml` defines three
ExternalSecrets, two of which target `namespace: media` (`autobrr`, `bazarr`).
Database *credentials for media apps* living in the infrastructure layer means:

- the `media` namespace must already exist when `infrastructure` reconciles
  (it's created by `apps`, which `dependsOn: infrastructure` — a latent ordering bug)
- when you debug Bazarr you will not think to look in the CNPG folder

Move them next to their apps. Better yet, stop hand-writing them at all — see
[03-secrets.md](03-secrets.md) §"Let the database mint its own passwords".

---

## 7. Prune the dead docs

`kubernetes/README.md`, `apps/README.md`, and `data-lakehouse/README.md` are all
half to-do list, half genuinely useful command reference. The to-do lists are stale
(`apps/README.md` says Homepage is migrated and Mealie isn't; both are deployed).

Split them: keep the `kubectl`/`helm` cheatsheet in `kubernetes/README.md`, move
every checklist into a single `kubernetes/ROADMAP.md`. One place to look, one place
to update.

---

## Estimated result

| | Before | After |
| --- | --- | --- |
| Files in `kubernetes/` | 985 | ~700 (and ~400 after [02-structure.md](02-structure.md)) |
| Files in `data-lakehouse/` | 384 | ~60 |
| Undefined template vars | 1 | 0 |
| Postgres pods | 6 | 2 |
