# Reaching your apps and databases from your devices

## Your current topology, as I read it

```
                        ┌─────────────────────────────────────┐
 Internet ──────────────│ Cloudflare (DNS + Tunnel + TLS)     │
                        └───────────────┬─────────────────────┘
                                        │ cloudflared
                                        │ Ingress class: cloudflare-tunnel
                                        │ *.thewhitelodge.org
                                        │ *.${hidden_domain}
                                        │ *.${personal_domain}
                                        ▼
   Your laptop ──WireGuard(wg0)──▶  ┌──────────────────────────────┐
   Your phone                       │ netcup VPS                    │
                                    │ kubernetes-server-01          │
                                    │ single-node k3s v1.36.1       │
                                    │  flannel over wg0             │
                                    │  ├─ Traefik (hostNetwork :80) │
                                    │  ├─ MetalLB 10.10.10.0/28     │
                                    │  ├─ Teleport                  │
                                    │  ├─ Authentik                 │
                                    │  ├─ CNPG apps-cluster         │
                                    │  └─ CNPG data-cluster         │
                                    └──────────────────────────────┘
```

You have **four** separate ways in (Cloudflare Tunnel, Traefik on hostNetwork,
MetalLB LoadBalancer IPs, Teleport) and they overlap. That's why connecting feels
fiddly — there's no single answer to "how do I reach X."

---

## Problem 1: MetalLB L2 on a single cloud VPS probably isn't doing what you think

`infrastructure/base/metallb/ip-address-pool.yaml` advertises `10.10.10.0/28` via
`L2Advertisement`. L2 mode works by answering ARP requests on a shared broadcast
domain. Your node's cluster interface is `wg0` — a point-to-point WireGuard link,
not a broadcast segment. There is no ARP to answer.

In practice this means `cnpg-apps-lb` at `10.10.10.2` is reachable only if you have
a static route pushed to your WireGuard peers (`AllowedIPs` including
`10.10.10.0/28`). It might be working for you precisely because of that — but it's
load-bearing configuration that lives in your WireGuard config, not in this repo,
and that's exactly the kind of thing that makes debugging feel like juggling.

Two honest options:

**(a) Keep it, and document it.** Add to `platform/metallb/README.md`: which
`AllowedIPs` each peer needs, and the fact that these IPs are WireGuard-only. Also
delete the stale `cluster_lb_ip: 192.168.100.200` from `cluster-vars.yaml`, which
refers to a network that appears nowhere else in the repo.

**(b) Drop MetalLB entirely and route database access through Teleport.** On a
single node with no LAN, MetalLB is providing you three IPs for two Postgres
clusters. Teleport is already deployed and already has a `db-access` role listing
every database by name. That's the better tool for this job — see below.

I'd lean (b), because it removes a whole component, and because MetalLB + hostNetwork
Traefik + Cloudflare Tunnel is three overlapping ingress paths on one machine.

---

## Problem 2: `pg_hba` `trust` rules

Both CNPG clusters have:

```yaml
    pg_hba:
      - hostssl all all 10.42.0.0/16 trust
      - hostssl all all 192.168.1.0/24 trust
      - hostssl all all 192.168.2.5/32 trust
      - hostssl all all all scram-sha-256
```

`10.42.0.0/16` is your pod CIDR. `trust` means **any pod in the cluster can connect
as any Postgres user, including `postgres` superuser, with no password.** A
compromised container — say, one of the many `:latest`-tagged media images — has
full read/write on Authentik's user table and every other database.

Combined with `ansible/inventories/group_vars/all.yml` opening `5432/tcp` on the
host firewall, the blast radius is larger than you probably intend.

Fix: delete the `trust` lines and rely on `scram-sha-256` for everything. Your apps
already get passwords via secrets, so this should be a no-op for them. Keep one
narrow exception if you need it for local admin:

```yaml
    pg_hba:
      - hostssl all all all scram-sha-256
```

If something breaks after this, it was relying on passwordless superuser access,
which is worth knowing about.

Also: `enableSuperuserAccess: true` on both clusters. CNPG defaults this to `false`
for good reason. Turn it off unless you're actively using the `postgres` role, and
use `kubectl cnpg psql` (the plugin) for admin instead.

---

## Recommended access model: one path per audience

### Web apps → Cloudflare Tunnel, always

This already works and is the right design. `*.${cluster_domain}` → tunnel →
Traefik → service. Nothing exposed on the VPS's public IP, TLS handled upstream,
works identically from your phone on cellular and your laptop at home.

Two improvements:

1. **Put Authentik forward-auth in front of everything by default.** You have the
   middleware (`apps/base/authentik/middleware.yaml`) and Authentik is deployed.
   Right now most routes have no auth, which means anything that leaks a hostname
   is publicly reachable. Make protected the default and public the exception:

   ```yaml
   # components/authenticated-route/kustomization.yaml
   apiVersion: kustomize.config.k8s.io/v1alpha1
   kind: Component
   patches:
     - target: { kind: Ingress }
       patch: |
         - op: add
           path: /metadata/annotations/traefik.ingress.kubernetes.io~1router.middlewares
           value: authentik-authentik-forwardauth@kubernetescrd
   ```

   Then `components: [../../components/authenticated-route]` in each app.

2. **Use Cloudflare Access on the tunnel for the handful of things Authentik can't
   protect** (anything doing its own auth badly, like a bare Redis UI).

### SSH, kubectl, and databases → Teleport, always

You've already built most of this. `infrastructure/base/teleport/config/roles.yaml`
has a `db-access` role enumerating every database. Finish it:

- Register both CNPG clusters as Teleport databases (via `TeleportDatabase` CRs, or
  the `db_service` config), so `tsh db ls` shows `apps-cluster` and `data-cluster`.
- Then from **any** device: `tsh login --proxy=teleport.${personal_domain}` once,
  and after that `tsh db connect apps-cluster --db-user=sonarr --db-name=sonarr`.
- DBeaver / DataGrip / pgAdmin work through `tsh proxy db` on a local port.

Why this is the answer to "easier to connect to my databases from my devices":

- **No WireGuard required.** Teleport's proxy is reachable through the tunnel.
- **No passwords to look up.** Teleport issues short-lived certs; you never touch
  1Password to open a psql session.
- **It's audited**, and it works the same for your phone (Teleport Connect) as your
  laptop.
- Your `db-access` role already lists the db names — the hard part is done.

The README you wrote at `infrastructure/base/teleport/README.md` shows you've
already fought the CA bundle problem. Capture the resolution there once it works;
that's the highest-value doc in the repo right now.

### Cluster admin → Headlamp + OIDC (already done, use it)

Your k3s API server is configured with Authentik OIDC
(`ansible/inventories/k3s_cluster.yml`, `oidc-issuer-url`, `oidc-groups-claim`), and
Headlamp is deployed with RBAC. That's a genuinely nice setup — a phone-friendly
cluster UI behind SSO. Make sure `apps/base/headlamp/rbac.yaml` maps your Authentik
group properly so you don't fall back to a service-account token.

---

## Make Homepage the actual index

`apps/base/homepage/config/services.yaml` is already a good manifest of everything
— but it's hand-maintained, and it lists things that don't exist (Tdarr, Huntarr,
Overseerr under a `overseerr.` hostname while your app is `seerr`).

Homepage supports **Kubernetes service discovery via annotations**. Switch to it:

```yaml
# on each Ingress
metadata:
  annotations:
    gethomepage.dev/enabled: "true"
    gethomepage.dev/group: Media
    gethomepage.dev/name: Sonarr
    gethomepage.dev/icon: sonarr
    gethomepage.dev/description: TV shows
```

Then `services.yaml` shrinks to just the non-Kubernetes entries (Proxmox, Cockpit,
the Synology). Apps appear on your dashboard the moment they deploy and disappear
when you remove them. Combined with the ingress standardization in
[04-templating.md](04-templating.md), adding an app auto-registers it in the one
place you actually look from your phone.

Add the `gethomepage.dev/*` annotations to your `http-route` component so it's
automatic.

---

## A note on TLS inside the cluster

93 of 97 IngressRoutes use `entryPoints: [web]` — plain HTTP on :80. Traffic from
Cloudflare's tunnel to Traefik is over the tunnel (fine), but anything reaching
Traefik over WireGuard hits it in plaintext, and pod-to-Traefik is plaintext.

You already have a wildcard cert (`infrastructure/base/traefik/certificates.yaml`
covers all three domains) and a `TLSStore` making it the default. So switching to
`websecure` is nearly free:

```yaml
  entryPoints: [websecure]
  tls: {}     # picks up the default TLSStore cert
```

Do it as part of the ingress standardization. Also add a global HTTP→HTTPS redirect
in the Traefik values so you can't accidentally leave one on :80.

---

## Summary: the rules to write on the wall

| I want to... | Use |
| --- | --- |
| Open a web app from any device | `https://<app>.thewhitelodge.org` (tunnel → Traefik), SSO via Authentik |
| Query a database | `tsh db connect` |
| Get a shell on the node | `tsh ssh` |
| Poke at the cluster | Headlamp, or `kubectl` with OIDC |
| Reach something on the LAN side | WireGuard, and it should be rare |

Four rules. Right now there are four *mechanisms* and no rules, which is the
difference.
