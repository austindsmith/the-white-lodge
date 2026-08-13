# Secrets: getting from 50+ 1Password items to ~15

## Current state

You are running **two secret systems simultaneously**:

| System | Count | Where |
| --- | --- | --- |
| External Secrets → 1Password | 33 `ExternalSecret` resources in 28 files | apps, infra, data |
| SOPS + age | ~86 encrypted files | everywhere |

Plus a third implicit one: `infrastructure/base/cloudnative-pg/secret.yaml` is a
single 680-line SOPS blob containing **26 hand-written `*-db-secret` credentials**.

That's the "a lot to manage" feeling. It isn't the *number* of secrets — it's that
you have three places to look and no rule for which one a given secret lives in.

The good news: your `ClusterSecretStore` is set up correctly, and roughly half your
ExternalSecrets already use the right pattern (`dataFrom.extract`, one 1Password
item → many keys). You need to finish the job, not restart it.

---

## The target model

**Four tiers, and every secret belongs to exactly one.**

### Tier 1 — Bootstrap (SOPS, exactly one file)

`external-secrets/operator/secret.yaml`, the 1Password service account token.
This is the only secret that *cannot* come from 1Password, because it's the key to
1Password. Keep it SOPS-encrypted. **Everything else stops using SOPS.**

Your `.sops.yaml` then covers one path instead of eighty-six, and you delete the
`decryption:` block from every Flux Kustomization except the external-secrets one.
That also removes a whole class of "why is Flux failing" — SOPS decryption errors
are cryptic and you currently have them possible in six places.

### Tier 2 — Human-owned secrets (1Password, one item per *domain*, not per app)

These are the things only you know: API tokens from vendors, your own passwords.
There should be very few.

| 1Password item | Fields | Consumed by |
| --- | --- | --- |
| `cloudflare` | `api_token`, `account_id`, `tunnel_name`, `domains`, `hidden_domain`, `personal_domain` | cert-manager, tunnel, ddns, cluster-vars |
| `cluster` | `domain`, `admin_email`, `timezone` | cluster-vars |
| `github` | `webhook_token`, `app_id`, `app_private_key` | flux receiver, renovate |
| `synology` | `username`, `password`, `host` | synology-csi |
| `vpn` | `wireguard_private_key`, `wireguard_addresses`, `server_countries` | gluetun |
| `plex` | `claim_token` | plex |
| `usenet` | `sabnzbd_api_key`, provider creds | sabnzbd |
| `indexers` | one field per tracker | prowlarr |
| `authentik` | `bootstrap_password`, `bootstrap_token`, `secret_key` | authentik |
| `smtp` | `host`, `user`, `password`, `from` | ntfy, mealie, paperless, authentik |
| `backblaze` / `offsite` | `key_id`, `application_key`, `bucket` | CNPG backups, Longhorn backups |

**That's ~11 items.** You already do this correctly for `cloudflare` — one item,
six fields, three consumers. Generalize the pattern.

The key insight: your current `cloudflare/api_token` style (`key: item/field`) and
your `extract: { key: prowlarr }` style (whole item → all fields) are both fine,
but **prefer `extract`** — it means adding a field in 1Password requires no
Kubernetes change at all.

### Tier 3 — Machine-generated secrets (never touch 1Password)

Database passwords, session keys, encryption keys, internal API keys. **You should
not be inventing these, storing them, or rotating them by hand.** This tier is
where your 50-item problem actually lives.

**3a. Let CloudNativePG mint database passwords.**

Right now `infrastructure/base/cloudnative-pg/cluster.yaml` declares 25 managed
roles, each pointing at a `*-db-secret` you hand-wrote into a SOPS file. Instead,
declare the role and let CNPG generate:

```yaml
# databases/apps-cluster/cluster.yaml
  managed:
    roles:
      - name: sonarr
        ensure: present
        login: true
        # no passwordSecret -> CNPG generates and manages one
```

CNPG creates `apps-cluster-sonarr` (or you name it) as a `kubernetes.io/basic-auth`
secret in the cluster namespace. Then one `ClusterExternalSecret`-free approach:
copy it to the app's namespace with a `Reflector` annotation, or simpler, put the
app in the same namespace as nothing and just reference the CNPG-created secret via
a small `ExternalSecret`-free `Secret` sync.

