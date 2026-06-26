# Cloudnative PG

## Notes

Adding the below to metadata triggers to a reload on changes to the file. Useful for situations where otherwise a resource would need to be deleted and a deployment restarted with `kubectl rollout restart`

```yaml
labels:
  cnpg.io/reload: ""
```

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
