# Feedback: `kubernetes/` structure, secrets, and lakehouse

Written 2026-08-12. Nothing outside this folder was modified.

## What I looked at

`kubernetes/` contains **985 files**. Breakdown:

| Directory         | Files | Verdict                                                  |
| ----------------- | ----- | -------------------------------------------------------- |
| `apps/`           | 406   | Real, but three different app-authoring styles mixed      |
| `data-lakehouse/` | 384   | **~90% is duplicated filler** — this is your main problem |
| `infrastructure/` | 115   | Real and mostly good                                      |
| `core/`           | 38    | Real, overlaps with `infrastructure/`                     |
| `clusters/`       | 24    | Good — this part is clean                                 |
| `monitoring/`     | 11    | Mostly `.gitkeep`, disabled in production                 |
| `external-secrets/` | 7   | Good bones, underused                                     |

The single most important thing I found: **44 of your lakehouse `deployment.yaml`
files are byte-identical copies of the FileFlows deployment** (`namespace: media`,
`image: revenz/fileflows`). With their sibling `service.yaml` / `ingress-route.yaml`
/ `pvc-config.yaml` / `secret.yaml`, that is roughly **250 files of pure noise**.
That is why ripgrep, Telescope, and your own brain are overwhelmed — a quarter of
your Kubernetes repo means nothing.

## Read these in order

1. **[01-quick-wins.md](01-quick-wins.md)** — a weekend's worth of changes that
   cut the repo roughly in half. Start here. Includes the real bugs I found.
2. **[02-structure.md](02-structure.md)** — the layout I'd move to, and why
   `base/overlays` is costing you more than it gives you on a single cluster.
3. **[03-secrets.md](03-secrets.md)** — how to get from 50+ hand-managed 1Password
   items down to ~15, and stop maintaining two secret systems at once.
4. **[04-templating.md](04-templating.md)** — killing the copy-paste (the \*arr
   stack is 9 near-identical 90-line files; 71 `HelmRepository` files exist).
5. **[05-access.md](05-access.md)** — reaching apps and Postgres from your laptop
   and phone without thinking about it.
6. **[06-reliability.md](06-reliability.md)** — Flux dependency wiring, the
   `wait: true` trap you're currently in, and a debugging playbook.
7. **[07-lakehouse-getting-started.md](07-lakehouse-getting-started.md)** — what
   each of those 60 tools actually does, which ones you should run, and a concrete
   first pipeline for ABQ open data, NM legislature data, and your bills.

## The three sentences version

Delete the lakehouse filler and collapse `base/overlays` — that alone takes
`kubernetes/` from 985 files to roughly 400 and makes the tree navigable again.
Move every secret to External Secrets with **one 1Password item per app** and let
CloudNativePG generate its own database passwords instead of you inventing them.
Then run a *small* lakehouse — ClickHouse + Postgres + DuckDB + dbt + one
orchestrator — instead of the twelve-category enterprise stack you've scaffolded,
because you are on a **single-node k3s VPS** and Trino/Spark/Kafka/DataHub will
not fit.

## The thing I want you to internalize

Your `clusters/production/*.yaml` layer is genuinely well done — variable
substitution, SOPS decryption, `dependsOn` ordering, per-layer Flux Kustomizations.
The problem is not your GitOps skill. The problem is that you have been using the
filesystem as a to-do list. `data-lakehouse/base/query/starburst/` doesn't remind
you to try Starburst — it just makes `sonarr` harder to find. Move the wishlist
into a markdown file and let the directory tree describe **only what is deployed**.