The cleanest option given what you already run: **`PushSecret`**, which you've
already used once (`data-lakehouse/base/databases/cloudnative-pg/push-secret.yaml`)
and correctly identified in your own README:

> "Switch this up so that cloudnative-pg creates the secrets and then uses
> `Push Secrets` to sync to `1 Password`."

That note is exactly right. Do it. The flow becomes:

```
CNPG generates password
   → Secret in cnpg-apps namespace
      → PushSecret writes it to 1Password (so DBeaver/psql on your laptop can read it)
      → App namespace gets it via ExternalSecret reading that same 1Password item
```

You author zero passwords. 1Password becomes a *mirror* for human access, not a
source you maintain. **This eliminates 26 of your ~50 items' worth of maintenance
even if the items still exist.**

One `PushSecret` per cluster, using a wildcard match, rather than 26:

```yaml
apiVersion: external-secrets.io/v1alpha1
kind: PushSecret
metadata:
  name: cnpg-apps-credentials
  namespace: cnpg-apps
spec:
  updatePolicy: Replace
  deletionPolicy: Delete
  refreshInterval: 1h
  secretStoreRefs:
    - name: op-secret-store
      kind: ClusterSecretStore
  selector:
    secret:
      name: apps-cluster-sonarr        # one block per role, or use a label selector
  template:
    metadata:
      labels:
        managed-by: cnpg
  data:
    - match:
        remoteRef:
          remoteKey: db-sonarr
```

Check your ESO version's support for `selector.secret.selector` (label-based) —
newer versions let you match many secrets with one `PushSecret`, which collapses
this to a single resource for the whole cluster.

**3b. Generate app secrets in-cluster.**

For things like Authentik's `secret_key`, ClickStack's
`express_session_secret`, Paperless' `SECRET_KEY` — nobody ever needs to read these
from a phone. Use the ESO `Password` generator:

```yaml
apiVersion: generators.external-secrets.io/v1alpha1
kind: Password
metadata:
  name: strong-password
  namespace: data
spec:
  length: 42
  digits: 6
  symbols: 0          # symbols in DB URLs cause escaping pain; skip them
  noUpper: false
  allowRepeat: true
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: clickstack-session
  namespace: data
spec:
  refreshInterval: 0                 # generate once, never rotate unprompted
  target:
    name: clickstack-session
    creationPolicy: Owner
  dataFrom:
    - sourceRef:
        generatorRef:
          apiVersion: generators.external-secrets.io/v1alpha1
          kind: Password
          name: strong-password
      rewrite:
        - regexp: { source: "password", target: "EXPRESS_SESSION_SECRET" }
```

Define the `Password` generator **once per namespace** and reference it from every
ExternalSecret that needs a random value. That's another handful of 1Password items
gone.

### Tier 4 — Config files that happen to contain a secret

This is an anti-pattern you've fallen into in four places:

- `bazarr/config.yaml` stored whole in 1Password
- `seerr/settings.json` stored whole in 1Password
- `qui/config.toml` stored whole in 1Password
- `agregarr/settings.json` stored whole in 1Password

Storing a 200-line JSON config in a password manager means you can't diff it, can't
review it, can't Renovate it, and every unrelated setting change is a 1Password
edit. It also makes those items enormous and is probably a real contributor to your
"50+ objects" fatigue.

**You already found the right fix and used it exactly once** — the qBittorrent
pattern in `apps/base/media/arr/qbittorrent-vpn/external-secret.yaml`:

```yaml
  target:
    name: qbittorrent-config-files
    template:
      templateFrom:
        - configMap:
            name: qbittorrent-config-files
            items:
              - key: qBittorrent.conf
  dataFrom:
    - extract:
        key: qbittorrent
```

The config lives in a git-tracked ConfigMap with `{{ .api_key }}` placeholders; the
secrets come from 1Password; ESO renders them together. Apply this to all four.
The config becomes reviewable, and the 1Password item shrinks to three fields.

---

## Naming convention

Pick one and never deviate — inconsistency here is why you can't remember what's in
the vault. Suggested:

