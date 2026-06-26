# Cloudnative PG

## Naming conventions

| File                  | Resource Kind        | Name                      |
| --------------------- | -------------------- | ------------------------- |
| `helmrepository.yaml` | HelmRepository       | `cloudnative-pg`          |
| `helmrelease.yaml`    | HelmRelease          | `cloudnative-pg`          |
| `cluster.yaml`        | Cluster              | `app-cluster`             |
| `secret.yaml`         | Secret               | `app-credentials`         |
| `certificates.yaml`   | Issuer               | `app-cluster-issuer`      |
| `certificates.yaml`   | Certificate (server) | `app-cluster-server-cert` |
| `certificates.yaml`   | Certificate (client) | `app-cluster-client-cert` |
| `namespace.yaml`      | Namespace            | `cnpg-apps`               |