| Thing | 1Password item name | Kubernetes Secret name | ExternalSecret name |
| --- | --- | --- | --- |
| App secrets | `sonarr` | `sonarr-secret` | `sonarr` |
| DB credentials | `db-sonarr` | `sonarr-db-secret` | `sonarr-db` |
| Shared/domain | `cloudflare` | `cloudflare-secret` | `cloudflare` |
| Certificates | `ca-cnpg-apps` | `cnpg-apps-ca` | `cnpg-apps-ca` |

Right now you have `prowlarr` → target `prowlarr`, `gluetun` → target `gluetun`,
but `bazarr` → both `bazarr` and `bazarr-settings`, and Sonarr's HelmRelease
references `sonarr-secret` while nothing appears to create it. Consistency here is
worth more than any individual optimization.

Also: **use the ExternalSecret name to describe the secret, not the mechanism.**
You have `prowlarr-external-secret`, `cnpg-data-external-secret`,
`cluster-vars-secret-external-secret`. The kind is already in the resource. Drop
the suffix — `kubectl get externalsecret -A` becomes readable.

---

## One shared ClusterExternalSecret for cross-cutting values

Things every namespace needs (SMTP, the OIDC issuer URL, the wildcard cert) should
not be 12 copies of the same ExternalSecret. Use `ClusterExternalSecret`:

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterExternalSecret
metadata:
  name: smtp
spec:
  externalSecretName: smtp
  namespaceSelectors:
    - matchLabels:
        needs-smtp: "true"
  refreshTime: 6h
  externalSecretSpec:
    secretStoreRef:
      kind: ClusterSecretStore
      name: op-secret-store
    target:
      name: smtp
      creationPolicy: Owner
    dataFrom:
      - extract:
          key: smtp
```

Then label the namespaces that need it. One resource, N namespaces, and adding a
new app that sends mail is a one-line namespace label.

---

## Making the vault navigable

Inside 1Password, use the item **tags** and a naming prefix so the vault sorts
usefully:

```
db-*          machine-generated, pushed by PushSecret, DO NOT EDIT
app-*         app credentials you may need in a browser
infra-*       cloudflare, synology, backblaze — you edit these
gen-*         generated in-cluster, mirrored for reference only
```

Add a `notes` field on every item saying which manifest consumes it:

> Consumed by `kubernetes/apps/media/sonarr/external-secret.yaml`. Managed by CNPG
> — do not edit; edit the Cluster spec instead.

Six months from now that note is the difference between a 30-second fix and an
afternoon.

---

## Verification commands

```bash
# every ExternalSecret and whether it's synced
kubectl get externalsecret -A -o custom-columns=\
'NS:.metadata.namespace,NAME:.metadata.name,STORE:.spec.secretStoreRef.name,READY:.status.conditions[0].status,REASON:.status.conditions[0].reason'

# the ones that are broken, only
kubectl get externalsecret -A -o json | jq -r '
  .items[] | select(.status.conditions[0].status != "True")
  | "\(.metadata.namespace)/\(.metadata.name): \(.status.conditions[0].message)"'

# which 1Password keys are referenced anywhere in the repo
grep -rhoE 'key: [a-z0-9/_.-]+' --include='*.yaml' kubernetes/ | sort -u

# secrets that exist in-cluster but nothing references (candidates for deletion)
kubectl get secrets -A -o json | jq -r '.items[] | select(.type=="Opaque") | "\(.metadata.namespace)/\(.metadata.name)"'
```

Save the second one as `just secrets-broken`. It should be the first thing you run
when an app won't start.

---

## Migration order

1. Fix the Tier 4 config-file items (4 apps) — biggest reduction in 1Password bulk.
2. Switch CNPG to generated passwords + one `PushSecret`. Delete the 680-line
   `infrastructure/base/cloudnative-pg/secret.yaml`. **Back it up first**, and do
   one role at a time so a failure only breaks one app.
3. Move the remaining SOPS secrets to 1Password items, one folder at a time.
4. Delete `decryption:` from the Flux Kustomizations that no longer need it.
5. Consolidate one-field items into domain items (`smtp`, `infra-*`).

Expected end state: **~15 1Password items you actively maintain**, ~25 mirrored
machine-generated ones you never touch, one SOPS file.
